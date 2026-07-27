class AiProfile {
  final String id;
  final String name;
  final String apiKey;
  final String baseUrl;
  final String model;

  AiProfile({
    required this.id,
    required this.name,
    required this.apiKey,
    required this.baseUrl,
    required this.model,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'model': model,
      };

  factory AiProfile.fromJson(Map<String, dynamic> json) => AiProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        apiKey: json['apiKey'] as String,
        baseUrl: json['baseUrl'] as String,
        model: json['model'] as String,
      );
}
