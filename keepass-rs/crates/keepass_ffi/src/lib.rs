//! Plain C ABI adapter for desktop shells that cannot call Rust APIs directly.
//!
//! The adapter keeps all KeePass behavior in `keepass_core`. FFI callers pass
//! UTF-8 C strings and receive JSON C strings. Session state is held behind an
//! opaque handle returned by `keepassy_open_local`.

use keepass_core::{
    CreateEntryRequest, CreateGroupRequest, MoveEntryRequest, RenameGroupRequest,
    Result as CoreResult, SetCustomFieldRequest, UpdateEntryRequest, UpsertAttachmentRequest,
    VaultError, VaultService, VaultSession, WebDavConfig, WebDavCredentials, KEEPASS_CORE_VERSION,
};
use serde::{Deserialize, Serialize};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::ptr;
use std::sync::Mutex;
use tokio::runtime::Runtime;

/// Opaque session handle owned by FFI callers.
pub struct KeepassYSession {
    inner: Mutex<VaultSession>,
    runtime: Runtime,
}

/// Standard response for all FFI calls.
///
/// `status == 0` means success. Non-zero status means error. `json` is always
/// owned by the caller and must be released with [`keepassy_string_free`].
/// `session` is set only by open calls and must be released with
/// [`keepassy_session_close`].
#[repr(C)]
pub struct KeepassYFfiResult {
    pub status: i32,
    pub session: *mut KeepassYSession,
    pub json: *mut c_char,
}

#[derive(Serialize)]
struct ErrorBody {
    error: String,
}

#[derive(Serialize)]
struct SaveBody {
    saved: bool,
    dirty: bool,
}

#[derive(Serialize)]
struct DirtyBody {
    dirty: bool,
}

#[derive(Serialize)]
struct VersionBody {
    keepass_core: &'static str,
    keepass_ffi: &'static str,
}

#[derive(Deserialize)]
struct OpenWebDavRequest {
    url: String,
    username: Option<String>,
    password: Option<String>,
    keyfile_path: Option<String>,
    max_size_bytes: Option<u64>,
}

#[derive(Deserialize)]
struct CreateLocalRequest {
    path: String,
    keyfile_path: Option<String>,
}

/// Open a local `.kdbx` file.
///
/// `keyfile_path` may be null for password-only databases.
#[no_mangle]
pub extern "C" fn keepassy_open_local(
    path: *const c_char,
    master_password: *const c_char,
    keyfile_path: *const c_char,
) -> KeepassYFfiResult {
    let result = (|| {
        let path = read_required_c_string(path, "path")?;
        let master_password = read_required_c_string(master_password, "master_password")?;
        let keyfile_path = read_optional_c_string(keyfile_path)?;
        let keyfile = match keyfile_path {
            Some(path) => Some(std::fs::read(path).map_err(VaultError::Io)?),
            None => None,
        };

        let runtime = Runtime::new().map_err(VaultError::Io)?;
        let service = VaultService;
        let session = match keyfile.as_deref() {
            Some(keyfile) => runtime.block_on(service.open_local_with_keyfile(
                PathBuf::from(path),
                master_password,
                keyfile,
            ))?,
            None => runtime.block_on(service.open_local(PathBuf::from(path), master_password))?,
        };
        let snapshot = session.snapshot();
        Ok((session, runtime, snapshot))
    })();

    match result {
        Ok((session, runtime, snapshot)) => {
            let handle = Box::into_raw(Box::new(KeepassYSession {
                inner: Mutex::new(session),
                runtime,
            }));
            success_with_session(handle, snapshot)
        }
        Err(err) => error_result(err),
    }
}

/// Return backend component versions for startup diagnostics.
#[no_mangle]
pub extern "C" fn keepassy_backend_version_json() -> KeepassYFfiResult {
    success(VersionBody {
        keepass_core: KEEPASS_CORE_VERSION,
        keepass_ffi: env!("CARGO_PKG_VERSION"),
    })
}

/// Open a WebDAV-hosted `.kdbx` file.
///
/// `request_json` must contain `url` and may contain `username`, `password`,
/// `keyfile_path`, and `max_size_bytes`.
#[no_mangle]
pub extern "C" fn keepassy_open_webdav(
    request_json: *const c_char,
    master_password: *const c_char,
) -> KeepassYFfiResult {
    let result = (|| {
        let request = read_json_request::<OpenWebDavRequest>(request_json, "request_json")?;
        let master_password = read_required_c_string(master_password, "master_password")?;
        let mut config = WebDavConfig::new(request.url)?;
        if request.username.as_deref().is_some_and(|v| !v.is_empty())
            || request.password.as_deref().is_some_and(|v| !v.is_empty())
        {
            config = config.with_credentials(WebDavCredentials::new(
                request.username.unwrap_or_default(),
                request.password.unwrap_or_default(),
            ));
        }
        if let Some(max_size_bytes) = request.max_size_bytes {
            config = config.with_max_size(max_size_bytes);
        }
        let keyfile = match request.keyfile_path {
            Some(path) if !path.trim().is_empty() => {
                Some(std::fs::read(path).map_err(VaultError::Io)?)
            }
            _ => None,
        };

        let runtime = Runtime::new().map_err(VaultError::Io)?;
        let service = VaultService;
        let session = match keyfile.as_deref() {
            Some(keyfile) => runtime.block_on(service.open_webdav_with_keyfile(
                config,
                master_password,
                keyfile,
            ))?,
            None => runtime.block_on(service.open_webdav(config, master_password))?,
        };
        let snapshot = session.snapshot();
        Ok((session, runtime, snapshot))
    })();

    match result {
        Ok((session, runtime, snapshot)) => {
            let handle = Box::into_raw(Box::new(KeepassYSession {
                inner: Mutex::new(session),
                runtime,
            }));
            success_with_session(handle, snapshot)
        }
        Err(err) => error_result(err),
    }
}

/// Create a new empty KeePass database, write it to `path`, and return an
/// open session with a snapshot.
///
/// `request_json` must contain `"path"` and may contain `"keyfile_path"`.
#[no_mangle]
pub extern "C" fn keepassy_create_local(
    request_json: *const c_char,
    master_password: *const c_char,
) -> KeepassYFfiResult {
    let result = (|| {
        let request = read_json_request::<CreateLocalRequest>(request_json, "request_json")?;
        let master_password = read_required_c_string(master_password, "master_password")?;
        let keyfile = match request.keyfile_path.as_deref() {
            Some(path) if !path.trim().is_empty() => {
                Some(std::fs::read(path).map_err(VaultError::Io)?)
            }
            _ => None,
        };

        let runtime = Runtime::new().map_err(VaultError::Io)?;
        let service = VaultService;
        let session = match keyfile.as_deref() {
            Some(keyfile) => runtime.block_on(service.create_local_with_keyfile(
                PathBuf::from(request.path),
                master_password,
                keyfile,
            ))?,
            None => runtime
                .block_on(service.create_local(PathBuf::from(request.path), master_password))?,
        };
        let snapshot = session.snapshot();
        Ok((session, runtime, snapshot))
    })();

    match result {
        Ok((session, runtime, snapshot)) => {
            let handle = Box::into_raw(Box::new(KeepassYSession {
                inner: Mutex::new(session),
                runtime,
            }));
            success_with_session(handle, snapshot)
        }
        Err(err) => error_result(err),
    }
}

/// Release a session returned by `keepassy_open_local`.
///
/// # Safety
///
/// `session` must be either null or a pointer returned by this crate from
/// `keepassy_open_local`, and it must be released at most once.
#[no_mangle]
pub unsafe extern "C" fn keepassy_session_close(session: *mut KeepassYSession) {
    if !session.is_null() {
        // SAFETY: `session` must be a pointer returned by `Box::into_raw` from
        // this crate. Reconstructing the Box drops exactly one handle.
        unsafe {
            drop(Box::from_raw(session));
        }
    }
}

/// Release a JSON string returned by this crate.
///
/// # Safety
///
/// `value` must be either null or a pointer returned by this crate, and it must
/// be released at most once.
#[no_mangle]
pub unsafe extern "C" fn keepassy_string_free(value: *mut c_char) {
    if !value.is_null() {
        // SAFETY: `value` must be a pointer returned by `CString::into_raw` from
        // this crate. Reconstructing the CString drops exactly one allocation.
        unsafe {
            drop(CString::from_raw(value));
        }
    }
}

#[no_mangle]
pub extern "C" fn keepassy_snapshot_json(session: *mut KeepassYSession) -> KeepassYFfiResult {
    with_session(session, |vault| Ok(vault.snapshot()))
}

#[no_mangle]
pub extern "C" fn keepassy_group_tree_json(session: *mut KeepassYSession) -> KeepassYFfiResult {
    with_session(session, |vault| Ok(vault.group_tree().clone()))
}

#[no_mangle]
pub extern "C" fn keepassy_entries_json(
    session: *mut KeepassYSession,
    group_id: *const c_char,
) -> KeepassYFfiResult {
    let group_id = match read_required_c_string(group_id, "group_id") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| {
        Ok(vault.entries_for_group(&group_id)?.to_vec())
    })
}

#[no_mangle]
pub extern "C" fn keepassy_entry_detail_json(
    session: *mut KeepassYSession,
    entry_id: *const c_char,
) -> KeepassYFfiResult {
    let entry_id = match read_required_c_string(entry_id, "entry_id") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| vault.entry_detail(&entry_id))
}

#[no_mangle]
pub extern "C" fn keepassy_create_entry_json(
    session: *mut KeepassYSession,
    request_json: *const c_char,
) -> KeepassYFfiResult {
    let request = match read_json_request::<CreateEntryRequest>(request_json, "request_json") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| vault.create_entry(request))
}

#[no_mangle]
pub extern "C" fn keepassy_update_entry_json(
    session: *mut KeepassYSession,
    request_json: *const c_char,
) -> KeepassYFfiResult {
    let request = match read_json_request::<UpdateEntryRequest>(request_json, "request_json") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| vault.update_entry(request))
}

#[no_mangle]
pub extern "C" fn keepassy_delete_entry_json(
    session: *mut KeepassYSession,
    entry_id: *const c_char,
) -> KeepassYFfiResult {
    let entry_id = match read_required_c_string(entry_id, "entry_id") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| {
        vault.delete_entry(&entry_id)?;
        Ok(vault.snapshot())
    })
}

#[no_mangle]
pub extern "C" fn keepassy_restore_entry_json(
    session: *mut KeepassYSession,
    entry_id: *const c_char,
) -> KeepassYFfiResult {
    let entry_id = match read_required_c_string(entry_id, "entry_id") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| {
        vault.restore_entry(&entry_id)?;
        Ok(vault.snapshot())
    })
}

#[no_mangle]
pub extern "C" fn keepassy_permanently_delete_entry_json(
    session: *mut KeepassYSession,
    entry_id: *const c_char,
) -> KeepassYFfiResult {
    let entry_id = match read_required_c_string(entry_id, "entry_id") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| {
        vault.permanently_delete_entry(&entry_id)?;
        Ok(vault.snapshot())
    })
}

#[no_mangle]
pub extern "C" fn keepassy_empty_recycle_bin_json(
    session: *mut KeepassYSession,
) -> KeepassYFfiResult {
    with_session(session, |vault| {
        vault.empty_recycle_bin()?;
        Ok(vault.snapshot())
    })
}

#[no_mangle]
pub extern "C" fn keepassy_set_custom_field_json(
    session: *mut KeepassYSession,
    request_json: *const c_char,
) -> KeepassYFfiResult {
    let request = match read_json_request::<SetCustomFieldRequest>(request_json, "request_json") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| vault.set_custom_field(request))
}

#[no_mangle]
pub extern "C" fn keepassy_delete_custom_field_json(
    session: *mut KeepassYSession,
    entry_id: *const c_char,
    key: *const c_char,
) -> KeepassYFfiResult {
    let entry_id = match read_required_c_string(entry_id, "entry_id") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    let key = match read_required_c_string(key, "key") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| vault.delete_custom_field(&entry_id, &key))
}

#[no_mangle]
pub extern "C" fn keepassy_upsert_attachment_json(
    session: *mut KeepassYSession,
    request_json: *const c_char,
) -> KeepassYFfiResult {
    let request = match read_json_request::<UpsertAttachmentRequest>(request_json, "request_json") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| vault.upsert_attachment(request))
}

#[no_mangle]
pub extern "C" fn keepassy_remove_attachment_json(
    session: *mut KeepassYSession,
    entry_id: *const c_char,
    name: *const c_char,
) -> KeepassYFfiResult {
    let entry_id = match read_required_c_string(entry_id, "entry_id") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    let name = match read_required_c_string(name, "name") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| {
        vault.remove_attachment(&entry_id, &name)?;
        Ok(serde_json::Value::Object(Default::default()))
    })
}

#[no_mangle]
pub extern "C" fn keepassy_attachment_bytes_json(
    session: *mut KeepassYSession,
    entry_id: *const c_char,
    name: *const c_char,
) -> KeepassYFfiResult {
    let entry_id = match read_required_c_string(entry_id, "entry_id") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    let name = match read_required_c_string(name, "name") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| vault.attachment_bytes(&entry_id, &name))
}

#[no_mangle]
pub extern "C" fn keepassy_entry_history_json(
    session: *mut KeepassYSession,
    entry_id: *const c_char,
) -> KeepassYFfiResult {
    let entry_id = match read_required_c_string(entry_id, "entry_id") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| vault.entry_history(&entry_id))
}

#[no_mangle]
pub extern "C" fn keepassy_entry_history_detail_json(
    session: *mut KeepassYSession,
    entry_id: *const c_char,
    index: i32,
) -> KeepassYFfiResult {
    let entry_id = match read_required_c_string(entry_id, "entry_id") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    let index = index as usize;
    with_session(session, |vault| {
        vault.entry_history_detail(&entry_id, index)
    })
}

#[no_mangle]
pub extern "C" fn keepassy_is_dirty(session: *mut KeepassYSession) -> KeepassYFfiResult {
    with_ffi_session(session, |ffi_session| {
        let vault = ffi_session
            .inner
            .lock()
            .map_err(|_| VaultError::Storage("session lock poisoned".to_string()))?;
        Ok(DirtyBody {
            dirty: vault.is_dirty(),
        })
    })
}

#[no_mangle]
pub extern "C" fn keepassy_move_entry_json(
    session: *mut KeepassYSession,
    request_json: *const c_char,
) -> KeepassYFfiResult {
    let request = match read_json_request::<MoveEntryRequest>(request_json, "request_json") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| {
        vault.move_entry(&request.entry_id, &request.target_group_id)
    })
}

#[no_mangle]
pub extern "C" fn keepassy_create_group_json(
    session: *mut KeepassYSession,
    request_json: *const c_char,
) -> KeepassYFfiResult {
    let request = match read_json_request::<CreateGroupRequest>(request_json, "request_json") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| {
        vault.create_group(&request.parent_id, &request.name)
    })
}

#[no_mangle]
pub extern "C" fn keepassy_rename_group_json(
    session: *mut KeepassYSession,
    request_json: *const c_char,
) -> KeepassYFfiResult {
    let request = match read_json_request::<RenameGroupRequest>(request_json, "request_json") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| {
        vault.rename_group(&request.group_id, &request.name)
    })
}

#[no_mangle]
pub extern "C" fn keepassy_delete_group_json(
    session: *mut KeepassYSession,
    group_id: *const c_char,
) -> KeepassYFfiResult {
    let group_id = match read_required_c_string(group_id, "group_id") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| {
        vault.delete_group(&group_id)?;
        Ok(vault.snapshot())
    })
}

#[no_mangle]
pub extern "C" fn keepassy_restore_group_json(
    session: *mut KeepassYSession,
    group_id: *const c_char,
) -> KeepassYFfiResult {
    let group_id = match read_required_c_string(group_id, "group_id") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| {
        vault.restore_group(&group_id)?;
        Ok(vault.snapshot())
    })
}

#[no_mangle]
pub extern "C" fn keepassy_permanently_delete_group_json(
    session: *mut KeepassYSession,
    group_id: *const c_char,
) -> KeepassYFfiResult {
    let group_id = match read_required_c_string(group_id, "group_id") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    with_session(session, |vault| {
        vault.permanently_delete_group(&group_id)?;
        Ok(vault.snapshot())
    })
}

#[no_mangle]
pub extern "C" fn keepassy_change_password_json(
    session: *mut KeepassYSession,
    old_password: *const c_char,
    new_password: *const c_char,
    keyfile_path: *const c_char,
) -> KeepassYFfiResult {
    let old_password = match read_required_c_string(old_password, "old_password") {
        Ok(v) => v,
        Err(e) => return error_result(e),
    };
    let new_password = match read_required_c_string(new_password, "new_password") {
        Ok(v) => v,
        Err(e) => return error_result(e),
    };
    let keyfile_path = match read_optional_c_string(keyfile_path) {
        Ok(v) => v,
        Err(e) => return error_result(e),
    };
    let keyfile = match keyfile_path {
        Some(path) => match std::fs::read(path) {
            Ok(b) => Some(b),
            Err(e) => return error_result(VaultError::Io(e)),
        },
        None => None,
    };
    with_ffi_session(session, |ffi_session| {
        let mut vault = ffi_session
            .inner
            .lock()
            .map_err(|_| VaultError::Storage("session lock poisoned".to_string()))?;
        ffi_session.runtime.block_on(vault.change_password(
            &old_password,
            &new_password,
            keyfile.as_deref(),
        ))?;
        Ok(SaveBody {
            saved: true,
            dirty: vault.is_dirty(),
        })
    })
}

#[no_mangle]
pub extern "C" fn keepassy_save(
    session: *mut KeepassYSession,
    master_password: *const c_char,
    keyfile_path: *const c_char,
) -> KeepassYFfiResult {
    let master_password = match read_required_c_string(master_password, "master_password") {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    let keyfile_path = match read_optional_c_string(keyfile_path) {
        Ok(value) => value,
        Err(err) => return error_result(err),
    };
    let keyfile = match keyfile_path {
        Some(path) => match std::fs::read(path) {
            Ok(bytes) => Some(bytes),
            Err(err) => return error_result(VaultError::Io(err)),
        },
        None => None,
    };

    with_ffi_session(session, |ffi_session| {
        let mut vault = ffi_session
            .inner
            .lock()
            .map_err(|_| VaultError::Storage("session lock poisoned".to_string()))?;
        match keyfile.as_deref() {
            Some(keyfile) => ffi_session
                .runtime
                .block_on(vault.save_with_keyfile(&master_password, keyfile))?,
            None => ffi_session.runtime.block_on(vault.save(&master_password))?,
        }
        Ok(SaveBody {
            saved: true,
            dirty: vault.is_dirty(),
        })
    })
}

fn with_session<T, F>(session: *mut KeepassYSession, action: F) -> KeepassYFfiResult
where
    T: Serialize,
    F: FnOnce(&mut VaultSession) -> CoreResult<T>,
{
    with_ffi_session(session, |ffi_session| {
        let mut vault = ffi_session
            .inner
            .lock()
            .map_err(|_| VaultError::Storage("session lock poisoned".to_string()))?;
        action(&mut vault)
    })
}

fn with_ffi_session<T, F>(session: *mut KeepassYSession, action: F) -> KeepassYFfiResult
where
    T: Serialize,
    F: FnOnce(&KeepassYSession) -> CoreResult<T>,
{
    if session.is_null() {
        return error_result(VaultError::InvalidRequest(
            "session handle must not be null".to_string(),
        ));
    }
    // SAFETY: Non-null session handles must be created by this crate and remain
    // valid until the caller passes them to `keepassy_session_close`.
    let ffi_session = unsafe { &*session };
    match action(ffi_session) {
        Ok(value) => success(value),
        Err(err) => error_result(err),
    }
}

fn read_json_request<T>(ptr: *const c_char, name: &str) -> CoreResult<T>
where
    T: serde::de::DeserializeOwned,
{
    let json = read_required_c_string(ptr, name)?;
    serde_json::from_str(&json)
        .map_err(|err| VaultError::InvalidRequest(format!("invalid {name}: {err}")))
}

fn read_required_c_string(ptr: *const c_char, name: &str) -> CoreResult<String> {
    read_optional_c_string(ptr)?
        .ok_or_else(|| VaultError::InvalidRequest(format!("{name} pointer must not be null")))
}

fn read_optional_c_string(ptr: *const c_char) -> CoreResult<Option<String>> {
    if ptr.is_null() {
        return Ok(None);
    }
    // SAFETY: The caller must provide a valid, NUL-terminated UTF-8 C string
    // that remains alive for the duration of this call.
    let value = unsafe { CStr::from_ptr(ptr) };
    let value = value
        .to_str()
        .map_err(|err| VaultError::InvalidRequest(format!("invalid UTF-8 string: {err}")))?;
    Ok(Some(value.to_string()))
}

fn success<T: Serialize>(value: T) -> KeepassYFfiResult {
    match serde_json::to_string(&value) {
        Ok(json) => KeepassYFfiResult {
            status: 0,
            session: ptr::null_mut(),
            json: into_c_string(json),
        },
        Err(err) => error_result(VaultError::Storage(err.to_string())),
    }
}

fn success_with_session<T: Serialize>(
    session: *mut KeepassYSession,
    value: T,
) -> KeepassYFfiResult {
    match serde_json::to_string(&value) {
        Ok(json) => KeepassYFfiResult {
            status: 0,
            session,
            json: into_c_string(json),
        },
        Err(err) => {
            // SAFETY: `session` was just allocated by this crate and has not
            // been returned to the caller.
            unsafe {
                keepassy_session_close(session);
            }
            error_result(VaultError::Storage(err.to_string()))
        }
    }
}

fn error_result(err: VaultError) -> KeepassYFfiResult {
    let json = serde_json::to_string(&ErrorBody {
        error: err.to_string(),
    })
    .unwrap_or_else(|_| "{\"error\":\"failed to serialize error\"}".to_string());
    KeepassYFfiResult {
        status: 1,
        session: ptr::null_mut(),
        json: into_c_string(json),
    }
}

fn into_c_string(value: String) -> *mut c_char {
    let sanitized = value.replace('\0', "\\u0000");
    CString::new(sanitized)
        .expect("interior NULs were sanitized")
        .into_raw()
}

#[cfg(test)]
mod tests {
    use super::*;
    use keepass::{Database, DatabaseKey};
    use serde_json::{json, Value};
    use std::io::{Read, Write};
    use std::net::{TcpListener, TcpStream};
    use std::sync::{Arc, Mutex as StdMutex};
    use std::thread;
    use std::time::Duration;

    fn c_string(value: impl AsRef<str>) -> CString {
        CString::new(value.as_ref()).unwrap()
    }

    fn response_json(response: KeepassYFfiResult) -> Value {
        assert_eq!(response.status, 0);
        assert!(!response.json.is_null());
        // SAFETY: Test reads the valid NUL-terminated string returned by this crate.
        let text = unsafe { CStr::from_ptr(response.json) }
            .to_str()
            .unwrap()
            .to_string();
        // SAFETY: `response.json` was returned by this crate and is freed once.
        unsafe {
            keepassy_string_free(response.json);
        }
        serde_json::from_str(&text).unwrap()
    }

    fn response_error(response: KeepassYFfiResult) -> Value {
        assert_ne!(response.status, 0);
        assert!(!response.json.is_null());
        // SAFETY: Test reads the valid NUL-terminated string returned by this crate.
        let text = unsafe { CStr::from_ptr(response.json) }
            .to_str()
            .unwrap()
            .to_string();
        // SAFETY: `response.json` was returned by this crate and is freed once.
        unsafe {
            keepassy_string_free(response.json);
        }
        serde_json::from_str(&text).unwrap()
    }

    fn temp_database() -> (PathBuf, String) {
        let path =
            std::env::temp_dir().join(format!("keepassy-ffi-test-{}.kdbx", std::process::id()));
        let password = "test-password".to_string();
        let bytes = database_bytes(&password);
        std::fs::write(&path, bytes).unwrap();
        (path, password)
    }

    #[test]
    fn backend_version_reports_core_and_ffi_versions() {
        let body = response_json(keepassy_backend_version_json());

        assert_eq!(body["keepass_core"], KEEPASS_CORE_VERSION);
        assert_eq!(body["keepass_ffi"], env!("CARGO_PKG_VERSION"));
    }

    fn database_bytes(password: &str) -> Vec<u8> {
        let db = Database::new(Default::default());
        let mut bytes = Vec::new();
        db.save(&mut bytes, DatabaseKey::new().with_password(password))
            .unwrap();
        bytes
    }

    struct WebDavState {
        bytes: Vec<u8>,
        etag: String,
        conflict_on_put: bool,
        last_put_if_match: Option<String>,
    }

    fn start_webdav_server(
        bytes: Vec<u8>,
        conflict_on_put: bool,
    ) -> (String, Arc<StdMutex<WebDavState>>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let url = format!("http://{}/vault.kdbx", listener.local_addr().unwrap());
        let state = Arc::new(StdMutex::new(WebDavState {
            bytes,
            etag: "\"v1\"".to_string(),
            conflict_on_put,
            last_put_if_match: None,
        }));
        let server_state = Arc::clone(&state);
        thread::spawn(move || {
            for stream in listener.incoming().flatten() {
                handle_webdav_connection(stream, &server_state);
            }
        });
        (url, state)
    }

    fn handle_webdav_connection(mut stream: TcpStream, state: &Arc<StdMutex<WebDavState>>) {
        stream
            .set_read_timeout(Some(Duration::from_secs(2)))
            .unwrap();
        let mut buffer = Vec::new();
        let mut chunk = [0_u8; 4096];
        loop {
            match stream.read(&mut chunk) {
                Ok(0) => break,
                Ok(n) => {
                    buffer.extend_from_slice(&chunk[..n]);
                    if request_complete(&buffer) {
                        break;
                    }
                }
                Err(_) => break,
            }
        }

        let header_end = match find_header_end(&buffer) {
            Some(value) => value,
            None => return,
        };
        let header_text = String::from_utf8_lossy(&buffer[..header_end]);
        let method = header_text
            .lines()
            .next()
            .and_then(|line| line.split_whitespace().next())
            .unwrap_or("");

        match method {
            "HEAD" => {
                let guard = state.lock().unwrap();
                write_response(&mut stream, 200, "OK", &guard.etag, guard.bytes.len(), &[]);
            }
            "GET" => {
                let guard = state.lock().unwrap();
                write_response(
                    &mut stream,
                    200,
                    "OK",
                    &guard.etag,
                    guard.bytes.len(),
                    &guard.bytes,
                );
            }
            "PUT" => {
                let if_match = header_value(&header_text, "if-match");
                let mut guard = state.lock().unwrap();
                guard.last_put_if_match = if_match;
                if guard.conflict_on_put {
                    write_response(&mut stream, 412, "Precondition Failed", &guard.etag, 0, &[]);
                } else {
                    guard.bytes = buffer[header_end + 4..].to_vec();
                    guard.etag = "\"v2\"".to_string();
                    write_response(&mut stream, 200, "OK", &guard.etag, 0, &[]);
                }
            }
            _ => write_response(&mut stream, 405, "Method Not Allowed", "\"v1\"", 0, &[]),
        }
    }

    fn request_complete(buffer: &[u8]) -> bool {
        let Some(header_end) = find_header_end(buffer) else {
            return false;
        };
        let header_text = String::from_utf8_lossy(&buffer[..header_end]);
        let content_length = header_value(&header_text, "content-length")
            .and_then(|value| value.parse::<usize>().ok())
            .unwrap_or(0);
        buffer.len() >= header_end + 4 + content_length
    }

    fn find_header_end(buffer: &[u8]) -> Option<usize> {
        buffer.windows(4).position(|window| window == b"\r\n\r\n")
    }

    fn header_value(headers: &str, name: &str) -> Option<String> {
        headers.lines().find_map(|line| {
            let (key, value) = line.split_once(':')?;
            key.eq_ignore_ascii_case(name)
                .then(|| value.trim().to_string())
        })
    }

    fn write_response(
        stream: &mut TcpStream,
        status: u16,
        reason: &str,
        etag: &str,
        content_length: usize,
        body: &[u8],
    ) {
        let response = format!(
            "HTTP/1.1 {status} {reason}\r\nETag: {etag}\r\nLast-Modified: Wed, 29 Apr 2026 00:00:00 GMT\r\nContent-Length: {content_length}\r\nConnection: close\r\n\r\n"
        );
        stream.write_all(response.as_bytes()).unwrap();
        stream.write_all(body).unwrap();
    }

    #[test]
    fn ffi_open_read_create_update_and_save() {
        let (path, password) = temp_database();
        let path_c = c_string(path.to_string_lossy());
        let password_c = c_string(&password);

        let open = keepassy_open_local(path_c.as_ptr(), password_c.as_ptr(), ptr::null());
        assert_eq!(open.status, 0);
        assert!(!open.session.is_null());
        let session = open.session;
        let snapshot = response_json(open);
        let root_id = snapshot["group_tree"]["id"].as_str().unwrap().to_string();

        let create = c_string(
            json!({
                "group_id": root_id,
                "title": "Email",
                "username": "alice",
                "password": "secret",
                "url": null,
                "notes": null,
                "custom_fields": {}
            })
            .to_string(),
        );
        let created = response_json(keepassy_create_entry_json(session, create.as_ptr()));
        let entry_id = created["id"].as_str().unwrap().to_string();
        assert_eq!(created["title"], "Email");

        let custom = c_string(
            json!({
                "entry_id": entry_id,
                "key": "ApiKey",
                "value": "secret-value",
                "protect": true
            })
            .to_string(),
        );
        let detail = response_json(keepassy_set_custom_field_json(session, custom.as_ptr()));
        assert_eq!(detail["fields"]["ApiKey"], "secret-value");

        let update = c_string(
            json!({
                "entry_id": entry_id,
                "title": "Email Updated",
                "username": null,
                "password": null,
                "url": "https://example.com",
                "notes": null
            })
            .to_string(),
        );
        let updated = response_json(keepassy_update_entry_json(session, update.as_ptr()));
        assert_eq!(updated["title"], "Email Updated");

        let save = response_json(keepassy_save(session, password_c.as_ptr(), ptr::null()));
        assert_eq!(save["saved"], true);
        assert_eq!(save["dirty"], false);
        // SAFETY: `session` was returned by this crate and is closed once.
        unsafe {
            keepassy_session_close(session);
        }

        let reopened = keepassy_open_local(path_c.as_ptr(), password_c.as_ptr(), ptr::null());
        let session = reopened.session;
        let snapshot = response_json(reopened);
        assert_eq!(
            snapshot["group_tree"]["entries"].as_array().unwrap().len(),
            1
        );
        // SAFETY: `session` was returned by this crate and is closed once.
        unsafe {
            keepassy_session_close(session);
        }

        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn ffi_recycle_restore_permanent_delete_and_empty_bin() {
        let (path, password) = temp_database();
        let path_c = c_string(path.to_string_lossy());
        let password_c = c_string(&password);

        let open = keepassy_open_local(path_c.as_ptr(), password_c.as_ptr(), ptr::null());
        assert_eq!(open.status, 0);
        let session = open.session;
        let snapshot = response_json(open);
        let root_id = snapshot["group_tree"]["id"].as_str().unwrap().to_string();

        let first = c_string(
            json!({
                "group_id": root_id,
                "title": "First",
                "custom_fields": {}
            })
            .to_string(),
        );
        let first = response_json(keepassy_create_entry_json(session, first.as_ptr()));
        let first_id = first["id"].as_str().unwrap().to_string();
        let second = c_string(
            json!({
                "group_id": root_id,
                "title": "Second",
                "custom_fields": {}
            })
            .to_string(),
        );
        let second = response_json(keepassy_create_entry_json(session, second.as_ptr()));
        let second_id = second["id"].as_str().unwrap().to_string();

        let first_id_c = c_string(&first_id);
        let recycled = response_json(keepassy_delete_entry_json(session, first_id_c.as_ptr()));
        let recycle_bin = recycled["group_tree"]["groups"]
            .as_array()
            .unwrap()
            .iter()
            .find(|group| group["is_recycle_bin"].as_bool() == Some(true))
            .unwrap();
        assert_eq!(recycle_bin["entries"].as_array().unwrap().len(), 1);

        let restored = response_json(keepassy_restore_entry_json(session, first_id_c.as_ptr()));
        assert_eq!(
            restored["group_tree"]["entries"].as_array().unwrap().len(),
            2
        );

        let second_id_c = c_string(&second_id);
        let _ = response_json(keepassy_delete_entry_json(session, second_id_c.as_ptr()));
        let emptied = response_json(keepassy_empty_recycle_bin_json(session));
        let recycle_bin = emptied["group_tree"]["groups"]
            .as_array()
            .unwrap()
            .iter()
            .find(|group| group["is_recycle_bin"].as_bool() == Some(true))
            .unwrap();
        assert!(recycle_bin["entries"].as_array().unwrap().is_empty());

        let deleted = response_json(keepassy_permanently_delete_entry_json(
            session,
            first_id_c.as_ptr(),
        ));
        assert!(deleted["group_tree"]["entries"]
            .as_array()
            .unwrap()
            .is_empty());

        let group = c_string(
            json!({
                "parent_id": root_id,
                "name": "Archive"
            })
            .to_string(),
        );
        let group = response_json(keepassy_create_group_json(session, group.as_ptr()));
        let group_id = group["id"].as_str().unwrap().to_string();
        let group_id_c = c_string(&group_id);

        let recycled_group =
            response_json(keepassy_delete_group_json(session, group_id_c.as_ptr()));
        let recycle_bin = recycled_group["group_tree"]["groups"]
            .as_array()
            .unwrap()
            .iter()
            .find(|group| group["is_recycle_bin"].as_bool() == Some(true))
            .unwrap();
        assert_eq!(recycle_bin["groups"].as_array().unwrap().len(), 1);

        let restored_group =
            response_json(keepassy_restore_group_json(session, group_id_c.as_ptr()));
        assert!(restored_group["group_tree"]["groups"]
            .as_array()
            .unwrap()
            .iter()
            .any(|group| group["id"].as_str() == Some(group_id.as_str())));

        let _ = response_json(keepassy_delete_group_json(session, group_id_c.as_ptr()));
        let deleted_group = response_json(keepassy_permanently_delete_group_json(
            session,
            group_id_c.as_ptr(),
        ));
        assert!(!deleted_group["group_tree"]["groups"]
            .as_array()
            .unwrap()
            .iter()
            .any(|group| group["id"].as_str() == Some(group_id.as_str())));

        // SAFETY: `session` was returned by this crate and is closed once.
        unsafe {
            keepassy_session_close(session);
        }
        let _ = std::fs::remove_file(path);
    }

    #[test]
    fn ffi_error_response_for_null_session() {
        let response = keepassy_group_tree_json(ptr::null_mut());
        let error = response_error(response);
        assert!(error["error"].as_str().unwrap().contains("session handle"));
    }

    #[test]
    fn ffi_open_webdav_returns_remote_metadata() {
        let password = "test-password";
        let (url, _state) = start_webdav_server(database_bytes(password), false);
        let request = c_string(json!({ "url": url }).to_string());
        let password_c = c_string(password);

        let open = keepassy_open_webdav(request.as_ptr(), password_c.as_ptr());
        assert_eq!(open.status, 0);
        assert!(!open.session.is_null());
        let session = open.session;
        let snapshot = response_json(open);
        assert_eq!(snapshot["source"], url);
        assert_eq!(snapshot["metadata"]["etag"], "\"v1\"");
        assert_eq!(
            snapshot["metadata"]["last_modified"],
            "Wed, 29 Apr 2026 00:00:00 GMT"
        );
        // SAFETY: `session` was returned by this crate and is closed once.
        unsafe {
            keepassy_session_close(session);
        }
    }

    #[test]
    fn ffi_webdav_save_conflict_returns_error() {
        let password = "test-password";
        let (url, state) = start_webdav_server(database_bytes(password), true);
        let request = c_string(json!({ "url": url }).to_string());
        let password_c = c_string(password);

        let open = keepassy_open_webdav(request.as_ptr(), password_c.as_ptr());
        assert_eq!(open.status, 0);
        let session = open.session;
        let snapshot = response_json(open);
        let root_id = snapshot["group_tree"]["id"].as_str().unwrap().to_string();

        let create = c_string(
            json!({
                "group_id": root_id,
                "title": "Remote",
                "username": null,
                "password": null,
                "url": null,
                "notes": null,
                "custom_fields": {}
            })
            .to_string(),
        );
        let created = response_json(keepassy_create_entry_json(session, create.as_ptr()));
        assert_eq!(created["title"], "Remote");

        let error = response_error(keepassy_save(session, password_c.as_ptr(), ptr::null()));
        assert!(error["error"]
            .as_str()
            .unwrap()
            .contains("remote database has been modified"));
        assert_eq!(
            state.lock().unwrap().last_put_if_match.as_deref(),
            Some("\"v1\"")
        );
        // SAFETY: `session` was returned by this crate and is closed once.
        unsafe {
            keepassy_session_close(session);
        }
    }

    #[test]
    fn ffi_webdav_save_success_updates_remote() {
        let password = "test-password";
        let (url, state) = start_webdav_server(database_bytes(password), false);
        let request = c_string(json!({ "url": url }).to_string());
        let password_c = c_string(password);

        let open = keepassy_open_webdav(request.as_ptr(), password_c.as_ptr());
        assert_eq!(open.status, 0);
        let session = open.session;
        let snapshot = response_json(open);
        let root_id = snapshot["group_tree"]["id"].as_str().unwrap().to_string();

        let create = c_string(
            json!({
                "group_id": root_id,
                "title": "Saved Remote",
                "username": null,
                "password": null,
                "url": null,
                "notes": null,
                "custom_fields": {}
            })
            .to_string(),
        );
        let created = response_json(keepassy_create_entry_json(session, create.as_ptr()));
        assert_eq!(created["title"], "Saved Remote");

        let save = response_json(keepassy_save(session, password_c.as_ptr(), ptr::null()));
        assert_eq!(save["saved"], true);
        assert_eq!(save["dirty"], false);

        let guard = state.lock().unwrap();
        assert_eq!(guard.last_put_if_match.as_deref(), Some("\"v1\""));
        assert_eq!(guard.etag, "\"v2\"");
        assert!(!guard.bytes.is_empty());
        drop(guard);

        // SAFETY: `session` was returned by this crate and is closed once.
        unsafe {
            keepassy_session_close(session);
        }
    }

    #[test]
    fn ffi_create_local_and_reopen() {
        let password = "test-password";
        let path =
            std::env::temp_dir().join(format!("keepassy-ffi-create-{}.kdbx", std::process::id()));
        let _ = std::fs::remove_file(&path);

        let request = c_string(json!({ "path": path.to_string_lossy() }).to_string());
        let password_c = c_string(password);

        let create = keepassy_create_local(request.as_ptr(), password_c.as_ptr());
        assert_eq!(create.status, 0);
        assert!(!create.session.is_null());
        let session = create.session;
        let snapshot = response_json(create);
        assert_eq!(snapshot["source"], path.to_string_lossy().to_string());
        assert_eq!(snapshot["group_tree"]["name"], "Root");
        assert!(snapshot["group_tree"]["entries"]
            .as_array()
            .unwrap()
            .is_empty());
        // SAFETY: `session` was returned by this crate and is closed once.
        unsafe {
            keepassy_session_close(session);
        }

        let duplicate = keepassy_create_local(request.as_ptr(), password_c.as_ptr());
        assert_eq!(duplicate.status, 1);
        let duplicate_error = response_error(duplicate);
        assert!(duplicate_error["error"]
            .as_str()
            .unwrap()
            .contains("already exists"));

        // Reopen the created file
        let path_c = c_string(path.to_string_lossy());
        let reopen = keepassy_open_local(path_c.as_ptr(), password_c.as_ptr(), ptr::null());
        assert_eq!(reopen.status, 0);
        let session = reopen.session;
        let reopened = response_json(reopen);
        assert_eq!(reopened["group_tree"]["name"], "Root");
        // SAFETY: `session` was returned by this crate and is closed once.
        unsafe {
            keepassy_session_close(session);
        }

        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn ffi_create_local_with_keyfile_only_and_reopen() {
        let path = std::env::temp_dir().join(format!(
            "keepassy-ffi-create-keyfile-only-{}.kdbx",
            std::process::id()
        ));
        let keyfile_path = std::env::temp_dir().join(format!(
            "keepassy-ffi-create-keyfile-only-{}.key",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(&keyfile_path);
        std::fs::write(&keyfile_path, b"test-keyfile-bytes").unwrap();

        let request = c_string(
            json!({
                "path": path.to_string_lossy(),
                "keyfile_path": keyfile_path.to_string_lossy(),
            })
            .to_string(),
        );
        let empty_password = c_string("");

        let create = keepassy_create_local(request.as_ptr(), empty_password.as_ptr());
        assert_eq!(create.status, 0);
        assert!(!create.session.is_null());
        let session = create.session;
        let snapshot = response_json(create);
        assert_eq!(snapshot["source"], path.to_string_lossy().to_string());
        // SAFETY: `session` was returned by this crate and is closed once.
        unsafe {
            keepassy_session_close(session);
        }

        let path_c = c_string(path.to_string_lossy());
        let keyfile_c = c_string(keyfile_path.to_string_lossy());
        let reopen =
            keepassy_open_local(path_c.as_ptr(), empty_password.as_ptr(), keyfile_c.as_ptr());
        assert_eq!(reopen.status, 0);
        let session = reopen.session;
        let reopened = response_json(reopen);
        assert_eq!(reopened["group_tree"]["name"], "Root");
        // SAFETY: `session` was returned by this crate and is closed once.
        unsafe {
            keepassy_session_close(session);
        }

        let _ = std::fs::remove_file(&path);
        let _ = std::fs::remove_file(&keyfile_path);
    }
}
