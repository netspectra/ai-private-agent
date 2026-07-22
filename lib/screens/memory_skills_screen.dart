import 'package:flutter/material.dart';
import '../models/agent_memory_entry.dart';
import '../models/saved_skill.dart';
import '../models/user_skill.dart';
import '../services/agent_memory_service.dart';
import '../services/skill_memory_service.dart';
import '../services/user_skill_service.dart';

class MemorySkillsScreen extends StatefulWidget {
  const MemorySkillsScreen({super.key});

  @override
  State<MemorySkillsScreen> createState() => _MemorySkillsScreenState();
}

class _MemorySkillsScreenState extends State<MemorySkillsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory & Skills'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Memory'),
            Tab(text: 'Skills'),
            Tab(text: 'Learned'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_memoryTab(), _skillsTab(), _learnedTab()],
      ),
    );
  }

  Widget _memoryTab() => FutureBuilder<List<AgentMemoryEntry>>(
    future: AgentMemoryService.instance.list(),
    builder: (context, snapshot) {
      final entries = snapshot.data ?? const [];
      return _managedList(
        intro:
            'Durable facts and preferences are recalled in future sessions. '
            'Secrets are rejected and only relevant entries are sent to the model.',
        onAdd: () => _editMemory(),
        emptyText: 'No long-term memories yet.',
        children: entries
            .map(
              (entry) => Card(
                child: ListTile(
                  title: Text(entry.content),
                  subtitle: Text('${entry.category} • ${entry.source}'),
                  leading: Switch(
                    value: entry.enabled,
                    onChanged: (value) async {
                      await AgentMemoryService.instance.setEnabled(
                        entry.id,
                        value,
                      );
                      _refresh();
                    },
                  ),
                  onTap: () => _editMemory(entry),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await AgentMemoryService.instance.delete(entry.id);
                      _refresh();
                    },
                  ),
                ),
              ),
            )
            .toList(),
      );
    },
  );

  Widget _skillsTab() => FutureBuilder<List<UserSkill>>(
    future: UserSkillService.instance.list(),
    builder: (context, snapshot) {
      final skills = snapshot.data ?? const [];
      return _managedList(
        intro:
            'Skills are reusable instructions loaded by trigger words or '
            'explicit /skill-name commands.',
        onAdd: () => _editSkill(),
        emptyText: 'No user skills yet.',
        children: skills
            .map(
              (skill) => Card(
                child: ListTile(
                  title: Text(skill.name),
                  subtitle: Text('/${skill.commandName}\n${skill.description}'),
                  isThreeLine: true,
                  leading: Switch(
                    value: skill.enabled,
                    onChanged: (value) async {
                      await UserSkillService.instance.setEnabled(
                        skill.id,
                        value,
                      );
                      _refresh();
                    },
                  ),
                  onTap: () => _editSkill(skill),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await UserSkillService.instance.delete(skill.id);
                      _refresh();
                    },
                  ),
                ),
              ),
            )
            .toList(),
      );
    },
  );

  Widget _learnedTab() => FutureBuilder<List<SavedSkill>>(
    future: SkillMemoryService.instance.listSkills(),
    builder: (context, snapshot) {
      final skills = snapshot.data ?? const [];
      return _managedList(
        intro:
            'Successful task traces are learned automatically. Auto replay is '
            'off by default; enable it only after reviewing the actions.',
        emptyText: 'No successful workflows learned yet.',
        children: skills
            .map(
              (skill) => Card(
                child: ExpansionTile(
                  title: Text(skill.task),
                  subtitle: Text(
                    '${skill.steps.length} actions • ${skill.successCount} successes',
                  ),
                  children: [
                    SwitchListTile(
                      title: const Text('Automatic replay'),
                      subtitle: const Text(
                        'May tap and type without asking again.',
                      ),
                      value: skill.autoReplay,
                      onChanged: skill.enabled && skill.canAutoReplay
                          ? (value) async {
                              await SkillMemoryService.instance.setAutoReplay(
                                skill.id,
                                value,
                              );
                              _refresh();
                            }
                          : null,
                    ),
                    if (!skill.canAutoReplay)
                      const ListTile(
                        leading: Icon(Icons.lock_outline),
                        title: Text('Replay locked'),
                        subtitle: Text(
                          'Typed text was redacted for privacy. The workflow remains available for review only.',
                        ),
                      ),
                    ...skill.steps.asMap().entries.map(
                      (item) => ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 12,
                          child: Text(
                            '${item.key + 1}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        title: Text(item.value.action),
                        subtitle: Text(item.value.params.toString()),
                      ),
                    ),
                    OverflowBar(
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                          onPressed: () async {
                            await SkillMemoryService.instance.deleteSkill(
                              skill.id,
                            );
                            _refresh();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      );
    },
  );

  Widget _managedList({
    required String intro,
    required String emptyText,
    required List<Widget> children,
    VoidCallback? onAdd,
  }) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(intro),
        if (onAdd != null) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ],
        const SizedBox(height: 12),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text(emptyText)),
          )
        else
          ...children,
      ],
    );
  }

  Future<void> _editMemory([AgentMemoryEntry? entry]) async {
    final content = TextEditingController(text: entry?.content ?? '');
    String category = entry?.category ?? 'general';
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          title: Text(entry == null ? 'Add memory' : 'Edit memory'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: category,
                items:
                    const ['general', 'user', 'system', 'project', 'workflow']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                onChanged: (value) =>
                    setDialogState(() => category = value ?? category),
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: content,
                minLines: 3,
                maxLines: 6,
                maxLength: 1200,
                decoration: const InputDecoration(
                  labelText: 'Durable fact or preference',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    try {
      await AgentMemoryService.instance.upsert(
        id: entry?.id,
        content: content.text,
        category: category,
      );
      _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _editSkill([UserSkill? skill]) async {
    final name = TextEditingController(text: skill?.name ?? '');
    final description = TextEditingController(text: skill?.description ?? '');
    final triggers = TextEditingController(
      text: skill?.triggers.join(', ') ?? '',
    );
    final instructions = TextEditingController(text: skill?.instructions ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(skill == null ? 'Create skill' : 'Edit skill'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              TextField(
                controller: triggers,
                decoration: const InputDecoration(
                  labelText: 'Triggers (comma separated)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: instructions,
                maxLines: 9,
                maxLength: 1200,
                decoration: const InputDecoration(
                  labelText: 'Procedure, pitfalls and verification',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await UserSkillService.instance.upsert(
        id: skill?.id,
        name: name.text,
        description: description.text,
        triggers: triggers.text.split(','),
        instructions: instructions.text,
      );
      _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}
