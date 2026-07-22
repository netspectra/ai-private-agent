import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/saved_skill.dart';

class SkillMemoryService {
  SkillMemoryService._();
  factory SkillMemoryService() => instance;
  static final SkillMemoryService instance = SkillMemoryService._();

  List<SavedSkill> _skills = [];
  bool _isLoaded = false;

  Future<File> get _localFile async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/skills_memory.jsonl');
  }

  Future<void> _loadSkills() async {
    if (_isLoaded) return;
    try {
      final file = await _localFile;
      if (!await file.exists()) {
        _isLoaded = true;
        return;
      }
      final lines = await file.readAsLines();
      _skills = lines
          .where((line) => line.trim().isNotEmpty)
          .map(
            (line) =>
                SavedSkill.fromJson(jsonDecode(line) as Map<String, dynamic>),
          )
          .toList();
      _isLoaded = true;
    } catch (e) {
      print('Failed to load skills: $e');
    }
  }

  Future<void> _saveAllSkills() async {
    try {
      final file = await _localFile;
      final lines = _skills.map((s) => jsonEncode(s.toJson())).join('\n');
      await file.writeAsString(lines + (lines.isNotEmpty ? '\n' : ''));
    } catch (e) {
      print('Failed to save skills: $e');
    }
  }

  List<String> _extractKeywords(String text) {
    final stopWords = {
      'to',
      'and',
      'the',
      'a',
      'in',
      'of',
      'for',
      'on',
      'with',
      'at',
      'by',
      'from',
      'go',
      'turn',
      'open',
      'как',
      'что',
      'это',
      'для',
      'или',
      'мне',
      'надо',
      'нужно',
      'открой',
    };
    final words = RegExp(
      r'[a-z0-9а-яё]{2,}',
      caseSensitive: false,
      unicode: true,
    ).allMatches(text.toLowerCase()).map((match) => match.group(0)!).toList();
    return words.where((w) => w.isNotEmpty && !stopWords.contains(w)).toList();
  }

  double _jaccardSimilarity(List<String> a, List<String> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    final setA = a.toSet();
    final setB = b.toSet();
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    return intersection / union;
  }

  Future<SavedSkill?> findSkill(String taskGoal) async {
    await _loadSkills();
    if (_skills.isEmpty) return null;

    final safeTaskGoal = _redactTaskGoal(taskGoal);
    final queryKeywords = _extractKeywords(safeTaskGoal);
    SavedSkill? bestMatch;
    double highestSim = 0.0;

    for (final skill in _skills.where(
      (item) => item.enabled && item.autoReplay,
    )) {
      final sim = _jaccardSimilarity(queryKeywords, skill.taskKeywords);
      if (sim > highestSim) {
        highestSim = sim;
        bestMatch = skill;
      }
    }

    if (highestSim > 0.6) {
      return bestMatch;
    }
    return null;
  }

  Future<void> saveSkill(String taskGoal, List<ActionStep> steps) async {
    await _loadSkills();

    final safeTaskGoal = _redactTaskGoal(taskGoal);
    final safeSteps = steps.map(_sanitizeStep).toList();
    final queryKeywords = _extractKeywords(safeTaskGoal);
    for (final skill in _skills) {
      if (_jaccardSimilarity(queryKeywords, skill.taskKeywords) > 0.8) {
        skill.successCount++;
        skill.lastUsed = DateTime.now();
        if (safeSteps.length < skill.steps.length) {
          skill.steps.clear();
          skill.steps.addAll(safeSteps);
        }
        await _saveAllSkills();
        return;
      }
    }

    final newSkill = SavedSkill(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      task: safeTaskGoal,
      taskKeywords: queryKeywords,
      successCount: 1,
      failCount: 0,
      lastUsed: DateTime.now(),
      steps: safeSteps,
    );
    _skills.add(newSkill);
    await _saveAllSkills();
  }

  Future<void> recordFailure(String skillId) async {
    await _loadSkills();
    final index = _skills.indexWhere((s) => s.id == skillId);
    if (index != -1) {
      _skills[index].failCount++;
      await _saveAllSkills();
    }
  }

  Future<List<SavedSkill>> listSkills() async {
    await _loadSkills();
    return List.unmodifiable(_skills);
  }

  Future<void> setEnabled(String skillId, bool enabled) async {
    await _loadSkills();
    final skill = _skills.where((item) => item.id == skillId).firstOrNull;
    if (skill == null) return;
    skill.enabled = enabled;
    await _saveAllSkills();
  }

  Future<void> setAutoReplay(String skillId, bool autoReplay) async {
    await _loadSkills();
    final skill = _skills.where((item) => item.id == skillId).firstOrNull;
    if (skill == null) return;
    skill.autoReplay = autoReplay && skill.canAutoReplay;
    await _saveAllSkills();
  }

  Future<void> deleteSkill(String skillId) async {
    await _loadSkills();
    _skills.removeWhere((item) => item.id == skillId);
    await _saveAllSkills();
  }

  String _redactTaskGoal(String value) {
    return value
        .replaceAll(
          RegExp(r'[\w.+-]+@[\w.-]+\.[a-z]{2,}', caseSensitive: false),
          '[email]',
        )
        .replaceAll(RegExp(r'\+?\d[\d ()-]{7,}\d'), '[number]')
        .replaceAll(
          RegExp(
            r'(api[_ -]?key|password|token)\s*[:=]\s*\S+',
            caseSensitive: false,
          ),
          r'$1=[redacted]',
        );
  }

  ActionStep _sanitizeStep(ActionStep step) {
    if (step.action != 'type_text') return step;
    return ActionStep(
      action: step.action,
      params: {
        if (step.params['field_hint'] != null)
          'field_hint': step.params['field_hint'],
        'redacted': true,
      },
    );
  }
}
