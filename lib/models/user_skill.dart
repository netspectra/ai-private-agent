class UserSkill {
  final String id;
  final String name;
  final String description;
  final List<String> triggers;
  final String instructions;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool enabled;

  const UserSkill({
    required this.id,
    required this.name,
    required this.description,
    required this.triggers,
    required this.instructions,
    required this.createdAt,
    required this.updatedAt,
    this.enabled = true,
  });

  String get commandName => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9а-яё]+', unicode: true), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  UserSkill copyWith({
    String? name,
    String? description,
    List<String>? triggers,
    String? instructions,
    DateTime? updatedAt,
    bool? enabled,
  }) {
    return UserSkill(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      triggers: triggers ?? this.triggers,
      instructions: instructions ?? this.instructions,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      enabled: enabled ?? this.enabled,
    );
  }

  factory UserSkill.fromJson(Map<String, dynamic> json) => UserSkill(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    description: json['description'] as String? ?? '',
    triggers: List<String>.from(json['triggers'] as List? ?? const []),
    instructions: json['instructions'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['created_at'] as String? ?? '') ??
        DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updated_at'] as String? ?? '') ??
        DateTime.now(),
    enabled: json['enabled'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'triggers': triggers,
    'instructions': instructions,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'enabled': enabled,
  };
}
