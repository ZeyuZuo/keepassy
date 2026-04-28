import 'dart:collection';

class OpenedVault {
  const OpenedVault({
    required this.source,
    required this.groupTree,
    this.metadata,
  });

  final String source;
  final RemoteMetadata? metadata;
  final GroupNode groupTree;

  factory OpenedVault.fromJson(Map<String, Object?> json) {
    return OpenedVault(
      source: json['source'] as String? ?? '',
      metadata: json['metadata'] is Map<String, Object?>
          ? RemoteMetadata.fromJson(json['metadata']! as Map<String, Object?>)
          : null,
      groupTree: GroupNode.fromJson(
        json['group_tree']! as Map<String, Object?>,
      ),
    );
  }
}

class RemoteMetadata {
  const RemoteMetadata({this.etag, this.lastModified, this.contentLength});

  final String? etag;
  final String? lastModified;
  final int? contentLength;

  factory RemoteMetadata.fromJson(Map<String, Object?> json) {
    return RemoteMetadata(
      etag: json['etag'] as String?,
      lastModified: json['last_modified'] as String?,
      contentLength: json['content_length'] as int?,
    );
  }
}

class GroupNode {
  const GroupNode({
    required this.id,
    required this.name,
    required this.entries,
    required this.groups,
  });

  final String id;
  final String name;
  final List<EntrySummary> entries;
  final List<GroupNode> groups;

  factory GroupNode.fromJson(Map<String, Object?> json) {
    return GroupNode(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled group',
      entries: (json['entries'] as List<Object?>? ?? const [])
          .cast<Map<String, Object?>>()
          .map(EntrySummary.fromJson)
          .toList(growable: false),
      groups: (json['groups'] as List<Object?>? ?? const [])
          .cast<Map<String, Object?>>()
          .map(GroupNode.fromJson)
          .toList(growable: false),
    );
  }

  Iterable<GroupNode> flatten() sync* {
    yield this;
    for (final child in groups) {
      yield* child.flatten();
    }
  }

  int get entryCount {
    return entries.length +
        groups.fold<int>(0, (total, group) => total + group.entryCount);
  }
}

class EntrySummary {
  const EntrySummary({required this.id, this.title, this.username, this.url});

  final String id;
  final String? title;
  final String? username;
  final String? url;

  String get displayTitle {
    final value = title?.trim();
    return value == null || value.isEmpty ? 'Untitled entry' : value;
  }

  factory EntrySummary.fromJson(Map<String, Object?> json) {
    return EntrySummary(
      id: json['id'] as String? ?? '',
      title: json['title'] as String?,
      username: json['username'] as String?,
      url: json['url'] as String?,
    );
  }
}

class EntryDetail {
  const EntryDetail({
    required this.id,
    this.title,
    this.username,
    this.url,
    this.password,
    this.notes,
    this.fields = const {},
    this.attachments = const [],
  });

  final String id;
  final String? title;
  final String? username;
  final String? url;
  final String? password;
  final String? notes;
  final Map<String, String> fields;
  final List<AttachmentSummary> attachments;

  String get displayTitle {
    final value = title?.trim();
    return value == null || value.isEmpty ? 'Untitled entry' : value;
  }

  UnmodifiableMapView<String, String> get readonlyFields {
    return UnmodifiableMapView(fields);
  }

  factory EntryDetail.fromJson(Map<String, Object?> json) {
    final rawFields = json['fields'] as Map<String, Object?>? ?? const {};

    return EntryDetail(
      id: json['id'] as String? ?? '',
      title: json['title'] as String?,
      username: json['username'] as String?,
      url: json['url'] as String?,
      password: json['password'] as String?,
      notes: json['notes'] as String?,
      fields: rawFields.map(
        (key, value) => MapEntry(key, value?.toString() ?? ''),
      ),
      attachments: (json['attachments'] as List<Object?>? ?? const [])
          .cast<Map<String, Object?>>()
          .map(AttachmentSummary.fromJson)
          .toList(growable: false),
    );
  }
}

class AttachmentSummary {
  const AttachmentSummary({
    required this.name,
    required this.size,
    required this.protected,
  });

  final String name;
  final int size;
  final bool protected;

  factory AttachmentSummary.fromJson(Map<String, Object?> json) {
    return AttachmentSummary(
      name: json['name'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      protected: json['protected'] as bool? ?? false,
    );
  }
}

class CreateEntryRequest {
  const CreateEntryRequest({
    required this.groupId,
    this.title,
    this.username,
    this.password,
    this.url,
    this.notes,
    this.customFields = const {},
  });

  final String groupId;
  final String? title;
  final String? username;
  final String? password;
  final String? url;
  final String? notes;
  final Map<String, String> customFields;

  Map<String, Object?> toJson() => {
    'group_id': groupId,
    'title': title,
    'username': username,
    'password': password,
    'url': url,
    'notes': notes,
    'custom_fields': customFields,
  };
}

class UpdateEntryRequest {
  const UpdateEntryRequest({
    required this.entryId,
    this.title,
    this.username,
    this.password,
    this.url,
    this.notes,
  });

  final String entryId;
  final String? title;
  final String? username;
  final String? password;
  final String? url;
  final String? notes;

  Map<String, Object?> toJson() => {
    'entry_id': entryId,
    'title': title,
    'username': username,
    'password': password,
    'url': url,
    'notes': notes,
  };
}
