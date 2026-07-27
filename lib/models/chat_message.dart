class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;
  final AgentActionResult? actionResult;
  final List<String>? attachments; // local file paths of attached images

  ChatMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.actionResult,
    this.attachments,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isUser => role == 'user';
  bool get hasAttachments => attachments != null && attachments!.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'actionResult': actionResult?.toJson(),
        'attachments': attachments,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        role: json['role'] as String,
        content: json['content'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        actionResult: json['actionResult'] != null
            ? AgentActionResult.fromJson(json['actionResult'] as Map<String, dynamic>)
            : null,
        attachments: (json['attachments'] as List?)?.cast<String>(),
      );
}

class AgentActionResult {
  final String actionType;
  final bool success;
  final String? details;

  AgentActionResult({
    required this.actionType,
    required this.success,
    this.details,
  });

  Map<String, dynamic> toJson() => {
        'actionType': actionType,
        'success': success,
        'details': details,
      };

  factory AgentActionResult.fromJson(Map<String, dynamic> json) => AgentActionResult(
        actionType: json['actionType'] as String,
        success: json['success'] as bool,
        details: json['details'] as String?,
      );
}
