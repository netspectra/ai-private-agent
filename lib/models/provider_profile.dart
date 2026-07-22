class ProviderProfile {
  final String id;
  final String name;
  final String baseUrl;
  final String model;
  final double temperature;
  final int maxTokens;
  final int maxSteps;
  final bool disableMaxSteps;
  final bool useScreenCompression;
  final bool useSystemPrompt;
  final DateTime updatedAt;

  const ProviderProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.temperature,
    required this.maxTokens,
    required this.maxSteps,
    required this.disableMaxSteps,
    required this.useScreenCompression,
    required this.useSystemPrompt,
    required this.updatedAt,
  });

  factory ProviderProfile.fromJson(Map<String, dynamic> json) =>
      ProviderProfile(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Custom',
        baseUrl: json['base_url'] as String? ?? '',
        model: json['model'] as String? ?? '',
        temperature: (json['temperature'] as num?)?.toDouble() ?? 1.0,
        maxTokens: json['max_tokens'] as int? ?? 1024,
        maxSteps: json['max_steps'] as int? ?? 15,
        disableMaxSteps: json['disable_max_steps'] as bool? ?? false,
        useScreenCompression: json['use_screen_compression'] as bool? ?? true,
        useSystemPrompt: json['use_system_prompt'] as bool? ?? true,
        updatedAt:
            DateTime.tryParse(json['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'base_url': baseUrl,
    'model': model,
    'temperature': temperature,
    'max_tokens': maxTokens,
    'max_steps': maxSteps,
    'disable_max_steps': disableMaxSteps,
    'use_screen_compression': useScreenCompression,
    'use_system_prompt': useSystemPrompt,
    'updated_at': updatedAt.toIso8601String(),
  };
}
