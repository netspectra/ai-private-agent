import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/user_skill.dart';
import 'agent_memory_service.dart';
import 'text_relevance.dart';

class UserSkillService {
  UserSkillService._();
  static final UserSkillService instance = UserSkillService._();
  List<UserSkill>? _cache;

  Future<File> get _file async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/user_skills.json');
  }

  Future<List<UserSkill>> list() async {
    if (_cache != null) return List.unmodifiable(_cache!);
    try {
      final file = await _file;
      if (!await file.exists()) return _cache = [];
      final decoded = jsonDecode(await file.readAsString());
      _cache = (decoded as List)
          .map((item) => UserSkill.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _cache = [];
    }
    return List.unmodifiable(_cache!);
  }

  Future<void> upsert({
    String? id,
    required String name,
    required String description,
    required List<String> triggers,
    required String instructions,
  }) async {
    if (name.trim().isEmpty || instructions.trim().isEmpty) {
      throw ArgumentError('Skill name and instructions are required.');
    }
    final error = AgentMemoryService.validateContent(instructions);
    if (error != null) throw ArgumentError(error);
    await list();
    final now = DateTime.now();
    final index = id == null
        ? -1
        : _cache!.indexWhere((skill) => skill.id == id);
    if (index >= 0) {
      _cache![index] = _cache![index].copyWith(
        name: name.trim(),
        description: description.trim(),
        triggers: triggers
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
        instructions: instructions.trim(),
        updatedAt: now,
      );
    } else {
      _cache!.add(
        UserSkill(
          id: now.microsecondsSinceEpoch.toString(),
          name: name.trim(),
          description: description.trim(),
          triggers: triggers
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toList(),
          instructions: instructions.trim(),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await _save();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await list();
    final index = _cache!.indexWhere((skill) => skill.id == id);
    if (index < 0) return;
    _cache![index] = _cache![index].copyWith(
      enabled: enabled,
      updatedAt: DateTime.now(),
    );
    await _save();
  }

  Future<void> delete(String id) async {
    await list();
    _cache!.removeWhere((skill) => skill.id == id);
    await _save();
  }

  Future<String> contextFor(String query) async {
    final skills = (await list()).where((skill) => skill.enabled).toList();
    final lower = query.trimLeft().toLowerCase();
    final matches = skills
        .where((skill) {
          if (lower.startsWith('/${skill.commandName}')) return true;
          final searchable =
              '${skill.name} ${skill.description} ${skill.triggers.join(' ')}';
          return TextRelevance.score(query, searchable) >= 0.34;
        })
        .take(3)
        .toList();
    if (matches.isEmpty) return '';
    return matches
        .map(
          (skill) =>
              '### ${skill.name}\n${skill.description}\nProcedure:\n${skill.instructions}',
        )
        .join('\n\n');
  }

  Future<String> catalog() async {
    final skills = (await list()).where((skill) => skill.enabled).take(30);
    return skills
        .map((skill) => '/${skill.commandName}: ${skill.description}')
        .join('\n');
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
