use thiserror::Error;

pub type Result<T> = std::result::Result<T, VaultError>;

#[derive(Debug, Error)]
pub enum VaultError {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),

    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),

    #[error("invalid URL: {0}")]
    Url(#[from] url::ParseError),

    #[error("storage error: {0}")]
    Storage(String),

    #[error("failed to open KeePass database: {0}")]
    DatabaseOpen(String),

    #[error("group not found: {0}")]
    GroupNotFound(String),

    #[error("entry not found: {0}")]
    EntryNotFound(String),

    #[error("attachment not found: {0}")]
    AttachmentNotFound(String),

    #[error("history item not found: {0}")]
    HistoryNotFound(String),

    #[error("invalid request: {0}")]
    InvalidRequest(String),

    #[error("conflict: {0}")]
    Conflict(String),

    #[error("failed to save KeePass database: {0}")]
    DatabaseSave(String),
}
