use crate::dto::{
    AttachmentBytes, AttachmentSummary, CreateEntryRequest, EntryDetail, EntrySummary, GroupNode,
    HistorySummary, OpenedVault, SetCustomFieldRequest, UpdateEntryRequest,
    UpsertAttachmentRequest,
};
use crate::error::{Result, VaultError};
use crate::storage::{LocalFileStorage, StorageBackend, WebDavConfig, WebDavStorage};
use keepass::db::{
    fields, Attachment, CustomDataItem, CustomDataValue, Entry, Group, Times, Value,
};
use keepass::{Database, DatabaseKey};
use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::io::Cursor;
use std::path::PathBuf;
use uuid::Uuid;

/// Standard KeePass fields that map to dedicated [`EntryDetail`] fields rather
/// than appearing in [`EntryDetail::fields`].
static KNOWN_FIELD_KEYS: &[&str] = &[
    fields::TITLE,
    fields::USERNAME,
    fields::PASSWORD,
    fields::URL,
    fields::NOTES,
];

const RECYCLE_BIN_NAME: &str = "Recycle Bin";
const ORIGINAL_GROUP_CUSTOM_DATA_KEY: &str = "keepassy.original_group_id";
const ORIGINAL_PARENT_GROUP_CUSTOM_DATA_KEY: &str = "keepassy.original_parent_group_id";

// --- VaultService (factory) ---

#[derive(Debug, Clone, Default)]
pub struct VaultService;

impl VaultService {
    /// Open a local `.kdbx` file and return a [`VaultSession`].
    pub async fn open_local(
        &self,
        path: impl Into<PathBuf>,
        master_password: impl AsRef<str>,
    ) -> Result<VaultSession> {
        let storage = LocalFileStorage::new(path);
        VaultSession::open(Box::new(storage), master_password.as_ref(), None).await
    }

    /// Open a local `.kdbx` file with a master password plus keyfile bytes.
    pub async fn open_local_with_keyfile(
        &self,
        path: impl Into<PathBuf>,
        master_password: impl AsRef<str>,
        keyfile: impl AsRef<[u8]>,
    ) -> Result<VaultSession> {
        let storage = LocalFileStorage::new(path);
        VaultSession::open(
            Box::new(storage),
            master_password.as_ref(),
            Some(keyfile.as_ref()),
        )
        .await
    }

    /// Open a remote `.kdbx` file via WebDAV and return a [`VaultSession`].
    pub async fn open_webdav(
        &self,
        config: WebDavConfig,
        master_password: impl AsRef<str>,
    ) -> Result<VaultSession> {
        let storage = WebDavStorage::new(config);
        VaultSession::open(Box::new(storage), master_password.as_ref(), None).await
    }

    /// Open a remote `.kdbx` file via WebDAV with a master password plus
    /// keyfile bytes.
    pub async fn open_webdav_with_keyfile(
        &self,
        config: WebDavConfig,
        master_password: impl AsRef<str>,
        keyfile: impl AsRef<[u8]>,
    ) -> Result<VaultSession> {
        let storage = WebDavStorage::new(config);
        VaultSession::open(
            Box::new(storage),
            master_password.as_ref(),
            Some(keyfile.as_ref()),
        )
        .await
    }

    /// Create a new empty KeePass database at `path`, write it atomically,
    /// and return an open [`VaultSession`].
    pub async fn create_local(
        &self,
        path: impl Into<PathBuf>,
        master_password: impl AsRef<str>,
    ) -> Result<VaultSession> {
        let path = path.into();
        let db = Database::new(Default::default());
        let key = build_database_key(master_password.as_ref(), None)?;
        let mut buf = Vec::new();
        db.save(&mut buf, key)
            .map_err(|e| VaultError::DatabaseSave(e.to_string()))?;
        write_new_database(&path, &buf)?;
        let storage = LocalFileStorage::new(path);
        VaultSession::open(Box::new(storage), master_password.as_ref(), None).await
    }

    /// Create a new empty KeePass database with a master password plus keyfile.
    pub async fn create_local_with_keyfile(
        &self,
        path: impl Into<PathBuf>,
        master_password: impl AsRef<str>,
        keyfile: impl AsRef<[u8]>,
    ) -> Result<VaultSession> {
        let path = path.into();
        let db = Database::new(Default::default());
        let key = build_database_key(master_password.as_ref(), Some(keyfile.as_ref()))?;
        let mut buf = Vec::new();
        db.save(&mut buf, key)
            .map_err(|e| VaultError::DatabaseSave(e.to_string()))?;
        write_new_database(&path, &buf)?;
        let storage = LocalFileStorage::new(path);
        VaultSession::open(
            Box::new(storage),
            master_password.as_ref(),
            Some(keyfile.as_ref()),
        )
        .await
    }
}

// --- VaultSession ---

/// A stateful handle to an opened KeePass vault.
///
/// Holds the decrypted database in memory and provides both read and write
/// operations. Mutations mark the session dirty; call [`save`](VaultSession::save)
/// to persist changes.
pub struct VaultSession {
    db: Database,
    original_bytes: Vec<u8>,
    source: String,
    metadata: Option<crate::dto::RemoteMetadata>,
    storage: Box<dyn StorageBackend>,
    dirty: bool,
    group_tree: GroupNode,
    entry_details: BTreeMap<String, EntryDetail>,
}

impl VaultSession {
    async fn open(
        storage: Box<dyn StorageBackend>,
        master_password: &str,
        keyfile: Option<&[u8]>,
    ) -> Result<Self> {
        let bytes = storage.read().await?;
        let metadata = storage.metadata().await?;
        let source = storage.source();
        let key = build_database_key(master_password, keyfile)?;
        let db = Database::parse(&bytes, key)
            .map_err(|err| VaultError::DatabaseOpen(err.to_string()))?;
        let (group_tree, entry_details) = build_tree(&db);
        Ok(Self {
            db,
            original_bytes: bytes,
            source,
            metadata,
            storage,
            dirty: false,
            group_tree,
            entry_details,
        })
    }

    // --- read methods ---

    /// Snapshot of the vault metadata (source, remote metadata, etc.).
    pub fn snapshot(&self) -> OpenedVault {
        OpenedVault {
            source: self.source.clone(),
            metadata: self.metadata.clone(),
            group_tree: self.group_tree.clone(),
            entry_details: self.entry_details.clone(),
        }
    }

    /// Reference to the group tree root.
    pub fn group_tree(&self) -> &GroupNode {
        &self.group_tree
    }

    /// List entry summaries for a group by its UUID.
    pub fn entries_for_group(&self, group_id: &str) -> Result<&[EntrySummary]> {
        find_group(&self.group_tree, group_id)
            .map(|g| g.entries.as_slice())
            .ok_or_else(|| VaultError::GroupNotFound(group_id.to_string()))
    }

    /// Look up a single entry's full details by UUID.
    pub fn entry_detail(&self, entry_id: &str) -> Result<EntryDetail> {
        self.entry_details
            .get(entry_id)
            .cloned()
            .ok_or_else(|| VaultError::EntryNotFound(entry_id.to_string()))
    }

    /// Whether the session has unsaved changes.
    pub fn is_dirty(&self) -> bool {
        self.dirty
    }

    /// List attachment metadata for an entry.
    pub fn attachments_for_entry(&self, entry_id: &str) -> Result<Vec<AttachmentSummary>> {
        let entry = find_entry(&self.db.root, entry_id)
            .ok_or_else(|| VaultError::EntryNotFound(entry_id.to_string()))?;
        Ok(attachment_summaries(entry))
    }

    /// Read raw bytes for a single attachment.
    pub fn attachment_bytes(&self, entry_id: &str, name: &str) -> Result<AttachmentBytes> {
        let entry = find_entry(&self.db.root, entry_id)
            .ok_or_else(|| VaultError::EntryNotFound(entry_id.to_string()))?;
        let attachment = entry
            .attachments
            .get(name)
            .ok_or_else(|| VaultError::AttachmentNotFound(name.to_string()))?;

        Ok(AttachmentBytes {
            entry_id: entry_id.to_string(),
            name: name.to_string(),
            bytes: attachment.data.get().clone(),
            protected: attachment.data.is_protected(),
        })
    }

    /// List historical snapshots for an entry.
    pub fn entry_history(&self, entry_id: &str) -> Result<Vec<HistorySummary>> {
        let entry = find_entry(&self.db.root, entry_id)
            .ok_or_else(|| VaultError::EntryNotFound(entry_id.to_string()))?;
        let Some(history) = &entry.history else {
            return Ok(Vec::new());
        };

        Ok(history
            .get_entries()
            .iter()
            .enumerate()
            .map(|(index, entry)| history_summary(index, entry))
            .collect())
    }

    /// Read a historical entry snapshot by index from [`entry_history`](Self::entry_history).
    pub fn entry_history_detail(&self, entry_id: &str, index: usize) -> Result<EntryDetail> {
        let entry = find_entry(&self.db.root, entry_id)
            .ok_or_else(|| VaultError::EntryNotFound(entry_id.to_string()))?;
        let history_entry = entry
            .history
            .as_ref()
            .and_then(|history| history.get_entries().get(index))
            .ok_or_else(|| VaultError::HistoryNotFound(format!("{entry_id}:{index}")))?;

        Ok(entry_to_detail(entry_id.to_string(), history_entry))
    }

    // --- mutation methods ---

    /// Create a new entry in the given group.
    pub fn create_entry(&mut self, req: CreateEntryRequest) -> Result<EntryDetail> {
        let group = find_group_mut(&mut self.db.root, &req.group_id)
            .ok_or_else(|| VaultError::GroupNotFound(req.group_id.clone()))?;

        let mut entry = Entry::new();
        set_opt(&mut entry, fields::TITLE, req.title.as_deref());
        set_opt(&mut entry, fields::USERNAME, req.username.as_deref());
        set_opt(&mut entry, fields::PASSWORD, req.password.as_deref());
        set_opt(&mut entry, fields::URL, req.url.as_deref());
        set_opt(&mut entry, fields::NOTES, req.notes.as_deref());
        for (key, value) in &req.custom_fields {
            if !value.is_empty() {
                if req.protected_custom_fields.contains(key) {
                    entry.set_protected(key.clone(), value.clone());
                } else {
                    entry.set_unprotected(key.clone(), value.clone());
                }
            }
        }
        entry.times.expires = Some(req.expires);
        if let Some(ref t) = req.expiry_time {
            if let Ok(dt) = chrono::NaiveDateTime::parse_from_str(t, "%Y-%m-%dT%H:%M:%S") {
                entry.times.expiry = Some(dt);
            }
        }

        let entry_id = entry.uuid.to_string();
        let detail = entry_to_detail(entry_id.clone(), &entry);
        group.entries.push(entry);

        self.rebuild_cache();
        self.dirty = true;
        Ok(detail)
    }

    /// Update an existing entry. Fields set to `Some(...)` are updated;
    /// fields left as `None` keep their current value. Pass `Some("")` to
    /// clear an optional field.
    pub fn update_entry(&mut self, req: UpdateEntryRequest) -> Result<EntryDetail> {
        let entry = find_entry_mut(&mut self.db.root, &req.entry_id)
            .ok_or_else(|| VaultError::EntryNotFound(req.entry_id.clone()))?;

        let changed = [
            apply_update(entry, fields::TITLE, req.title.as_deref()),
            apply_update(entry, fields::USERNAME, req.username.as_deref()),
            apply_update(entry, fields::PASSWORD, req.password.as_deref()),
            apply_update(entry, fields::URL, req.url.as_deref()),
            apply_update(entry, fields::NOTES, req.notes.as_deref()),
        ]
        .into_iter()
        .any(|c| c);
        let expiry_changed = apply_expiry_update(entry, req.expires, req.expiry_time.as_deref());

        if changed || expiry_changed {
            entry.update_history();
            self.rebuild_cache();
            self.dirty = true;
        }

        // Return the updated detail from our fresh cache
        self.entry_details
            .get(&req.entry_id)
            .cloned()
            .ok_or_else(|| VaultError::EntryNotFound(req.entry_id.clone()))
    }

    /// Move an entry to the KeePass recycle bin.
    pub fn delete_entry(&mut self, entry_id: &str) -> Result<()> {
        let source_group_id = find_group_containing_entry(&self.db.root, entry_id)
            .map(|group| group.uuid.to_string())
            .ok_or_else(|| VaultError::EntryNotFound(entry_id.to_string()))?;
        let recycle_bin_id = self.ensure_recycle_bin();

        if source_group_id == recycle_bin_id {
            return self.permanently_delete_entry(entry_id);
        }

        let (original_group_id, mut entry) =
            remove_entry_from_group(&mut self.db.root, entry_id)
                .ok_or_else(|| VaultError::EntryNotFound(entry_id.to_string()))?;
        set_original_group_id(&mut entry, original_group_id);
        let now = Times::now();
        entry.times.location_changed = Some(now);
        entry.times.last_modification = Some(now);

        let recycle_bin = find_group_mut(&mut self.db.root, &recycle_bin_id)
            .ok_or_else(|| VaultError::GroupNotFound(format!("recycle bin {recycle_bin_id}")))?;
        recycle_bin.entries.push(entry);

        self.rebuild_cache();
        self.dirty = true;
        Ok(())
    }

    /// Restore an entry from the recycle bin to its original group when possible.
    pub fn restore_entry(&mut self, entry_id: &str) -> Result<EntryDetail> {
        let recycle_bin_id = self
            .recycle_bin_id()
            .ok_or_else(|| VaultError::EntryNotFound(entry_id.to_string()))?;
        let source_group_id = find_group_containing_entry(&self.db.root, entry_id)
            .map(|group| group.uuid.to_string())
            .ok_or_else(|| VaultError::EntryNotFound(entry_id.to_string()))?;

        if source_group_id != recycle_bin_id {
            return Err(VaultError::InvalidRequest(
                "entry is not in the recycle bin".to_string(),
            ));
        }

        let (_, mut entry) = remove_entry_from_group(&mut self.db.root, entry_id)
            .ok_or_else(|| VaultError::EntryNotFound(entry_id.to_string()))?;
        let original_group_id = take_original_group_id(&mut entry);
        let root_id = self.db.root.uuid.to_string();
        let target_group_id = original_group_id
            .filter(|id| id != &recycle_bin_id && group_exists(&self.db.root, id))
            .unwrap_or(root_id);

        let now = Times::now();
        entry.times.location_changed = Some(now);
        entry.times.last_modification = Some(now);
        let target = find_group_mut(&mut self.db.root, &target_group_id)
            .ok_or_else(|| VaultError::GroupNotFound(target_group_id.clone()))?;
        target.entries.push(entry);

        self.rebuild_cache();
        self.dirty = true;
        self.entry_detail(entry_id)
    }

    /// Permanently remove an entry and mark it in KeePass deleted objects.
    pub fn permanently_delete_entry(&mut self, entry_id: &str) -> Result<()> {
        let (_, entry) = remove_entry_from_group(&mut self.db.root, entry_id)
            .ok_or_else(|| VaultError::EntryNotFound(entry_id.to_string()))?;
        self.db
            .deleted_objects
            .insert(entry.uuid, Some(Times::now()));
        self.rebuild_cache();
        self.dirty = true;
        Ok(())
    }

    /// Permanently remove every entry currently stored in the recycle bin.
    pub fn empty_recycle_bin(&mut self) -> Result<()> {
        let recycle_bin_id = match self.recycle_bin_id() {
            Some(id) => id,
            None => return Ok(()),
        };
        let recycle_bin = match find_group_mut(&mut self.db.root, &recycle_bin_id) {
            Some(group) => group,
            None => return Ok(()),
        };
        let mut removed_entries = Vec::new();
        let mut removed_groups = Vec::new();
        drain_recycle_bin(recycle_bin, &mut removed_entries, &mut removed_groups);
        if removed_entries.is_empty() && removed_groups.is_empty() {
            return Ok(());
        }
        let deleted_at = Times::now();
        for entry in removed_entries {
            self.db.deleted_objects.insert(entry.uuid, Some(deleted_at));
        }
        for group in removed_groups {
            mark_deleted_group(&mut self.db.deleted_objects, &group, deleted_at);
        }
        self.rebuild_cache();
        self.dirty = true;
        Ok(())
    }

    /// Add or replace an attachment on an entry.
    pub fn upsert_attachment(&mut self, req: UpsertAttachmentRequest) -> Result<AttachmentSummary> {
        if req.name.is_empty() {
            return Err(VaultError::InvalidRequest(
                "attachment name must not be empty".to_string(),
            ));
        }

        let entry = find_entry_mut(&mut self.db.root, &req.entry_id)
            .ok_or_else(|| VaultError::EntryNotFound(req.entry_id.clone()))?;
        let attachment = Attachment {
            data: if req.protect {
                Value::protected(req.bytes)
            } else {
                Value::unprotected(req.bytes)
            },
        };
        entry.attachments.insert(req.name.clone(), attachment);
        entry.update_history();

        self.rebuild_cache();
        self.dirty = true;

        self.attachments_for_entry(&req.entry_id)?
            .into_iter()
            .find(|attachment| attachment.name == req.name)
            .ok_or_else(|| VaultError::AttachmentNotFound(req.name))
    }

    /// Remove an attachment from an entry.
    pub fn remove_attachment(&mut self, entry_id: &str, name: &str) -> Result<()> {
        let entry = find_entry_mut(&mut self.db.root, entry_id)
            .ok_or_else(|| VaultError::EntryNotFound(entry_id.to_string()))?;
        if entry.attachments.remove(name).is_none() {
            return Err(VaultError::AttachmentNotFound(name.to_string()));
        }
        entry.update_history();

        self.rebuild_cache();
        self.dirty = true;
        Ok(())
    }

    /// Set or replace a custom string field.
    pub fn set_custom_field(&mut self, req: SetCustomFieldRequest) -> Result<EntryDetail> {
        validate_custom_field_key(&req.key)?;
        let entry = find_entry_mut(&mut self.db.root, &req.entry_id)
            .ok_or_else(|| VaultError::EntryNotFound(req.entry_id.clone()))?;

        let changed = match entry.fields.get(&req.key) {
            Some(value) => value.get() != &req.value || value.is_protected() != req.protect,
            None => true,
        };
        if changed {
            if req.protect {
                entry.set_protected(req.key.clone(), req.value);
            } else {
                entry.set_unprotected(req.key.clone(), req.value);
            }
            entry.update_history();
            self.rebuild_cache();
            self.dirty = true;
        }

        self.entry_detail(&req.entry_id)
    }

    /// Delete a custom string field from an entry.
    pub fn delete_custom_field(&mut self, entry_id: &str, key: &str) -> Result<EntryDetail> {
        validate_custom_field_key(key)?;
        let entry = find_entry_mut(&mut self.db.root, entry_id)
            .ok_or_else(|| VaultError::EntryNotFound(entry_id.to_string()))?;

        if entry.fields.remove(key).is_some() {
            entry.update_history();
            self.rebuild_cache();
            self.dirty = true;
        }

        self.entry_detail(entry_id)
    }

    /// Move an entry from its current group to a target group.
    pub fn move_entry(&mut self, entry_id: &str, target_group_id: &str) -> Result<EntryDetail> {
        let source = find_group_containing_entry_mut(&mut self.db.root, entry_id)
            .ok_or_else(|| VaultError::EntryNotFound(entry_id.to_string()))?;
        let idx = source
            .entries
            .iter()
            .position(|e| e.uuid.to_string() == entry_id)
            .unwrap();
        let entry = source.entries.remove(idx);
        let target = find_group_mut(&mut self.db.root, target_group_id)
            .ok_or_else(|| VaultError::GroupNotFound(target_group_id.to_string()))?;
        target.entries.push(entry);
        self.rebuild_cache();
        self.dirty = true;
        self.entry_detail(entry_id)
    }

    /// Create a new subgroup.
    pub fn create_group(&mut self, parent_id: &str, name: &str) -> Result<GroupNode> {
        let parent = find_group_mut(&mut self.db.root, parent_id)
            .ok_or_else(|| VaultError::GroupNotFound(parent_id.to_string()))?;
        let mut g = Group::new(name);
        g.times = keepass::db::Times::new();
        let gid = g.uuid.to_string();
        parent.groups.push(g);
        self.rebuild_cache();
        self.dirty = true;
        find_group(&self.group_tree, &gid)
            .cloned()
            .ok_or_else(|| VaultError::GroupNotFound(gid))
    }

    /// Rename a group.
    pub fn rename_group(&mut self, group_id: &str, name: &str) -> Result<GroupNode> {
        let g = find_group_mut(&mut self.db.root, group_id)
            .ok_or_else(|| VaultError::GroupNotFound(group_id.to_string()))?;
        g.name = name.to_string();
        self.rebuild_cache();
        self.dirty = true;
        find_group(&self.group_tree, group_id)
            .cloned()
            .ok_or_else(|| VaultError::GroupNotFound(group_id.to_string()))
    }

    /// Move a group and its contents to the KeePass recycle bin.
    pub fn delete_group(&mut self, group_id: &str) -> Result<()> {
        if self.db.root.uuid.to_string() == group_id {
            return Err(VaultError::InvalidRequest(
                "root group cannot be moved to the recycle bin".to_string(),
            ));
        }
        let parent_group_id = find_group_containing_group(&self.db.root, group_id)
            .map(|group| group.uuid.to_string())
            .ok_or_else(|| VaultError::GroupNotFound(format!("parent of {group_id}")))?;
        let recycle_bin_id = self.ensure_recycle_bin();

        if group_id == recycle_bin_id {
            return Err(VaultError::InvalidRequest(
                "recycle bin cannot be deleted".to_string(),
            ));
        }
        if parent_group_id == recycle_bin_id {
            return self.permanently_delete_group(group_id);
        }

        let (original_parent_id, mut group) = remove_group_from_parent(&mut self.db.root, group_id)
            .ok_or_else(|| VaultError::GroupNotFound(group_id.to_string()))?;
        set_original_parent_group_id(&mut group, original_parent_id);
        let now = Times::now();
        group.times.location_changed = Some(now);
        group.times.last_modification = Some(now);

        let recycle_bin = find_group_mut(&mut self.db.root, &recycle_bin_id)
            .ok_or_else(|| VaultError::GroupNotFound(format!("recycle bin {recycle_bin_id}")))?;
        recycle_bin.groups.push(group);
        self.rebuild_cache();
        self.dirty = true;
        Ok(())
    }

    /// Restore a top-level recycled group to its original parent when possible.
    pub fn restore_group(&mut self, group_id: &str) -> Result<GroupNode> {
        let recycle_bin_id = self
            .recycle_bin_id()
            .ok_or_else(|| VaultError::GroupNotFound(group_id.to_string()))?;
        let parent_group_id = find_group_containing_group(&self.db.root, group_id)
            .map(|group| group.uuid.to_string())
            .ok_or_else(|| VaultError::GroupNotFound(format!("parent of {group_id}")))?;

        if parent_group_id != recycle_bin_id {
            return Err(VaultError::InvalidRequest(
                "group is not a top-level item in the recycle bin".to_string(),
            ));
        }

        let (_, mut group) = remove_group_from_parent(&mut self.db.root, group_id)
            .ok_or_else(|| VaultError::GroupNotFound(group_id.to_string()))?;
        let original_parent_id = take_original_parent_group_id(&mut group);
        let root_id = self.db.root.uuid.to_string();
        let target_parent_id = original_parent_id
            .filter(|id| id != &recycle_bin_id && group_exists(&self.db.root, id))
            .unwrap_or(root_id);

        let now = Times::now();
        group.times.location_changed = Some(now);
        group.times.last_modification = Some(now);
        let target = find_group_mut(&mut self.db.root, &target_parent_id)
            .ok_or_else(|| VaultError::GroupNotFound(target_parent_id.clone()))?;
        target.groups.push(group);

        self.rebuild_cache();
        self.dirty = true;
        find_group(&self.group_tree, group_id)
            .cloned()
            .ok_or_else(|| VaultError::GroupNotFound(group_id.to_string()))
    }

    /// Permanently delete a group and all descendant groups and entries.
    pub fn permanently_delete_group(&mut self, group_id: &str) -> Result<()> {
        if self.db.root.uuid.to_string() == group_id {
            return Err(VaultError::InvalidRequest(
                "root group cannot be permanently deleted".to_string(),
            ));
        }
        if self.recycle_bin_id().as_deref() == Some(group_id) {
            return Err(VaultError::InvalidRequest(
                "recycle bin cannot be permanently deleted".to_string(),
            ));
        }
        let (_, group) = remove_group_from_parent(&mut self.db.root, group_id)
            .ok_or_else(|| VaultError::GroupNotFound(group_id.to_string()))?;
        let deleted_at = Times::now();
        mark_deleted_group(&mut self.db.deleted_objects, &group, deleted_at);
        self.rebuild_cache();
        self.dirty = true;
        Ok(())
    }

    /// Change the master password. Verifies the old password before re-encrypting.
    pub async fn change_password(
        &mut self,
        old_password: &str,
        new_password: &str,
        keyfile: Option<&[u8]>,
    ) -> Result<()> {
        let old_key = build_database_key(old_password, keyfile)?;
        Database::parse(&self.original_bytes, old_key).map_err(|e| {
            VaultError::DatabaseSave(format!("old password verification failed: {e}"))
        })?;
        let new_key = build_database_key(new_password, keyfile)?;
        let mut buf = Vec::new();
        self.db
            .save(&mut buf, new_key)
            .map_err(|e| VaultError::DatabaseSave(e.to_string()))?;
        self.original_bytes = buf;
        self.storage.write(&self.original_bytes).await?;
        Ok(())
    }

    // --- save ---

    /// Persist changes to the storage backend.
    ///
    /// Requires the master password to re-derive the encryption key. For
    /// WebDAV backends this uses `If-Match` to detect remote conflicts.
    /// Callers should handle [`VaultError::Conflict`] and re-open the vault
    /// before retrying.
    ///
    /// **Warning**: KDBX4 writing support in the `keepass` crate is
    /// experimental. Always keep a backup before saving.
    pub async fn save(&mut self, master_password: impl AsRef<str>) -> Result<()> {
        let master_password = master_password.as_ref();
        self.save_inner(master_password, None).await
    }

    /// Persist changes for a database opened with a password plus keyfile.
    pub async fn save_with_keyfile(
        &mut self,
        master_password: impl AsRef<str>,
        keyfile: impl AsRef<[u8]>,
    ) -> Result<()> {
        self.save_inner(master_password.as_ref(), Some(keyfile.as_ref()))
            .await
    }

    async fn save_inner(&mut self, master_password: &str, keyfile: Option<&[u8]>) -> Result<()> {
        let verification_key = build_database_key(master_password, keyfile)?;
        Database::parse(&self.original_bytes, verification_key).map_err(|err| {
            VaultError::DatabaseSave(format!("master password verification failed: {err}"))
        })?;

        let key = build_database_key(master_password, keyfile)?;
        let mut buf = Vec::new();
        self.db
            .save(&mut buf, key)
            .map_err(|err| VaultError::DatabaseSave(err.to_string()))?;
        self.storage.write(&buf).await?;
        self.original_bytes = buf;
        if let Ok(Some(metadata)) = self.storage.metadata().await {
            self.metadata = Some(metadata);
        }
        self.dirty = false;
        Ok(())
    }

    // --- internals ---

    fn rebuild_cache(&mut self) {
        let (tree, details) = build_tree(&self.db);
        self.group_tree = tree;
        self.entry_details = details;
    }

    fn recycle_bin_id(&self) -> Option<String> {
        self.db
            .meta
            .recyclebin_uuid
            .as_ref()
            .map(ToString::to_string)
    }

    fn ensure_recycle_bin(&mut self) -> String {
        if let Some(id) = self.recycle_bin_id() {
            if find_group_mut(&mut self.db.root, &id).is_some() {
                self.db.meta.recyclebin_enabled = Some(true);
                return id;
            }
        }

        if let Some(uuid) = self
            .db
            .root
            .groups
            .iter()
            .find(|group| group.name == RECYCLE_BIN_NAME)
            .map(|group| group.uuid)
        {
            self.db.meta.recyclebin_enabled = Some(true);
            self.db.meta.recyclebin_uuid = Some(uuid);
            self.db.meta.recyclebin_changed = Some(Times::now());
            return uuid.to_string();
        }

        let group = Group::new(RECYCLE_BIN_NAME);
        let id = group.uuid.to_string();
        self.db.meta.recyclebin_enabled = Some(true);
        self.db.meta.recyclebin_uuid = Some(group.uuid);
        self.db.meta.recyclebin_changed = Some(Times::now());
        self.db.root.groups.push(group);
        id
    }
}

impl std::fmt::Debug for VaultSession {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("VaultSession")
            .field("source", &self.source)
            .field("dirty", &self.dirty)
            .field("metadata", &self.metadata)
            .finish_non_exhaustive()
    }
}

// --- tree construction ---

fn build_tree(db: &Database) -> (GroupNode, BTreeMap<String, EntryDetail>) {
    let mut entry_details = BTreeMap::new();
    let recycle_bin_id = db.meta.recyclebin_uuid.as_ref().map(ToString::to_string);
    let tree = group_to_node(&db.root, recycle_bin_id.as_deref(), &mut entry_details);
    (tree, entry_details)
}

fn group_to_node(
    group: &Group,
    recycle_bin_id: Option<&str>,
    entry_details: &mut BTreeMap<String, EntryDetail>,
) -> GroupNode {
    let id = group.uuid.to_string();
    let mut node = GroupNode {
        is_recycle_bin: recycle_bin_id == Some(id.as_str()),
        id,
        name: group.name.clone(),
        entries: Vec::new(),
        groups: Vec::new(),
    };

    for entry in &group.entries {
        let entry_id = entry.uuid.to_string();
        node.entries.push(entry_to_summary(entry_id.clone(), entry));
        entry_details.insert(entry_id.clone(), entry_to_detail(entry_id, entry));
    }

    for child_group in &group.groups {
        node.groups
            .push(group_to_node(child_group, recycle_bin_id, entry_details));
    }

    node
}

// --- DTO converters ---

fn entry_to_summary(id: String, entry: &Entry) -> EntrySummary {
    EntrySummary {
        id,
        title: optional(entry.get_title()),
        username: optional(entry.get_username()),
        url: optional(entry.get_url()),
        expires: entry.times.expires.unwrap_or(false),
        notes: optional(entry.get(fields::NOTES)),
        last_modified: entry.times.last_modification.map(|t| t.to_string()),
    }
}

fn entry_to_detail(id: String, entry: &Entry) -> EntryDetail {
    let known: BTreeSet<&str> = KNOWN_FIELD_KEYS.iter().copied().collect();
    let mut protected_fields = Vec::new();
    let fields = entry
        .fields
        .iter()
        .filter(|(key, _)| !known.contains(key.as_str()))
        .filter_map(|(key, value)| {
            let v = value_to_string(value)?;
            if value.is_protected() {
                protected_fields.push(key.clone());
            }
            Some((key.clone(), v))
        })
        .collect();

    EntryDetail {
        id,
        title: optional(entry.get_title()),
        username: optional(entry.get_username()),
        url: optional(entry.get_url()),
        password: optional(entry.get_password()),
        notes: optional(entry.get(fields::NOTES)),
        expires: entry.times.expires.unwrap_or(false),
        expiry_time: entry.times.expiry.map(|t| t.to_string()),
        fields,
        protected_fields,
        attachments: attachment_summaries(entry),
    }
}

fn attachment_summaries(entry: &Entry) -> Vec<AttachmentSummary> {
    let mut attachments: Vec<_> = entry
        .attachments
        .iter()
        .map(|(name, attachment)| AttachmentSummary {
            name: name.clone(),
            size: attachment.data.get().len(),
            protected: attachment.data.is_protected(),
        })
        .collect();
    attachments.sort_by(|a, b| a.name.cmp(&b.name));
    attachments
}

fn history_summary(index: usize, entry: &Entry) -> HistorySummary {
    HistorySummary {
        index,
        title: optional(entry.get_title()),
        username: optional(entry.get_username()),
        url: optional(entry.get_url()),
        last_modified: entry
            .times
            .last_modification
            .map(|last_modified| last_modified.to_string()),
    }
}

fn optional(value: Option<&str>) -> Option<String> {
    value.filter(|v| !v.is_empty()).map(ToOwned::to_owned)
}

fn value_to_string(value: &Value<String>) -> Option<String> {
    optional(Some(value.get()))
}

fn build_database_key(master_password: &str, keyfile: Option<&[u8]>) -> Result<DatabaseKey> {
    if master_password.is_empty() && keyfile.is_none() {
        return Err(VaultError::InvalidRequest(
            "master password or keyfile is required".to_string(),
        ));
    }

    let mut key = DatabaseKey::new();
    if !master_password.is_empty() {
        key = key.with_password(master_password);
    }
    if let Some(keyfile) = keyfile {
        if keyfile.is_empty() {
            return Err(VaultError::InvalidRequest(
                "keyfile bytes must not be empty".to_string(),
            ));
        }
        let mut cursor = Cursor::new(keyfile);
        key = key
            .with_keyfile(&mut cursor)
            .map_err(|err| VaultError::Storage(format!("failed to read keyfile: {err}")))?;
    }
    Ok(key)
}

fn write_new_database(path: &PathBuf, bytes: &[u8]) -> Result<()> {
    if path.exists() {
        return Err(VaultError::InvalidRequest(format!(
            "vault file already exists: {}",
            path.display()
        )));
    }
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() && !parent.exists() {
            return Err(VaultError::InvalidRequest(format!(
                "parent directory does not exist: {}",
                parent.display()
            )));
        }
    }

    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("vault.kdbx");
    let temp_path = path.with_file_name(format!(".{file_name}.tmp-{}", std::process::id()));
    std::fs::write(&temp_path, bytes)?;
    if let Err(err) = std::fs::rename(&temp_path, path) {
        let _ = std::fs::remove_file(&temp_path);
        return Err(VaultError::Io(err));
    }
    Ok(())
}

// --- field helpers ---

fn validate_custom_field_key(key: &str) -> Result<()> {
    if key.is_empty() {
        return Err(VaultError::InvalidRequest(
            "custom field key must not be empty".to_string(),
        ));
    }
    if KNOWN_FIELD_KEYS.contains(&key) {
        return Err(VaultError::InvalidRequest(format!(
            "custom field key {key:?} conflicts with a standard KeePass field"
        )));
    }
    Ok(())
}

fn set_opt(entry: &mut Entry, key: &str, value: Option<&str>) {
    if let Some(v) = value {
        if !v.is_empty() {
            entry.set_unprotected(key, v);
        }
    }
}

/// `None` = don't touch, `Some("")` = clear, `Some(v)` = set to v.
fn apply_update(entry: &mut Entry, key: &str, value: Option<&str>) -> bool {
    match value {
        None => false,
        Some("") => entry.fields.remove(key).is_some(),
        Some(v) => {
            if entry
                .fields
                .get(key)
                .is_some_and(|current| current.get() == v)
            {
                false
            } else {
                entry.set_unprotected(key, v);
                true
            }
        }
    }
}

/// `None` = don't touch, `Some(false)` = clear expires,
/// `Some(true)` = set expires. `expiry_str` likewise.
fn apply_expiry_update(entry: &mut Entry, expires: Option<bool>, expiry_str: Option<&str>) -> bool {
    let mut changed = false;
    if let Some(exp) = expires {
        if entry.times.expires != Some(exp) {
            entry.times.expires = Some(exp);
            changed = true;
        }
    }
    match expiry_str {
        None => {}
        Some("") => {
            changed = entry.times.expiry.is_some();
            if changed {
                entry.times.expiry = None;
            }
        }
        Some(t) => {
            if let Ok(dt) = chrono::NaiveDateTime::parse_from_str(t, "%Y-%m-%dT%H:%M:%S") {
                if entry.times.expiry != Some(dt) {
                    entry.times.expiry = Some(dt);
                    changed = true;
                }
            }
        }
    }
    changed
}

fn set_original_group_id(entry: &mut Entry, group_id: String) {
    entry.custom_data.insert(
        ORIGINAL_GROUP_CUSTOM_DATA_KEY.to_string(),
        CustomDataItem {
            value: Some(CustomDataValue::String(group_id)),
            last_modification_time: Some(Times::now()),
        },
    );
}

fn take_original_group_id(entry: &mut Entry) -> Option<String> {
    let item = entry.custom_data.remove(ORIGINAL_GROUP_CUSTOM_DATA_KEY)?;
    match item.value {
        Some(CustomDataValue::String(value)) if !value.is_empty() => Some(value),
        _ => None,
    }
}

fn set_original_parent_group_id(group: &mut Group, parent_group_id: String) {
    group.custom_data.insert(
        ORIGINAL_PARENT_GROUP_CUSTOM_DATA_KEY.to_string(),
        CustomDataItem {
            value: Some(CustomDataValue::String(parent_group_id)),
            last_modification_time: Some(Times::now()),
        },
    );
}

fn take_original_parent_group_id(group: &mut Group) -> Option<String> {
    let item = group
        .custom_data
        .remove(ORIGINAL_PARENT_GROUP_CUSTOM_DATA_KEY)?;
    match item.value {
        Some(CustomDataValue::String(value)) if !value.is_empty() => Some(value),
        _ => None,
    }
}

fn find_group_containing_group<'a>(group: &'a Group, group_id: &str) -> Option<&'a Group> {
    if group
        .groups
        .iter()
        .any(|child| child.uuid.to_string() == group_id)
    {
        return Some(group);
    }
    group
        .groups
        .iter()
        .find_map(|child| find_group_containing_group(child, group_id))
}

// --- tree traversal ---

fn find_group<'a>(group: &'a GroupNode, group_id: &str) -> Option<&'a GroupNode> {
    if group.id == group_id {
        return Some(group);
    }
    group
        .groups
        .iter()
        .find_map(|child| find_group(child, group_id))
}

fn find_group_mut<'a>(group: &'a mut Group, group_id: &str) -> Option<&'a mut Group> {
    if group.uuid.to_string() == group_id {
        return Some(group);
    }
    group
        .groups
        .iter_mut()
        .find_map(|child| find_group_mut(child, group_id))
}

fn group_exists(group: &Group, group_id: &str) -> bool {
    if group.uuid.to_string() == group_id {
        return true;
    }
    group
        .groups
        .iter()
        .any(|child| group_exists(child, group_id))
}

fn find_entry<'a>(group: &'a Group, entry_id: &str) -> Option<&'a Entry> {
    for entry in &group.entries {
        if entry.uuid.to_string() == entry_id {
            return Some(entry);
        }
    }
    group
        .groups
        .iter()
        .find_map(|child| find_entry(child, entry_id))
}

fn find_entry_mut<'a>(group: &'a mut Group, entry_id: &str) -> Option<&'a mut Entry> {
    for entry in &mut group.entries {
        if entry.uuid.to_string() == entry_id {
            return Some(entry);
        }
    }
    group
        .groups
        .iter_mut()
        .find_map(|child| find_entry_mut(child, entry_id))
}

fn find_group_containing_entry_mut<'a>(
    group: &'a mut Group,
    entry_id: &str,
) -> Option<&'a mut Group> {
    if group.entries.iter().any(|e| e.uuid.to_string() == entry_id) {
        return Some(group);
    }
    group
        .groups
        .iter_mut()
        .find_map(|child| find_group_containing_entry_mut(child, entry_id))
}

fn find_group_containing_entry<'a>(group: &'a Group, entry_id: &str) -> Option<&'a Group> {
    if group.entries.iter().any(|e| e.uuid.to_string() == entry_id) {
        return Some(group);
    }
    group
        .groups
        .iter()
        .find_map(|child| find_group_containing_entry(child, entry_id))
}

fn remove_entry_from_group(group: &mut Group, entry_id: &str) -> Option<(String, Entry)> {
    if let Some(idx) = group
        .entries
        .iter()
        .position(|entry| entry.uuid.to_string() == entry_id)
    {
        return Some((group.uuid.to_string(), group.entries.remove(idx)));
    }
    group
        .groups
        .iter_mut()
        .find_map(|child| remove_entry_from_group(child, entry_id))
}

fn remove_group_from_parent(group: &mut Group, group_id: &str) -> Option<(String, Group)> {
    if let Some(idx) = group
        .groups
        .iter()
        .position(|child| child.uuid.to_string() == group_id)
    {
        return Some((group.uuid.to_string(), group.groups.remove(idx)));
    }
    group
        .groups
        .iter_mut()
        .find_map(|child| remove_group_from_parent(child, group_id))
}

fn drain_recycle_bin(recycle_bin: &mut Group, entries: &mut Vec<Entry>, groups: &mut Vec<Group>) {
    entries.append(&mut recycle_bin.entries);
    groups.append(&mut recycle_bin.groups);
}

fn mark_deleted_group(
    deleted_objects: &mut HashMap<Uuid, Option<chrono::NaiveDateTime>>,
    group: &Group,
    deleted_at: chrono::NaiveDateTime,
) {
    deleted_objects.insert(group.uuid, Some(deleted_at));
    for entry in &group.entries {
        deleted_objects.insert(entry.uuid, Some(deleted_at));
    }
    for child in &group.groups {
        mark_deleted_group(deleted_objects, child, deleted_at);
    }
}

// --- tests ---

#[cfg(test)]
mod tests {
    use super::*;

    fn test_session() -> VaultSession {
        let db = Database::new(Default::default());
        let mut original_bytes = Vec::new();
        db.save(
            &mut original_bytes,
            DatabaseKey::new().with_password("test-password"),
        )
        .unwrap();
        let storage = LocalFileStorage::new("/tmp/test.kdbx");
        let (group_tree, entry_details) = build_tree(&db);
        VaultSession {
            db,
            original_bytes,
            source: "test".into(),
            metadata: None,
            storage: Box::new(storage),
            dirty: false,
            group_tree,
            entry_details,
        }
    }

    #[test]
    fn finds_entries_by_group_id() {
        let group_id = "a1b2c3d4-e5f6-7890-abcd-ef1234567890";
        let entry_id = "f9e8d7c6-b5a4-3210-fedc-ba0987654321";

        let group = GroupNode {
            id: group_id.to_string(),
            name: "Root".into(),
            is_recycle_bin: false,
            entries: vec![EntrySummary {
                id: entry_id.to_string(),
                title: Some("Email".to_string()),
                username: Some("user".to_string()),
                url: None,
                expires: false,
                notes: None,
                last_modified: None,
            }],
            groups: vec![],
        };

        let mut session = test_session();
        session.group_tree = group;

        let entries = session.entries_for_group(group_id).unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].title.as_deref(), Some("Email"));
    }

    #[test]
    fn entry_detail_lookup() {
        let entry_id = "f9e8d7c6-b5a4-3210-fedc-ba0987654321";
        let detail = EntryDetail {
            id: entry_id.to_string(),
            title: Some("Email".to_string()),
            username: Some("user".to_string()),
            url: Some("https://example.com".to_string()),
            password: Some("secret".to_string()),
            notes: None,
            expires: false,
            expiry_time: None,
            fields: BTreeMap::new(),
            protected_fields: vec![],
            attachments: vec![],
        };

        let mut session = test_session();
        session.entry_details = BTreeMap::from([(entry_id.to_string(), detail)]);

        let detail = session.entry_detail(entry_id).unwrap();
        let json = serde_json::to_string(&detail).unwrap();
        assert!(json.contains("Email"));
    }

    // --- entry mapping (moved from old service tests) ---

    #[test]
    fn maps_all_known_fields() {
        let mut entry = Entry::new();
        entry.set_unprotected(fields::TITLE, "My Title");
        entry.set_unprotected(fields::USERNAME, "alice");
        entry.set_unprotected(fields::PASSWORD, "secret");
        entry.set_unprotected(fields::URL, "https://example.com");
        entry.set_unprotected(fields::NOTES, "some notes");

        let detail = entry_to_detail("id-1".into(), &entry);

        assert_eq!(detail.title.as_deref(), Some("My Title"));
        assert_eq!(detail.username.as_deref(), Some("alice"));
        assert_eq!(detail.password.as_deref(), Some("secret"));
        assert_eq!(detail.url.as_deref(), Some("https://example.com"));
        assert_eq!(detail.notes.as_deref(), Some("some notes"));
    }

    #[test]
    fn known_fields_not_duplicated() {
        let mut entry = Entry::new();
        entry.set_unprotected(fields::TITLE, "T");
        entry.set_unprotected(fields::USERNAME, "U");

        let detail = entry_to_detail("id".into(), &entry);
        assert!(!detail.fields.contains_key(fields::TITLE));
        assert!(!detail.fields.contains_key(fields::USERNAME));
    }

    #[test]
    fn custom_fields_in_map() {
        let mut entry = Entry::new();
        entry.set_unprotected("CustomKey", "custom value");

        let detail = entry_to_detail("id".into(), &entry);
        assert_eq!(
            detail.fields.get("CustomKey").map(String::as_str),
            Some("custom value")
        );
    }

    #[test]
    fn protected_password_readable() {
        let mut entry = Entry::new();
        entry.set_protected(fields::PASSWORD, "protected-secret");

        let detail = entry_to_detail("id".into(), &entry);
        assert_eq!(detail.password.as_deref(), Some("protected-secret"));
    }

    #[test]
    fn empty_fields_become_none() {
        let mut entry = Entry::new();
        entry.set_unprotected(fields::TITLE, "");

        let detail = entry_to_detail("id".into(), &entry);
        assert_eq!(detail.title, None);
    }

    #[test]
    fn missing_fields_become_none() {
        let entry = Entry::new();
        let detail = entry_to_detail("id".into(), &entry);
        assert_eq!(detail.title, None);
        assert_eq!(detail.password, None);
        assert_eq!(detail.notes, None);
        assert!(detail.fields.is_empty());
    }

    #[test]
    fn empty_custom_field_filtered() {
        let mut entry = Entry::new();
        entry.set_unprotected("EmptyField", "");

        let detail = entry_to_detail("id".into(), &entry);
        assert!(!detail.fields.contains_key("EmptyField"));
    }

    // --- mutation tests ---

    #[test]
    fn create_entry_in_root() {
        let mut session = test_session();
        let root_id = session.db.root.uuid.to_string();

        let detail = session
            .create_entry(CreateEntryRequest {
                group_id: root_id.clone(),
                title: Some("New Entry".into()),
                username: Some("alice".into()),
                password: Some("pass".into()),
                url: Some("https://example.com".into()),
                notes: Some("notes".into()),
                custom_fields: BTreeMap::new(),
                protected_custom_fields: vec![],
                expires: false,
                expiry_time: None,
            })
            .unwrap();

        assert_eq!(detail.title.as_deref(), Some("New Entry"));
        assert_eq!(detail.username.as_deref(), Some("alice"));
        assert!(session.is_dirty());
        assert_eq!(session.db.root.entries.len(), 1);
    }

    #[test]
    fn create_entry_nonexistent_group() {
        let mut session = test_session();
        let err = session
            .create_entry(CreateEntryRequest {
                group_id: "nonexistent-uuid".into(),
                title: Some("X".into()),
                username: None,
                password: None,
                url: None,
                notes: None,
                custom_fields: BTreeMap::new(),
                protected_custom_fields: vec![],
                expires: false,
                expiry_time: None,
            })
            .unwrap_err();

        assert!(matches!(err, VaultError::GroupNotFound(_)));
        assert!(!session.is_dirty());
    }

    #[test]
    fn update_entry_changes_fields() {
        let mut session = test_session();
        let root_id = session.db.root.uuid.to_string();

        // Create an entry first
        let created = session
            .create_entry(CreateEntryRequest {
                group_id: root_id.clone(),
                title: Some("Original".into()),
                username: Some("old".into()),
                password: Some("oldpass".into()),
                url: None,
                notes: None,
                custom_fields: BTreeMap::new(),
                protected_custom_fields: vec![],
                expires: false,
                expiry_time: None,
            })
            .unwrap();

        // Update it
        let updated = session
            .update_entry(UpdateEntryRequest {
                entry_id: created.id.clone(),
                title: Some("Changed".into()),
                username: None,            // leave unchanged
                password: Some("".into()), // clear
                url: Some("https://new.example".into()),
                notes: None,
                expires: None,
                expiry_time: None,
            })
            .unwrap();

        assert_eq!(updated.title.as_deref(), Some("Changed"));
        assert_eq!(updated.username.as_deref(), Some("old")); // preserved
        assert_eq!(updated.password, None); // cleared
        assert_eq!(updated.url.as_deref(), Some("https://new.example"));
    }

    #[test]
    fn update_entry_noop_does_not_mark_dirty() {
        let mut session = test_session();
        let root_id = session.db.root.uuid.to_string();

        let created = session
            .create_entry(CreateEntryRequest {
                group_id: root_id,
                title: Some("Original".into()),
                username: Some("old".into()),
                password: Some("oldpass".into()),
                url: None,
                notes: None,
                custom_fields: BTreeMap::new(),
                protected_custom_fields: vec![],
                expires: false,
                expiry_time: None,
            })
            .unwrap();

        session.dirty = false;
        let updated = session
            .update_entry(UpdateEntryRequest {
                entry_id: created.id,
                title: Some("Original".into()),
                username: None,
                password: Some("oldpass".into()),
                url: None,
                notes: None,
                expires: None,
                expiry_time: None,
            })
            .unwrap();

        assert_eq!(updated.title.as_deref(), Some("Original"));
        assert!(!session.is_dirty());
    }

    #[test]
    fn update_entry_nonexistent() {
        let mut session = test_session();
        let err = session
            .update_entry(UpdateEntryRequest {
                entry_id: "nonexistent".into(),
                title: Some("X".into()),
                username: None,
                password: None,
                url: None,
                notes: None,
                expires: None,
                expiry_time: None,
            })
            .unwrap_err();

        assert!(matches!(err, VaultError::EntryNotFound(_)));
        assert!(!session.is_dirty());
    }

    #[test]
    fn delete_entry_moves_to_recycle_bin_and_restore() {
        let mut session = test_session();
        let root_id = session.db.root.uuid.to_string();

        let created = session
            .create_entry(CreateEntryRequest {
                group_id: root_id.clone(),
                title: Some("To Delete".into()),
                username: None,
                password: None,
                url: None,
                notes: None,
                custom_fields: BTreeMap::new(),
                protected_custom_fields: vec![],
                expires: false,
                expiry_time: None,
            })
            .unwrap();

        assert_eq!(session.db.root.entries.len(), 1);
        assert!(session.is_dirty());

        // Reset dirty so we can test that delete marks it
        session.dirty = false;
        session.delete_entry(&created.id).unwrap();

        assert_eq!(session.db.root.entries.len(), 0);
        let recycle_bin_id = session.db.meta.recyclebin_uuid.unwrap().to_string();
        let recycle_bin = find_group(&session.group_tree, &recycle_bin_id).unwrap();
        assert!(recycle_bin.is_recycle_bin);
        assert_eq!(recycle_bin.entries.len(), 1);
        assert_eq!(recycle_bin.entries[0].id, created.id);
        assert!(session.is_dirty());

        let restored = session.restore_entry(&created.id).unwrap();
        assert_eq!(restored.title.as_deref(), Some("To Delete"));
        assert_eq!(session.db.root.entries.len(), 1);
        let recycle_bin = find_group(&session.group_tree, &recycle_bin_id).unwrap();
        assert!(recycle_bin.entries.is_empty());
    }

    #[test]
    fn permanently_delete_entry_records_deleted_object() {
        let mut session = test_session();
        let root_id = session.db.root.uuid.to_string();
        let created = session
            .create_entry(CreateEntryRequest {
                group_id: root_id,
                title: Some("Gone".into()),
                username: None,
                password: None,
                url: None,
                notes: None,
                custom_fields: BTreeMap::new(),
                protected_custom_fields: vec![],
                expires: false,
                expiry_time: None,
            })
            .unwrap();

        session.permanently_delete_entry(&created.id).unwrap();

        assert!(!session.entry_details.contains_key(&created.id));
        assert_eq!(session.db.deleted_objects.len(), 1);
    }

    #[test]
    fn empty_recycle_bin_removes_recycled_entries() {
        let mut session = test_session();
        let root_id = session.db.root.uuid.to_string();
        let created = session
            .create_entry(CreateEntryRequest {
                group_id: root_id,
                title: Some("Trash".into()),
                username: None,
                password: None,
                url: None,
                notes: None,
                custom_fields: BTreeMap::new(),
                protected_custom_fields: vec![],
                expires: false,
                expiry_time: None,
            })
            .unwrap();

        session.delete_entry(&created.id).unwrap();
        session.empty_recycle_bin().unwrap();

        assert!(!session.entry_details.contains_key(&created.id));
        let recycle_bin_id = session.db.meta.recyclebin_uuid.unwrap().to_string();
        let recycle_bin = find_group(&session.group_tree, &recycle_bin_id).unwrap();
        assert!(recycle_bin.entries.is_empty());
        assert_eq!(session.db.deleted_objects.len(), 1);
    }

    #[test]
    fn delete_group_moves_to_recycle_bin_and_restore() {
        let mut session = test_session();
        let root_id = session.db.root.uuid.to_string();
        let group = session.create_group(&root_id, "Projects").unwrap();

        session.dirty = false;
        session.delete_group(&group.id).unwrap();

        let recycle_bin_id = session.db.meta.recyclebin_uuid.unwrap().to_string();
        let recycle_bin = find_group(&session.group_tree, &recycle_bin_id).unwrap();
        assert!(recycle_bin.is_recycle_bin);
        assert_eq!(recycle_bin.groups.len(), 1);
        assert_eq!(recycle_bin.groups[0].name, "Projects");
        assert!(find_group(&session.group_tree, &group.id).is_some());
        assert!(session.is_dirty());

        session.restore_group(&group.id).unwrap();

        let restored = find_group(&session.group_tree, &group.id).unwrap();
        assert_eq!(restored.name, "Projects");
        let recycle_bin = find_group(&session.group_tree, &recycle_bin_id).unwrap();
        assert!(recycle_bin.groups.is_empty());
    }

    #[test]
    fn empty_recycle_bin_removes_recycled_groups() {
        let mut session = test_session();
        let root_id = session.db.root.uuid.to_string();
        let group = session.create_group(&root_id, "Old").unwrap();

        session.delete_group(&group.id).unwrap();
        session.empty_recycle_bin().unwrap();

        assert!(find_group(&session.group_tree, &group.id).is_none());
        assert_eq!(session.db.deleted_objects.len(), 1);
    }

    #[test]
    fn delete_entry_nonexistent() {
        let mut session = test_session();
        let err = session.delete_entry("nonexistent").unwrap_err();
        assert!(matches!(err, VaultError::EntryNotFound(_)));
        assert!(session.db.meta.recyclebin_uuid.is_none());
        assert!(session.db.root.groups.is_empty());
    }

    #[test]
    fn cache_rebuilds_after_mutation() {
        let mut session = test_session();
        let root_id = session.db.root.uuid.to_string();

        let created = session
            .create_entry(CreateEntryRequest {
                group_id: root_id.clone(),
                title: Some("Cached".into()),
                username: None,
                password: None,
                url: None,
                notes: None,
                custom_fields: BTreeMap::new(),
                protected_custom_fields: vec![],
                expires: false,
                expiry_time: None,
            })
            .unwrap();

        // Cache should reflect the new entry
        assert!(session.entry_details.contains_key(&created.id));
        let tree = session.group_tree();
        assert_eq!(tree.entries.len(), 1);
    }

    #[test]
    fn keyfile_open_and_save_round_trip() {
        let keyfile = b"test-keyfile-material";
        let db = Database::new(Default::default());
        let mut bytes = Vec::new();
        db.save(
            &mut bytes,
            build_database_key("test-password", Some(keyfile)).unwrap(),
        )
        .unwrap();

        let tmp =
            std::env::temp_dir().join(format!("keepass-rs-keyfile-{}.kdbx", std::process::id()));
        std::fs::write(&tmp, bytes).unwrap();

        let rt = tokio::runtime::Runtime::new().unwrap();
        assert!(rt
            .block_on(VaultService.open_local(&tmp, "test-password"))
            .is_err());

        let mut session = rt
            .block_on(VaultService.open_local_with_keyfile(&tmp, "test-password", keyfile))
            .unwrap();
        let root_id = session.db.root.uuid.to_string();
        session
            .create_entry(CreateEntryRequest {
                group_id: root_id,
                title: Some("Keyfile Entry".into()),
                username: None,
                password: None,
                url: None,
                notes: None,
                custom_fields: BTreeMap::new(),
                protected_custom_fields: vec![],
                expires: false,
                expiry_time: None,
            })
            .unwrap();
        rt.block_on(session.save_with_keyfile("test-password", keyfile))
            .unwrap();

        let reopened = rt
            .block_on(VaultService.open_local_with_keyfile(&tmp, "test-password", keyfile))
            .unwrap();
        assert_eq!(reopened.group_tree().entries.len(), 1);

        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn attachment_metadata_and_bytes_are_separate() {
        let mut session = test_session();
        let root_id = session.db.root.uuid.to_string();
        let created = session
            .create_entry(CreateEntryRequest {
                group_id: root_id,
                title: Some("With Attachment".into()),
                username: None,
                password: None,
                url: None,
                notes: None,
                custom_fields: BTreeMap::new(),
                protected_custom_fields: vec![],
                expires: false,
                expiry_time: None,
            })
            .unwrap();

        let summary = session
            .upsert_attachment(UpsertAttachmentRequest {
                entry_id: created.id.clone(),
                name: "secret.bin".into(),
                bytes: vec![1, 2, 3, 4],
                protect: true,
            })
            .unwrap();

        assert_eq!(summary.name, "secret.bin");
        assert_eq!(summary.size, 4);
        assert!(summary.protected);

        let detail = session.entry_detail(&created.id).unwrap();
        assert_eq!(detail.attachments, vec![summary]);
        let json = serde_json::to_string(&detail).unwrap();
        assert!(json.contains("secret.bin"));
        assert!(!json.contains("\"bytes\""));

        let bytes = session.attachment_bytes(&created.id, "secret.bin").unwrap();
        assert_eq!(bytes.bytes, vec![1, 2, 3, 4]);
        assert!(bytes.protected);

        session
            .remove_attachment(&created.id, "secret.bin")
            .unwrap();
        assert!(session
            .attachments_for_entry(&created.id)
            .unwrap()
            .is_empty());
    }

    #[test]
    fn custom_field_editing_rejects_known_field_conflicts() {
        let mut session = test_session();
        let root_id = session.db.root.uuid.to_string();
        let created = session
            .create_entry(CreateEntryRequest {
                group_id: root_id,
                title: Some("Custom Fields".into()),
                username: None,
                password: None,
                url: None,
                notes: None,
                custom_fields: BTreeMap::new(),
                protected_custom_fields: vec![],
                expires: false,
                expiry_time: None,
            })
            .unwrap();

        let detail = session
            .set_custom_field(SetCustomFieldRequest {
                entry_id: created.id.clone(),
                key: "ApiKey".into(),
                value: "secret".into(),
                protect: true,
            })
            .unwrap();
        assert_eq!(
            detail.fields.get("ApiKey").map(String::as_str),
            Some("secret")
        );

        session.dirty = false;
        session
            .set_custom_field(SetCustomFieldRequest {
                entry_id: created.id.clone(),
                key: "ApiKey".into(),
                value: "secret".into(),
                protect: true,
            })
            .unwrap();
        assert!(!session.is_dirty());

        let err = session
            .set_custom_field(SetCustomFieldRequest {
                entry_id: created.id.clone(),
                key: fields::TITLE.into(),
                value: "bad".into(),
                protect: false,
            })
            .unwrap_err();
        assert!(matches!(err, VaultError::InvalidRequest(_)));

        let detail = session.delete_custom_field(&created.id, "ApiKey").unwrap();
        assert!(!detail.fields.contains_key("ApiKey"));
    }

    #[test]
    fn history_api_lists_and_reads_snapshots() {
        let mut session = test_session();
        let root_id = session.db.root.uuid.to_string();
        let created = session
            .create_entry(CreateEntryRequest {
                group_id: root_id,
                title: Some("Original".into()),
                username: Some("alice".into()),
                password: None,
                url: None,
                notes: None,
                custom_fields: BTreeMap::new(),
                protected_custom_fields: vec![],
                expires: false,
                expiry_time: None,
            })
            .unwrap();

        session
            .update_entry(UpdateEntryRequest {
                entry_id: created.id.clone(),
                title: Some("Changed".into()),
                username: None,
                password: None,
                url: Some("https://example.com".into()),
                notes: None,
                expires: None,
                expiry_time: None,
            })
            .unwrap();

        let history = session.entry_history(&created.id).unwrap();
        assert_eq!(history.len(), 1);
        assert_eq!(history[0].index, 0);
        assert_eq!(history[0].title.as_deref(), Some("Changed"));

        let snapshot = session.entry_history_detail(&created.id, 0).unwrap();
        assert_eq!(snapshot.title.as_deref(), Some("Changed"));
        assert!(matches!(
            session.entry_history_detail(&created.id, 99).unwrap_err(),
            VaultError::HistoryNotFound(_)
        ));
    }

    #[test]
    fn save_writes_bytes() {
        let mut session = test_session();

        let root_id = session.db.root.uuid.to_string();
        let created = session
            .create_entry(CreateEntryRequest {
                group_id: root_id,
                title: Some("E1".into()),
                username: None,
                password: None,
                url: None,
                notes: None,
                custom_fields: BTreeMap::new(),
                protected_custom_fields: vec![],
                expires: false,
                expiry_time: None,
            })
            .unwrap();
        session
            .set_custom_field(SetCustomFieldRequest {
                entry_id: created.id.clone(),
                key: "ApiKey".into(),
                value: "secret".into(),
                protect: true,
            })
            .unwrap();
        session
            .upsert_attachment(UpsertAttachmentRequest {
                entry_id: created.id,
                name: "note.txt".into(),
                bytes: b"hello".to_vec(),
                protect: false,
            })
            .unwrap();

        let tmp = std::env::temp_dir().join(format!("keepass-rs-save-{}.kdbx", std::process::id()));
        session.storage = Box::new(LocalFileStorage::new(&tmp));

        let rt = tokio::runtime::Runtime::new().unwrap();
        rt.block_on(session.save("test-password")).unwrap();

        assert!(!session.is_dirty());
        assert!(tmp.exists());

        let bytes = std::fs::read(&tmp).unwrap();
        let reopened =
            Database::parse(&bytes, DatabaseKey::new().with_password("test-password")).unwrap();
        assert_eq!(reopened.root.entries.len(), 1);
        assert_eq!(reopened.root.entries[0].get_title(), Some("E1"));
        assert_eq!(reopened.root.entries[0].get("ApiKey"), Some("secret"));
        let attachment = reopened.root.entries[0]
            .attachments
            .get("note.txt")
            .unwrap();
        assert_eq!(attachment.data.get(), b"hello");

        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn save_rejects_wrong_master_password_without_writing() {
        let mut session = test_session();

        let root_id = session.db.root.uuid.to_string();
        session
            .create_entry(CreateEntryRequest {
                group_id: root_id,
                title: Some("E1".into()),
                username: None,
                password: None,
                url: None,
                notes: None,
                custom_fields: BTreeMap::new(),
                protected_custom_fields: vec![],
                expires: false,
                expiry_time: None,
            })
            .unwrap();

        let tmp = std::env::temp_dir().join(format!(
            "keepass-rs-save-wrong-password-{}.kdbx",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&tmp);
        session.storage = Box::new(LocalFileStorage::new(&tmp));

        let rt = tokio::runtime::Runtime::new().unwrap();
        let err = rt.block_on(session.save("wrong-password")).unwrap_err();

        assert!(matches!(err, VaultError::DatabaseSave(_)));
        assert!(session.is_dirty());
        assert!(!tmp.exists());
    }
}
