class ActionStep {
  final String action;
  final Map<String, dynamic> params;

  ActionStep({required this.action, required this.params});

  factory ActionStep.fromJson(Map<String, dynamic> json) {
    return ActionStep(
      action: json['action'] as String? ?? '',
      params: json['params'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {'action': action, 'params': params};
  }
}

class SavedSkill {
  final String id;
  final String task;
  final List<String> taskKeywords;
  int successCount;
  int failCount;
  DateTime lastUsed;
  final List<ActionStep> steps;
  bool enabled;
  bool autoReplay;

  SavedSkill({
    required this.id,
    required this.task,
    required this.taskKeywords,
    this.successCount = 0,
    this.failCount = 0,
    required this.lastUsed,
    required this.steps,
    this.enabled = true,
    this.autoReplay = false,
  });

  bool get isReliable =>
      enabled &&
      autoReplay &&
      canAutoReplay &&
      successCount >= 1 &&
      (failCount / (successCount + failCount)) < 0.3;

  bool get canAutoReplay => steps.every(
    (step) => step.params['redacted'] != true && step.action != 'type_text',
  );

  factory SavedSkill.fromJson(Map<String, dynamic> json) {
    return SavedSkill(
      id: json['id'] as String,
      task: json['task'] as String,
      taskKeywords: List<String>.from(json['task_keywords'] ?? []),
      successCount: json['success_count'] as int? ?? 0,
      failCount: json['fail_count'] as int? ?? 0,
      lastUsed: DateTime.parse(json['last_used'] as String),
      steps: (json['steps'] as List)
          .map((s) => ActionStep.fromJson(s as Map<String, dynamic>))
          .toList(),
      enabled: json['enabled'] as bool? ?? true,
      // Legacy skills are kept but are not silently replayed. The user may
      // explicitly opt in after reviewing the recorded steps.
      autoReplay: json['auto_replay'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'task': task,
      'task_keywords': taskKeywords,
      'success_count': successCount,
      'fail_count': failCount,
      'last_used': lastUsed.toIso8601String(),
      'steps': steps.map((s) => s.toJson()).toList(),
      'enabled': enabled,
      'auto_replay': autoReplay,
    };
  }
}
