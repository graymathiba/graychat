library;

class Group {
  final String id;
  final String name;
  final String creatorId;
  final List<String> memberIds;
  final DateTime createdAt;
  final String? avatarBase64;

  Group({
    required this.id,
    required this.name,
    required this.creatorId,
    required this.memberIds,
    required this.createdAt,
    this.avatarBase64,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as String,
      name: json['name'] as String,
      creatorId: json['creatorId'] as String,
      memberIds: (json['memberIds'] as List?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      avatarBase64: json['avatarBase64'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'creatorId': creatorId,
      'memberIds': memberIds,
      'createdAt': createdAt.toIso8601String(),
      if (avatarBase64 != null) 'avatarBase64': avatarBase64,
    };
  }

  Group copyWith({
    String? id,
    String? name,
    String? creatorId,
    List<String>? memberIds,
    DateTime? createdAt,
    String? avatarBase64,
  }) {
    return Group(
      id: id ?? this.id,
      name: name ?? this.name,
      creatorId: creatorId ?? this.creatorId,
      memberIds: memberIds ?? this.memberIds,
      createdAt: createdAt ?? this.createdAt,
      avatarBase64: avatarBase64 ?? this.avatarBase64,
    );
  }

  @override
  String toString() => 'Group(id: $id, name: $name, members: ${memberIds.length})';
}
