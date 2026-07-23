import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/ai_service.dart';
import '../config/local_models_config.dart';

class LocalModelsScreen extends StatefulWidget {
  final AiService aiService;
  final VoidCallback onModelChanged;

  const LocalModelsScreen({
    super.key,
    required this.aiService,
    required this.onModelChanged,
  });

  @override
  State<LocalModelsScreen> createState() => _LocalModelsScreenState();
}

class _LocalModelsScreenState extends State<LocalModelsScreen> {
  int _deviceRamGB = 0;

  @override
  void initState() {
    super.initState();
    _deviceRamGB = _getDeviceRamGB();
  }

  int _getDeviceRamGB() {
    try {
      final lines = File('/proc/meminfo').readAsLinesSync();
      for (final line in lines) {
        if (line.startsWith('MemTotal:')) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final kb = int.tryParse(parts[1]) ?? 0;
            // Round up to nearest GB (e.g. 7.5GB -> 8GB)
            return (kb / (1024 * 1024)).ceil();
          }
        }
      }
    } catch (_) {}
    return 4; // Default fallback
  }

  bool _isRecommended(String recommendedStr) {
    if (recommendedStr == 'Unknown' || recommendedStr.isEmpty) return false;
    final match = RegExp(r'(\d+)GB').firstMatch(recommendedStr);
    if (match != null && match.groupCount >= 1) {
      final req = int.tryParse(match.group(1)!) ?? 0;
      return _deviceRamGB >= req;
    }
    return false;
  }

  List<LocalModelSuggestion> _getAllModels() {
    final List<LocalModelSuggestion> list = List.from(LocalModelsConfig.suggestions);
    for (var path in widget.aiService.importedModels) {
      final name = path.split('/').last.replaceAll('.gguf', '').replaceAll('_', ' ');
      list.add(LocalModelSuggestion(
        name: name,
        recommendedRam: 'Unknown',
        description: 'Custom imported model',
        url: path,
        size: '', // We will calculate this in the UI
      ));
    }
    return list;
  }

  bool _isFilePickerActive = false;

  Future<bool> _isModelDownloaded(String filename) async {
    // Check imported models
    if (widget.aiService.importedModels.any((p) => p.endsWith(filename))) return true;
    
    // Check custom download dir
    final customDir = widget.aiService.defaultModelDownloadDir;
    if (customDir != null) {
      if (await File('$customDir/$filename').exists()) return true;
    }
    
    return await widget.aiService.modelManager.isModelDownloaded(filename);
  }
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Models Manager'),
        actions: [
          if (widget.aiService.defaultModelDownloadDir != null)
            IconButton(
              icon: const Icon(Icons.folder_off_outlined),
              tooltip: 'Clear Saved Download Folder',
              onPressed: () async {
                await widget.aiService.saveDefaultModelDownloadDir(null);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Saved download folder cleared. You will be asked next time.')),
                  );
                  setState(() {});
                }
              },
            ),
          TextButton.icon(
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Import'),
            onPressed: () async {
              final path = await widget.aiService.modelManager.pickAndImportModel();
              if (path != null) {
                await widget.aiService.addImportedModel(path);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Model imported successfully!')),
                  );
                  setState(() {});
                }
              }
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.aiService.modelManager,
        builder: (context, child) {
          final manager = widget.aiService.modelManager;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
          Card(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            elevation: 0,
            child: const Padding(
              padding: EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(Icons.info_outline),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Download a model directly to your device and run it completely offline. Warning: Requires significant storage and RAM.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (manager.isImporting)
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.5), width: 1),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Importing: ${manager.importFileName.isNotEmpty ? manager.importFileName : "Model"}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      manager.importStatus,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: manager.importProgressPercentage > 0 ? manager.importProgressPercentage : null,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          manager.downloadingModelsSize['import_size'] ?? '',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          manager.importSpeed,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ..._getAllModels().map((model) {
            return FutureBuilder<bool>(
              future: () async {
                final filename = model.name.replaceAll(' ', '_') + '.gguf';
                if (widget.aiService.importedModels.any((p) => p.endsWith(filename))) return true;
                final customDir = widget.aiService.defaultModelDownloadDir;
                if (customDir != null) {
                  if (await File('$customDir/$filename').exists()) return true;
                }
                return await widget.aiService.modelManager.isModelDownloaded(filename);
              }(),
              builder: (context, snapshot) {
                bool isDownloaded = snapshot.data ?? false;
                bool isDownloading = manager.downloadingModels.containsKey(model.name);
                bool isSelected = widget.aiService.useOnDeviceInference && 
                                  widget.aiService.onDeviceModelFilename == model.name.replaceAll(' ', '_') + '.gguf';

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: isSelected ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2) : BorderSide.none,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                model.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (model.size.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  model.size,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            else
                              FutureBuilder<String>(
                                future: widget.aiService.modelManager.fetchModelSize(model.url),
                                builder: (context, snapshot) {
                                  final sizeStr = snapshot.data ?? '...';
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      sizeStr,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                        if (_isRecommended(model.recommendedRam)) ...[
                          const SizedBox(height: 4),
                          Text(
                            '✓ Recommended for your device (${model.recommendedRam})',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        Text(
                          model.description,
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        if (isDownloading)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LinearProgressIndicator(
                                value: (manager.downloadProgress[model.name] != null && manager.downloadProgress[model.name]! >= 0) 
                                    ? manager.downloadProgress[model.name] 
                                    : null,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text((manager.downloadingModelsSize[model.name + '_size']) ?? 'Downloading...'),
                                  Text(manager.downloadSpeed[model.name] ?? ''),
                                ],
                              ),
                              TextButton(
                                onPressed: () {
                                  widget.aiService.modelManager.cancelDownload();
                                },
                                child: const Text('Cancel'),
                              ),
                            ],
                          )
                        else if (isDownloaded)
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () async {
                                    final filename = model.name.replaceAll(' ', '_') + '.gguf';
                                    if (isSelected) {
                                      await widget.aiService.saveOnDeviceSettings(false, null);
                                    } else {
                                      // Pre-Flight Check
                                      final loadAction = await _confirmModelLoadSafety(
                                        context,
                                        filename,
                                        model,
                                      );
                                      if (loadAction == _ModelLoadAction.cancel) return;
                                      if (loadAction == _ModelLoadAction.unload) {
                                        await widget.aiService.saveOnDeviceSettings(false, null);
                                        widget.onModelChanged();
                                        setState(() {});
                                        return;
                                      }
                                      
                                      // Show loading dialog
                                      showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (context) => const AlertDialog(
                                          content: Row(
                                            children: [
                                              CircularProgressIndicator(),
                                              SizedBox(width: 24),
                                              Text('Loading model natively...'),
                                            ],
                                          ),
                                        ),
                                      );

                                      try {
                                        await widget.aiService.saveOnDeviceSettings(true, filename);
                                        if (mounted) Navigator.pop(context); // Close dialog
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Model loaded successfully!')),
                                          );
                                        }
                                      } catch (e) {
                                        if (mounted) Navigator.pop(context); // Close dialog
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(e.toString()),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                        await widget.aiService.saveOnDeviceSettings(false, null);
                                      }
                                    }
                                    widget.onModelChanged();
                                    setState(() {});
                                  },
                                  icon: Icon(isSelected ? Icons.check_circle : Icons.play_arrow),
                                  label: Text(isSelected ? 'Active (Tap to Disable)' : 'Load Model'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: isSelected ? Colors.green : Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                onPressed: () async {
                                  final filename = model.name.replaceAll(' ', '_') + '.gguf';
                                  
                                  // Check if it's an imported model
                                  final importedPath = widget.aiService.importedModels.where((p) => p.endsWith(filename)).firstOrNull;
                                  if (importedPath != null) {
                                    await widget.aiService.removeImportedModel(importedPath);
                                  } else {
                                    await widget.aiService.modelManager.deleteModel(filename);
                                    if (widget.aiService.defaultModelDownloadDir != null) {
                                      final customFile = File('${widget.aiService.defaultModelDownloadDir}/$filename');
                                      if (await customFile.exists()) await customFile.delete();
                                    }
                                  }
                                  
                                  if (isSelected) {
                                    await widget.aiService.saveOnDeviceSettings(false, null);
                                    widget.onModelChanged();
                                  }
                                  setState(() {});
                                },
                              ),
                            ],
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final filename = model.name.replaceAll(' ', '_') + '.gguf';
                                
                                String? selectedDir = widget.aiService.defaultModelDownloadDir;
                                
                                if (selectedDir == null) {
                                  bool? useInternal = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Download Location'),
                                      content: const Text('Where would you like to save this model?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, true),
                                          child: const Text('App Internal Storage'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(context, false),
                                          child: const Text('Custom Folder'),
                                        ),
                                      ],
                                    ),
                                  );
                                  
                                  if (useInternal == null) return;
                                  
                                  if (!useInternal) {
                                    if (_isFilePickerActive) return;
                                    try {
                                      _isFilePickerActive = true;
                                      selectedDir = await FilePicker.getDirectoryPath(
                                        dialogTitle: 'Select Model Download Folder',
                                      );
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Failed to pick folder. Please try again.')),
                                        );
                                      }
                                      return;
                                    } finally {
                                      _isFilePickerActive = false;
                                    }
                                    if (selectedDir == null) return; // User cancelled
                                  } else {
                                    selectedDir = 'internal'; // Marker for internal storage
                                  }
                                  
                                  await widget.aiService.saveDefaultModelDownloadDir(selectedDir);
                                }
                                
                                String? actualDir = selectedDir == 'internal' ? null : selectedDir;
                                
                                await widget.aiService.modelManager.downloadModel(
                                  url: model.url,
                                  modelName: model.name,
                                  filename: filename,
                                  customDir: actualDir,
                                  onComplete: () {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('${model.name} downloaded successfully!')),
                                      );
                                    }
                                  },
                                  onError: (error) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Download failed: $error')),
                                      );
                                    }
                                  },
                                );
                              },
                              icon: const Icon(Icons.download_rounded, size: 16),
                              label: const Text('Download Model'),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }
            );
          }),
        ],
      );
      }),
    );
  }

  Future<double> _getAvailableRamGB() async {
    if (Platform.isAndroid) {
      try {
        final file = File('/proc/meminfo');
        final lines = await file.readAsLines();
        for (final line in lines) {
          if (line.startsWith('MemAvailable:')) {
            final match = RegExp(r'\d+').firstMatch(line);
            if (match != null) {
              final kb = int.parse(match.group(0)!);
              return kb / (1024 * 1024); // KB to GB
            }
          }
        }
      } catch (_) {}
    }
    return 0.0;
  }

  Future<_ModelLoadAction> _confirmModelLoadSafety(
    BuildContext context,
    String filename,
    LocalModelSuggestion model,
  ) async {
    final availableRamGb = await _getAvailableRamGB();
    final availableBytes = (availableRamGb * 1024 * 1024 * 1024).round();
    
    // Attempt to get file size from storage
    int fileBytes = 0;
    try {
      final path = await widget.aiService.modelManager.getModelPath(filename);
      if (path != null) {
         final f = File(path);
         if (await f.exists()) fileBytes = await f.length();
      }
    } catch (_) {}

    final modelLabel = fileBytes > 0 
        ? '${(fileBytes / (1024 * 1024)).toStringAsFixed(1)} MB' 
        : 'Unknown size';
    final ramLabel = availableBytes > 0 
        ? '${(availableBytes / (1024 * 1024)).toStringAsFixed(1)} MB' 
        : 'Unknown';

    final hasMeasuredMemory = availableBytes > 0 && fileBytes > 0;
    final isCriticallyLow = hasMeasuredMemory && availableBytes < fileBytes;
    final isLargeForRam = hasMeasuredMemory && availableBytes < fileBytes * 2;
    
    final String warning;
    if (isCriticallyLow) {
      warning = 'Available RAM is lower than recommended. This can crash the app if Android cannot reserve enough memory.';
    } else if (isLargeForRam) {
      warning = 'This can crash the app if Android cannot reserve enough memory for the model.';
    } else {
      warning = 'Loading local models can use more memory than the file size.';
    }

    final lower = filename.toLowerCase();
    final runtimeLabel = lower.endsWith('.gguf') 
        ? 'GGUF' 
        : lower.endsWith('.litertlm') 
            ? 'LiteRT-LM' 
            : 'Local model';

    final loadedName = widget.aiService.onDeviceModelFilename ?? '';
    final hasLoadedModel = widget.aiService.useOnDeviceInference && loadedName.isNotEmpty;
    final isSameModelLoaded = hasLoadedModel && loadedName == filename;

    final result = await showDialog<_ModelLoadAction>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(isCriticallyLow ? 'Restart recommended' : 'Load model?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(filename, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('Runtime: $runtimeLabel'),
            Text('Available RAM: $ramLabel'),
            Text('Model size: $modelLabel'),
            if (hasLoadedModel) ...[
              const SizedBox(height: 12),
              Text(
                isSameModelLoaded
                    ? 'This model is already loaded.'
                    : 'Already loaded: $loadedName',
              ),
              if (!isSameModelLoaded)
                const Text('Unload it before loading another model.'),
            ],
            const SizedBox(height: 12),
            Text(warning, style: TextStyle(color: isCriticallyLow ? Colors.red : null)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _ModelLoadAction.cancel),
            child: const Text('Cancel'),
          ),
          if (hasLoadedModel)
            TextButton(
              onPressed: () => Navigator.pop(context, _ModelLoadAction.unload),
              child: const Text('Unload'),
            ),
          if (isCriticallyLow)
            TextButton(
              onPressed: () async {
                Navigator.pop(context, _ModelLoadAction.cancel);
                await widget.aiService.modelManager.restartApp();
              },
              child: const Text('Restart app'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _ModelLoadAction.continueLoad),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result ?? _ModelLoadAction.cancel;
  }
}

enum _ModelLoadAction { cancel, unload, continueLoad }
