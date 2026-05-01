pub mod dto;
pub mod error;
pub mod service;
pub mod storage;

pub const KEEPASS_CORE_VERSION: &str = env!("CARGO_PKG_VERSION");

pub use dto::{
    AttachmentBytes, AttachmentSummary, CreateEntryRequest, CreateGroupRequest, EntryDetail,
    EntrySummary, GroupNode, HistorySummary, MoveEntryRequest, OpenedVault, RemoteMetadata,
    RenameGroupRequest, SetCustomFieldRequest, UpdateEntryRequest, UpsertAttachmentRequest,
};
pub use error::{Result, VaultError};
pub use service::{VaultService, VaultSession};
pub use storage::{
    LocalFileStorage, StorageBackend, WebDavConfig, WebDavCredentials, WebDavStorage,
};
