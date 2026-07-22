class AgentMemoryEntry {
  final String id;
  final String content;
  final String category;
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool enabled;

  const AgentMemoryEntry({
    required this.id,
    required this.content,
    required this.category,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    this.enabled = true,
  });

  AgentMemoryEntry copyWith({
    String? content,
    String? category,
    String? source,
    DateTime? updatedAt,
    bool? enabled,
  }) {
    return AgentMemoryEntry(
      id: id,
      content: content ?? this.content,
      category: category ?? this.category,
      source: source ?? this.source,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      enabled: enabled ?? this.enabled,
    );
  }

  factory AgentMemoryEntry.fromJson(Map<String, dynamic> json) {
    return AgentMemoryEntry(
      id: json['id'] as String,
      content: json['content'] as String? ?? '',
      category: json['category'] as String? ?? 'general',
      source: json['source'] as String? ?? 'user',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'category': category,
    'source': source,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'enabled': enabled,
  };
}
