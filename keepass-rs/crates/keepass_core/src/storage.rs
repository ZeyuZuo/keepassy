use crate::dto::RemoteMetadata;
use crate::error::{Result, VaultError};
use async_trait::async_trait;
use reqwest::header::{CONTENT_LENGTH, ETAG, IF_MATCH, LAST_MODIFIED};
use std::fmt;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::fs;
use tokio::io::AsyncWriteExt;
use url::Url;

// --- StorageBackend trait ---

#[async_trait]
pub trait StorageBackend: Send + Sync {
    /// Read the full contents of the database.
    async fn read(&self) -> Result<Vec<u8>>;

    /// Write bytes to the database, replacing it entirely.
    async fn write(&self, bytes: &[u8]) -> Result<()>;

    /// Return remote metadata such as ETag and Last-Modified. Local storage
    /// returns `None`.
    async fn metadata(&self) -> Result<Option<RemoteMetadata>>;

    /// Human-readable identifier for this storage (file path or URL).
    fn source(&self) -> String;
}

// --- LocalFileStorage ---

#[derive(Debug, Clone)]
pub struct LocalFileStorage {
    path: PathBuf,
}

impl LocalFileStorage {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Self { path: path.into() }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

#[async_trait]
impl StorageBackend for LocalFileStorage {
    async fn read(&self) -> Result<Vec<u8>> {
        Ok(fs::read(&self.path).await?)
    }

    async fn write(&self, bytes: &[u8]) -> Result<()> {
        write_file_atomically(&self.path, bytes).await
    }

    async fn metadata(&self) -> Result<Option<RemoteMetadata>> {
        Ok(None)
    }

    fn source(&self) -> String {
        self.path.display().to_string()
    }
}

// --- WebDavCredentials ---

/// Credentials for WebDAV basic authentication.
///
/// The `Debug` implementation redacts the password.
pub struct WebDavCredentials {
    pub username: String,
    pub password: String,
}

impl WebDavCredentials {
    pub fn new(username: impl Into<String>, password: impl Into<String>) -> Self {
        Self {
            username: username.into(),
            password: password.into(),
        }
    }
}

impl fmt::Debug for WebDavCredentials {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("WebDavCredentials")
            .field("username", &self.username)
            .field("password", &"[redacted]")
            .finish()
    }
}

impl Clone for WebDavCredentials {
    fn clone(&self) -> Self {
        Self {
            username: self.username.clone(),
            password: self.password.clone(),
        }
    }
}

// --- WebDavConfig ---

/// Configuration for a WebDAV storage backend.
///
/// Bundles the remote URL, optional credentials, and safety limits.
/// The `Debug` implementation redacts the credentials.
pub struct WebDavConfig {
    /// Full URL to the `.kdbx` file. Must use `http` or `https` scheme.
    pub url: Url,

    /// Optional HTTP basic-auth credentials.
    pub credentials: Option<WebDavCredentials>,

    /// Request timeout for individual HTTP calls. Defaults to 30 seconds if
    /// `None`.
    pub timeout: Option<Duration>,

    /// Maximum number of bytes accepted on download. Exceeding this limit
    /// produces a [`VaultError::Storage`] error. `None` means no limit.
    pub max_size_bytes: Option<u64>,
}

impl WebDavConfig {
    pub fn new(url: impl AsRef<str>) -> Result<Self> {
        let url = Url::parse(url.as_ref())?;
        let scheme = url.scheme();
        if scheme != "http" && scheme != "https" {
            return Err(VaultError::Storage(format!(
                "unsupported URL scheme {scheme:?}, expected http or https"
            )));
        }
        Ok(Self {
            url,
            credentials: None,
            timeout: None,
            max_size_bytes: None,
        })
    }

    pub fn with_credentials(mut self, credentials: WebDavCredentials) -> Self {
        self.credentials = Some(credentials);
        self
    }

    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.timeout = Some(timeout);
        self
    }

    pub fn with_max_size(mut self, max_size_bytes: u64) -> Self {
        self.max_size_bytes = Some(max_size_bytes);
        self
    }
}

impl fmt::Debug for WebDavConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("WebDavConfig")
            .field("url", &self.url)
            .field(
                "credentials",
                &self.credentials.as_ref().map(|_| "[redacted]"),
            )
            .field("timeout", &self.timeout)
            .field("max_size_bytes", &self.max_size_bytes)
            .finish()
    }
}

impl Clone for WebDavConfig {
    fn clone(&self) -> Self {
        Self {
            url: self.url.clone(),
            credentials: self.credentials.clone(),
            timeout: self.timeout,
            max_size_bytes: self.max_size_bytes,
        }
    }
}

// --- WebDavStorage ---

/// WebDAV storage backend.
///
/// Downloads the database on [`read`](StorageBackend::read) and uploads on
/// [`write`](StorageBackend::write). Tracks the ETag from the last successful
/// read or metadata call, and uses `If-Match` on write to detect remote
/// conflicts.
#[derive(Debug, Clone)]
pub struct WebDavStorage {
    client: reqwest::Client,
    config: WebDavConfig,
    /// ETag captured from the last `read` or `metadata` response. Used for
    /// `If-Match` on `write`.
    last_etag: Arc<Mutex<Option<String>>>,
}

impl WebDavStorage {
    pub fn new(config: WebDavConfig) -> Self {
        let builder =
            reqwest::Client::builder().timeout(config.timeout.unwrap_or(Duration::from_secs(30)));
        Self {
            client: builder.build().expect("reqwest::Client::new infallible"),
            config,
            last_etag: Arc::new(Mutex::new(None)),
        }
    }

    fn with_auth(&self, builder: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        match &self.config.credentials {
            Some(creds) => builder.basic_auth(&creds.username, Some(&creds.password)),
            None => builder,
        }
    }

    #[cfg(test)]
    fn build_request(&self, method: reqwest::Method) -> Result<reqwest::Request> {
        self.with_auth(self.client.request(method, self.config.url.clone()))
            .build()
            .map_err(VaultError::Http)
    }

    #[cfg(test)]
    fn build_write_request(&self, bytes: &[u8]) -> Result<reqwest::Request> {
        let mut req = self.with_auth(
            self.client
                .put(self.config.url.clone())
                .body(bytes.to_vec()),
        );
        if let Ok(guard) = self.last_etag.lock() {
            if let Some(ref etag) = *guard {
                req = req.header(IF_MATCH, etag.as_str());
            }
        }
        req.build().map_err(VaultError::Http)
    }

    fn store_etag(&self, headers: &reqwest::header::HeaderMap) {
        if let Some(etag) = header_to_string(headers.get(ETAG)) {
            if let Ok(mut guard) = self.last_etag.lock() {
                *guard = Some(etag);
            }
        }
    }
}

#[async_trait]
impl StorageBackend for WebDavStorage {
    async fn read(&self) -> Result<Vec<u8>> {
        let response = self
            .with_auth(self.client.get(self.config.url.clone()))
            .send()
            .await?
            .error_for_status()?;

        // Check Content-Length against max_size_bytes before reading body
        if let Some(max) = self.config.max_size_bytes {
            if let Some(len) = response.content_length() {
                if len > max {
                    return Err(VaultError::Storage(format!(
                        "download size {len} bytes exceeds limit of {max} bytes"
                    )));
                }
            }
        }

        self.store_etag(response.headers());

        let bytes = response.bytes().await?.to_vec();

        // Check actual size if Content-Length was not available
        if let Some(max) = self.config.max_size_bytes {
            if bytes.len() as u64 > max {
                return Err(VaultError::Storage(format!(
                    "download size {} bytes exceeds limit of {max} bytes",
                    bytes.len()
                )));
            }
        }

        Ok(bytes)
    }

    async fn write(&self, bytes: &[u8]) -> Result<()> {
        let mut req = self.with_auth(
            self.client
                .put(self.config.url.clone())
                .body(bytes.to_vec()),
        );

        // Use If-Match with the last known ETag for conflict detection
        if let Ok(guard) = self.last_etag.lock() {
            if let Some(ref etag) = *guard {
                req = req.header(IF_MATCH, etag.as_str());
            }
        }

        let response = req.send().await?;

        check_write_status(response.status())?;

        let response = response.error_for_status()?;
        self.store_etag(response.headers());

        Ok(())
    }

    async fn metadata(&self) -> Result<Option<RemoteMetadata>> {
        let response = match self
            .with_auth(self.client.head(self.config.url.clone()))
            .send()
            .await
        {
            Ok(resp) => resp,
            Err(err) => {
                // If HEAD is not supported, treat metadata as unavailable
                // rather than failing the whole operation.
                if err.is_connect() || err.is_timeout() {
                    return Err(VaultError::Http(err));
                }
                return Ok(None);
            }
        };

        // Non-2xx status for HEAD → metadata unavailable, not fatal
        if !response.status().is_success() {
            return Ok(None);
        }

        self.store_etag(response.headers());

        let headers = response.headers();
        let content_length = headers
            .get(CONTENT_LENGTH)
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.parse::<u64>().ok());

        Ok(Some(RemoteMetadata {
            etag: header_to_string(headers.get(ETAG)),
            last_modified: header_to_string(headers.get(LAST_MODIFIED)),
            content_length,
        }))
    }

    fn source(&self) -> String {
        self.config.url.to_string()
    }
}

fn header_to_string(value: Option<&reqwest::header::HeaderValue>) -> Option<String> {
    value.and_then(|v| v.to_str().ok()).map(ToOwned::to_owned)
}

fn check_write_status(status: reqwest::StatusCode) -> Result<()> {
    if status == reqwest::StatusCode::PRECONDITION_FAILED {
        return Err(VaultError::Conflict(
            "remote database has been modified since it was opened; re-open and try again"
                .to_string(),
        ));
    }

    Ok(())
}

async fn write_file_atomically(path: &Path, bytes: &[u8]) -> Result<()> {
    let temp_path = atomic_temp_path(path);
    let result = async {
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&temp_path)
            .await?;
        file.write_all(bytes).await?;
        file.sync_all().await?;
        drop(file);
        fs::rename(&temp_path, path).await?;
        Ok(())
    }
    .await;

    if result.is_err() {
        let _ = fs::remove_file(&temp_path).await;
    }
    result.map_err(VaultError::Io)
}

fn atomic_temp_path(path: &Path) -> PathBuf {
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("vault.kdbx");
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or_default();
    path.with_file_name(format!(".{file_name}.tmp-{}-{nonce}", std::process::id()))
}

// --- Tests ---

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn local_storage_round_trip() {
        let path = std::env::temp_dir().join(format!(
            "keepass-rs-local-storage-{}.bin",
            std::process::id()
        ));
        let storage = LocalFileStorage::new(&path);

        storage.write(b"abc").await.unwrap();
        assert_eq!(storage.read().await.unwrap(), b"abc");

        let _ = fs::remove_file(path).await;
    }

    #[test]
    fn webdav_config_rejects_non_http_scheme() {
        assert!(WebDavConfig::new("ftp://example.com/db.kdbx").is_err());
    }

    #[test]
    fn webdav_config_accepts_http_and_https() {
        assert!(WebDavConfig::new("http://example.com/db.kdbx").is_ok());
        assert!(WebDavConfig::new("https://example.com/db.kdbx").is_ok());
    }

    #[test]
    fn webdav_config_debug_redacts_credentials() {
        let config = WebDavConfig::new("https://example.com/db.kdbx")
            .unwrap()
            .with_credentials(WebDavCredentials::new("alice", "secret123"));
        let debug = format!("{config:?}");
        assert!(debug.contains("example.com"));
        assert!(debug.contains("db.kdbx"));
        assert!(debug.contains("[redacted]"));
        assert!(!debug.contains("secret123"));
    }

    #[test]
    fn webdav_credentials_debug_redacts_password() {
        let creds = WebDavCredentials::new("alice", "secret123");
        let debug = format!("{creds:?}");
        assert!(debug.contains("alice"));
        assert!(debug.contains("[redacted]"));
        assert!(!debug.contains("secret123"));
    }

    #[test]
    fn webdav_config_builder_pattern() {
        let config = WebDavConfig::new("https://example.com/db.kdbx")
            .unwrap()
            .with_credentials(WebDavCredentials::new("u", "p"))
            .with_timeout(Duration::from_secs(60))
            .with_max_size(50_000_000);

        assert_eq!(config.timeout, Some(Duration::from_secs(60)));
        assert_eq!(config.max_size_bytes, Some(50_000_000));
        assert!(config.credentials.is_some());
    }

    #[test]
    fn webdav_get_request_includes_basic_auth() {
        let config = WebDavConfig::new("https://example.com/vault.kdbx")
            .unwrap()
            .with_credentials(WebDavCredentials::new("user", "pass"));

        let storage = WebDavStorage::new(config);

        let request = storage.build_request(reqwest::Method::GET).unwrap();
        assert_eq!(request.method(), reqwest::Method::GET);
        assert_eq!(request.url().as_str(), "https://example.com/vault.kdbx");
        assert!(request
            .headers()
            .contains_key(reqwest::header::AUTHORIZATION));
    }

    #[test]
    fn webdav_default_debug_redacts_password() {
        // Verify the derive(Debug) on WebDavStorage does not leak credentials
        let config = WebDavConfig::new("https://example.com/db.kdbx")
            .unwrap()
            .with_credentials(WebDavCredentials::new("alice", "secret123"));
        let storage = WebDavStorage::new(config);
        let debug = format!("{storage:?}");
        assert!(!debug.contains("secret123"));
        assert!(debug.contains("[redacted]"));
    }

    #[test]
    fn webdav_put_request_includes_if_match() {
        let storage =
            WebDavStorage::new(WebDavConfig::new("https://example.com/vault.kdbx").unwrap());
        *storage.last_etag.lock().unwrap() = Some("\"old\"".to_string());

        let request = storage.build_write_request(b"abc").unwrap();

        assert_eq!(request.method(), reqwest::Method::PUT);
        assert_eq!(
            request
                .headers()
                .get(IF_MATCH)
                .and_then(|v| v.to_str().ok()),
            Some("\"old\"")
        );
    }

    #[test]
    fn webdav_store_etag_updates_cached_value() {
        let storage =
            WebDavStorage::new(WebDavConfig::new("https://example.com/vault.kdbx").unwrap());
        let mut headers = reqwest::header::HeaderMap::new();
        headers.insert(ETAG, "\"new\"".parse().unwrap());

        storage.store_etag(&headers);

        assert_eq!(
            storage.last_etag.lock().unwrap().as_deref(),
            Some("\"new\"")
        );
    }

    #[test]
    fn webdav_precondition_failed_status_maps_to_conflict() {
        let err = check_write_status(reqwest::StatusCode::PRECONDITION_FAILED).unwrap_err();
        assert!(matches!(err, VaultError::Conflict(_)));
    }
}
