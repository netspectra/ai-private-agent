import 'package:flutter/material.dart';

Future<String?> showSearchableModelPicker({
  required BuildContext context,
  required List<String> models,
  required String title,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _SearchableModelPicker(models: models, title: title),
  );
}

class _SearchableModelPicker extends StatefulWidget {
  final List<String> models;
  final String title;

  const _SearchableModelPicker({required this.models, required this.title});

  @override
  State<_SearchableModelPicker> createState() => _SearchableModelPickerState();
}

class _SearchableModelPickerState extends State<_SearchableModelPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.models
        .where((model) => model.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Filter models',
                  hintText: 'Type part of a model name',
                  prefixIcon: Icon(Icons.search_rounded),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
              const SizedBox(height: 8),
              Text('${filtered.length} of ${widget.models.length} models'),
              const SizedBox(height: 8),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No matching models'))
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) => ListTile(
                          title: Text(filtered[index]),
                          onTap: () => Navigator.pop(context, filtered[index]),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
