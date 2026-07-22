import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/agent_memory_entry.dart';
import '../models/saved_skill.dart';
import 'text_relevance.dart';

class AgentMemoryService {
  AgentMemoryService._();
  static final AgentMemoryService instance = AgentMemoryService._();

  static const int maxStoredCharacters = 12000;
  static const int maxInjectedCharacters = 4000;
  List<AgentMemoryEntry>? _cache;

  Future<File> get _file async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/agent_memory.json');
  }

  static String? validateContent(String value) {
    final text = value.trim();
    if (text.isEmpty) return 'Memory cannot be empty.';
    if (text.length > 1200) {
      return 'A memory entry is limited to 1,200 characters.';
    }
    final unsafe = RegExp(
      r'(api[_ -]?key|access[_ -]?token|password|private[_ -]?key|begin [a-z ]*private key|ignore (all|previous) instructions|reveal .*secret)',
      caseSensitive: false,
    );
    final invisible = RegExp(r'[\u200B-\u200F\u202A-\u202E\u2060-\u206F]');
    if (unsafe.hasMatch(text) || invisible.hasMatch(text)) {
      return 'Secrets and prompt-injection text are not allowed in memory.';
    }
    return null;
  }

  Future<List<AgentMemoryEntry>> list() async {
    if (_cache != null) return List.unmodifiable(_cache!);
    try {
      final file = await _file;
      if (!await file.exists()) return _cache = [];
      final decoded = jsonDecode(await file.readAsString());
      _cache = (decoded as List)
          .map(
            (item) => AgentMemoryEntry.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    } catch (_) {
      _cache = [];
    }
    return List.unmodifiable(_cache!);
  }

  Future<void> upsert({
    String? id,
    required String content,
    String category = 'general',
    String source = 'user',
  }) async {
    final error = validateContent(content);
    if (error != null) throw ArgumentError(error);
    await list();
    final now = DateTime.now();
    final normalized = content.trim();
    final duplicate = _cache!.any(
      (entry) =>
          entry.id != id &&
          entry.content.toLowerCase() == normalized.toLowerCase(),
    );
    if (duplicate) return;
    final index = id == null
        ? -1
        : _cache!.indexWhere((entry) => entry.id == id);
    if (index >= 0) {
      _cache![index] = _cache![index].copyWith(
        content: normalized,
        category: category,
        source: source,
        updatedAt: now,
      );
    } else {
      _cache!.add(
        AgentMemoryEntry(
          id: now.microsecondsSinceEpoch.toString(),
          content: normalized,
          category: category,
          source: source,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await _trimAndSave();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await list();
    final index = _cache!.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    _cache![index] = _cache![index].copyWith(
      enabled: enabled,
      updatedAt: DateTime.now(),
    );
    await _save();
  }

  Future<void> delete(String id) async {
    await list();
    _cache!.removeWhere((entry) => entry.id == id);
    await _save();
  }

  Future<String> contextFor(String query) async {
    final entries = (await list()).where((entry) => entry.enabled).toList();
    entries.sort((a, b) {
      final scoreA = TextRelevance.score(query, '${a.category} ${a.content}');
      final scoreB = TextRelevance.score(query, '${b.category} ${b.content}');
      final scoreComparison = scoreB.compareTo(scoreA);
      return scoreComparison != 0
          ? scoreComparison
          : b.updatedAt.compareTo(a.updatedAt);
    });
    final selected = entries
        .where(
          (entry) =>
              TextRelevance.score(query, entry.content) > 0 ||
              entry.category == 'user',
        )
        .take(8);
    final buffer = StringBuffer();
    for (final entry in selected) {
      final line = '- [${entry.category}] ${entry.content}\n';
      if (buffer.length + line.length > maxInjectedCharacters) break;
      buffer.write(line);
    }
    return buffer.toString().trim();
  }

  Future<void> recordWorkflowLesson(String goal, List<ActionStep> steps) async {
    if (steps.isEmpty ||
        validateContent(goal) != null ||
        steps.any((step) => step.action == 'type_text')) {
      return;
    }
    final actions = steps.map((step) => step.action).toSet().join(' → ');
    final compactGoal = goal.length > 300 ? goal.substring(0, 300) : goal;
    await upsert(
      content: 'Completed Android task "$compactGoal" using: $actions.',
      category: 'workflow',
      source: 'automatic',
    );
  }

  Future<void> _trimAndSave() async {
    _cache!.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    while (_cache!.fold<int>(0, (sum, item) => sum + item.content.length) >
            maxStoredCharacters &&
        _cache!.isNotEmpty) {
      final removable = _cache!.lastIndexWhere(
        (entry) => entry.source == 'automatic',
      );
      _cache!.removeAt(removable >= 0 ? removable : _cache!.length - 1);
    }
    await _save();
  }

  Future<void> _save() async {
    final file = await _file;
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode(_cache!.map((e) => e.toJson()).toList()),
    );
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}
