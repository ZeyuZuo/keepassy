use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// An opened KeePass vault.
///
/// Returned by [`VaultService::open_local`](crate::VaultService::open_local) and
/// [`VaultService::open_webdav`](crate::VaultService::open_webdav). Contains the full group
/// tree with entry summaries at every level, plus an internal entry detail index used by
/// [`VaultSession::entry_detail`](crate::VaultSession::entry_detail).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct OpenedVault {
    /// Identifies where this vault was loaded from (file path or URL).
    pub source: String,

    /// Remote metadata such as ETag and Last-Modified. `None` for local files.
    pub metadata: Option<RemoteMetadata>,

    /// The root of the group tree. Every group carries its child groups and
    /// top-level entry summaries.
    pub group_tree: GroupNode,

    /// Flat index of all entry details keyed by entry UUID. Not included in
    /// serialized output — use [`VaultSession::entry_detail`](crate::VaultSession::entry_detail)
    /// to look up individual entries.
    #[serde(skip_serializing, default)]
    pub entry_details: BTreeMap<String, EntryDetail>,
}

/// HTTP-level metadata collected when opening a vault over WebDAV.
///
/// Populated from response headers of the `HEAD` request. All fields are optional
/// because not every server returns every header.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RemoteMetadata {
    /// Value of the `ETag` header, used for conflict detection on save.
    pub etag: Option<String>,

    /// Value of the `Last-Modified` header.
    pub last_modified: Option<String>,

    /// Value of the `Content-Length` header, in bytes.
    pub content_length: Option<u64>,
}

/// A node in the group tree.
///
/// Each group has a KeePass-native UUID as its `id`. Groups contain both child
/// groups and a summary of their direct entries. The full entry details are
/// stored separately and accessed via [`VaultSession::entry_detail`](crate::VaultSession::entry_detail).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct GroupNode {
    /// KeePass UUID of this group in hyphenated format.
    pub id: String,

    /// Display name of the group.
    pub name: String,

    /// Whether this group is the KeePass recycle bin.
    #[serde(default)]
    pub is_recycle_bin: bool,

    /// Entries directly under this group (summary only — no passwords).
    pub entries: Vec<EntrySummary>,

    /// Child groups.
    pub groups: Vec<GroupNode>,
}

/// Lightweight summary of a KeePass entry.
///
/// Designed for list views. Passwords and notes are intentionally excluded —
/// use [`VaultSession::entry_detail`](crate::VaultSession::entry_detail) to get the
/// full [`EntryDetail`].
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EntrySummary {
    /// KeePass UUID of this entry in hyphenated format.
    pub id: String,

    /// Entry title (the `Title` KeePass field).
    pub title: Option<String>,

    /// Entry username (the `UserName` KeePass field).
    pub username: Option<String>,

    /// Entry URL (the `URL` KeePass field).
    pub url: Option<String>,

    /// Whether the entry has an expiration date set.
    #[serde(default)]
    pub expires: bool,

    /// Entry notes (for full-text search across groups).
    #[serde(default)]
    pub notes: Option<String>,

    /// Last modification time in ISO 8601 format.
    #[serde(default)]
    pub last_modified: Option<String>,
}

/// Full details of a KeePass entry, including sensitive fields.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EntryDetail {
    /// KeePass UUID of this entry in hyphenated format.
    pub id: String,

    /// Entry title.
    pub title: Option<String>,

    /// Entry username.
    pub username: Option<String>,

    /// Entry URL.
    pub url: Option<String>,

    /// Entry password. Only included in detail views, never in summaries.
    pub password: Option<String>,

    /// Entry notes.
    pub notes: Option<String>,

    /// Whether the entry has an expiration date set.
    #[serde(default)]
    pub expires: bool,

    /// Expiration date in ISO 8601 format.
    #[serde(default)]
    pub expiry_time: Option<String>,

    /// Custom KeePass string fields that do not have a dedicated slot.
    ///
    /// Standard fields (`Title`, `UserName`, `Password`, `URL`, `Notes`) are
    /// mapped to their dedicated fields and excluded from this map. Every
    /// other field present on the KeePass entry appears here with its raw
    /// decrypted value.
    pub fields: BTreeMap<String, String>,

    /// Keys of custom fields that are stored as protected values.
    pub protected_fields: Vec<String>,

    /// Attachment metadata for this entry. Raw attachment bytes are exposed
    /// only through the attachment read API, not normal entry detail JSON.
    pub attachments: Vec<AttachmentSummary>,
}

/// Metadata for a KeePass entry attachment.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttachmentSummary {
    /// Attachment name as stored on the KeePass entry.
    pub name: String,

    /// Attachment size in bytes.
    pub size: usize,

    /// Whether the stored attachment value is protected.
    pub protected: bool,
}

/// Raw bytes for a single entry attachment.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttachmentBytes {
    /// UUID of the owning entry.
    pub entry_id: String,

    /// Attachment name.
    pub name: String,

    /// Decrypted attachment bytes.
    pub bytes: Vec<u8>,

    /// Whether the stored attachment value is protected.
    pub protected: bool,
}

/// Request to add or replace an attachment on an entry.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UpsertAttachmentRequest {
    /// UUID of the entry to modify.
    pub entry_id: String,

    /// Attachment name. Must not be empty.
    pub name: String,

    /// Raw attachment bytes to store.
    pub bytes: Vec<u8>,

    /// Store the attachment value as protected.
    pub protect: bool,
}

/// Request to create a new entry in a KeePass vault.
///
/// All fields except `group_id` are optional — the entry will be created
/// with whatever fields are provided.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreateEntryRequest {
    /// UUID of the target group where the entry will be created.
    pub group_id: String,
    pub title: Option<String>,
    pub username: Option<String>,
    pub password: Option<String>,
    pub url: Option<String>,
    pub notes: Option<String>,
    /// Additional custom fields to set on the entry.
    pub custom_fields: BTreeMap<String, String>,

    /// Keys of custom fields that should be stored as protected values.
    #[serde(default)]
    pub protected_custom_fields: Vec<String>,

    /// Whether the entry expires.
    #[serde(default)]
    pub expires: bool,

    /// Expiration date in ISO 8601 format.
    pub expiry_time: Option<String>,
}

/// Request to update an existing entry.
///
/// Each optional field follows this convention:
/// - `None` — leave the field unchanged.
/// - `Some("")` — clear the field.
/// - `Some(value)` — set the field to `value`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UpdateEntryRequest {
    /// UUID of the entry to update.
    pub entry_id: String,
    pub title: Option<String>,
    pub username: Option<String>,
    pub password: Option<String>,
    pub url: Option<String>,
    pub notes: Option<String>,

    /// Whether the entry expires. `None` leaves unchanged.
    pub expires: Option<bool>,

    /// Expiration date. `None` leaves unchanged, `Some("")` clears.
    pub expiry_time: Option<String>,
}

/// Request to move an entry to a different group.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MoveEntryRequest {
    pub entry_id: String,
    pub target_group_id: String,
}

/// Request to create a new group.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreateGroupRequest {
    pub parent_id: String,
    pub name: String,
}

/// Request to rename a group.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RenameGroupRequest {
    pub group_id: String,
    pub name: String,
}

/// Request to set or replace a custom string field.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SetCustomFieldRequest {
    /// UUID of the entry to modify.
    pub entry_id: String,

    /// Custom field name. Standard KeePass field names are rejected.
    pub key: String,

    /// Field value. Empty values are allowed and preserved.
    pub value: String,

    /// Store the field value as protected.
    pub protect: bool,
}

/// Summary of one historical snapshot of an entry.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HistorySummary {
    /// Stable index for this history item within the current entry history
    /// list. Use this index to request the full historical snapshot.
    pub index: usize,

    /// Historical entry title.
    pub title: Option<String>,

    /// Historical username.
    pub username: Option<String>,

    /// Historical URL.
    pub url: Option<String>,

    /// Last modification timestamp if present in the KeePass data.
    pub last_modified: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::BTreeMap;

    #[test]
    fn group_node_json_shape() {
        let group = GroupNode {
            id: "abc-123".into(),
            name: "Root".into(),
            is_recycle_bin: false,
            entries: vec![EntrySummary {
                id: "def-456".into(),
                title: Some("Email".into()),
                username: Some("alice".into()),
                url: Some("https://example.com".into()),
                expires: false,
                notes: None,
                last_modified: None,
            }],
            groups: vec![],
        };

        let json = serde_json::to_string_pretty(&group).unwrap();

        assert!(json.contains("\"id\": \"abc-123\""));
        assert!(json.contains("\"name\": \"Root\""));
        assert!(json.contains("\"title\": \"Email\""));
        assert!(json.contains("\"username\": \"alice\""));
        // password must never appear in group tree or entry summary
        assert!(!json.contains("password"));
    }

    #[test]
    fn entry_summary_excludes_password() {
        let summary = EntrySummary {
            id: "def-456".into(),
            title: Some("Bank".into()),
            username: Some("bob".into()),
            url: None,
            expires: false,
            notes: None,
            last_modified: None,
        };

        let json = serde_json::to_string(&summary).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&json).unwrap();

        assert_eq!(parsed["id"], "def-456");
        assert_eq!(parsed["title"], "Bank");
        assert_eq!(parsed["username"], "bob");
        assert!(parsed.get("password").is_none());
    }

    #[test]
    fn entry_detail_includes_password_and_notes() {
        let mut fields = BTreeMap::new();
        fields.insert("CustomKey".into(), "custom value".into());

        let detail = EntryDetail {
            id: "abc-123".into(),
            title: Some("VPN".into()),
            username: Some("admin".into()),
            url: Some("https://vpn.example.com".into()),
            password: Some("secret123".into()),
            notes: Some("main gateway".into()),
            expires: false,
            expiry_time: None,
            fields,
            protected_fields: vec![],
            attachments: vec![AttachmentSummary {
                name: "vpn.conf".into(),
                size: 12,
                protected: false,
            }],
        };

        let json = serde_json::to_string_pretty(&detail).unwrap();

        assert!(json.contains("\"password\": \"secret123\""));
        assert!(json.contains("\"notes\": \"main gateway\""));
        assert!(json.contains("\"CustomKey\": \"custom value\""));
        assert!(!json.contains("\"bytes\""));
    }

    #[test]
    fn opened_vault_skips_entry_details_in_json() {
        let mut details = BTreeMap::new();
        details.insert(
            "e1".into(),
            EntryDetail {
                id: "e1".into(),
                title: Some("t".into()),
                username: None,
                url: None,
                password: Some("p".into()),
                notes: None,
                expires: false,
                expiry_time: None,
                fields: BTreeMap::new(),
                protected_fields: vec![],
                attachments: vec![],
            },
        );

        let vault = OpenedVault {
            source: "test.kdbx".into(),
            metadata: None,
            group_tree: GroupNode {
                id: "root".into(),
                name: "Root".into(),
                is_recycle_bin: false,
                entries: vec![],
                groups: vec![],
            },
            entry_details: details,
        };

        let json = serde_json::to_string_pretty(&vault).unwrap();

        // entry_details must not leak into serialized output
        assert!(!json.contains("entry_details"));
        assert!(!json.contains("\"p\""));
    }

    #[test]
    fn remote_metadata_json_shape() {
        let meta = RemoteMetadata {
            etag: Some("\"abc123\"".into()),
            last_modified: Some("Wed, 21 Oct 2015 07:28:00 GMT".into()),
            content_length: Some(1024),
        };

        let json = serde_json::to_string_pretty(&meta).unwrap();

        assert!(json.contains("\"etag\": \"\\\"abc123\\\"\""));
        assert!(json.contains("\"last_modified\""));
        assert!(json.contains("\"content_length\": 1024"));
    }

    #[test]
    fn entry_request_dtos_are_json_serializable() {
        let create = CreateEntryRequest {
            group_id: "group-1".into(),
            title: Some("Title".into()),
            username: None,
            password: Some("secret".into()),
            url: None,
            notes: None,
            custom_fields: BTreeMap::from([("Custom".into(), "Value".into())]),
            protected_custom_fields: vec![],
            expires: false,
            expiry_time: None,
        };

        let json = serde_json::to_string(&create).unwrap();
        let parsed: CreateEntryRequest = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, create);

        let update = UpdateEntryRequest {
            entry_id: "entry-1".into(),
            title: Some("New Title".into()),
            username: None,
            password: Some("".into()),
            url: None,
            notes: None,
            expires: None,
            expiry_time: None,
        };

        let json = serde_json::to_string(&update).unwrap();
        let parsed: UpdateEntryRequest = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, update);

        let attachment = UpsertAttachmentRequest {
            entry_id: "entry-1".into(),
            name: "file.bin".into(),
            bytes: vec![1, 2, 3],
            protect: true,
        };
        let json = serde_json::to_string(&attachment).unwrap();
        let parsed: UpsertAttachmentRequest = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, attachment);

        let custom = SetCustomFieldRequest {
            entry_id: "entry-1".into(),
            key: "Custom".into(),
            value: "Value".into(),
            protect: true,
        };
        let json = serde_json::to_string(&custom).unwrap();
        let parsed: SetCustomFieldRequest = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed, custom);
    }
}
