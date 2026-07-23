import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class ModelManagerService extends ChangeNotifier {
  final Dio _dio = Dio();
  CancelToken? _cancelToken;

  // State variables for UI
  final Map<String, bool> downloadingModels = {};
  final Map<String, double> downloadProgress = {};
  final Map<String, String> downloadSpeed = {};
  final Map<String, String> downloadingModelsSize = {};

  // Import State variables
  bool isImporting = false;
  String importFileName = '';
  String importStatus = '';
  double importProgressPercentage = 0.0;
  String importSpeed = '';
  
  static const MethodChannel _importChannel = MethodChannel('com.write4me.private_agent/model_import');

  ModelManagerService() {
    _importChannel.setMethodCallHandler(_handleImportCall);
  }

  Future<dynamic> _handleImportCall(MethodCall call) async {
    if (call.method == 'importProgress') {
      final args = call.arguments as Map;
      final filename = args['filename'] as String;
      final copiedBytes = (args['copiedBytes'] as num).toInt();
      final totalBytes = (args['totalBytes'] as num).toInt();
      final bytesPerSecond = (args['bytesPerSecond'] as num).toDouble();
      final status = args['status'] as String;

      isImporting = true;
      importFileName = filename;
      importStatus = status;
      importProgressPercentage = totalBytes > 0 ? copiedBytes / totalBytes : 0.0;

      final speedMBps = bytesPerSecond / (1024 * 1024);
      importSpeed = '${speedMBps.toStringAsFixed(1)} MB/s';

      final recMB = copiedBytes / (1024 * 1024);
      final totMB = totalBytes / (1024 * 1024);
      final recStr = recMB >= 1024 ? '${(recMB/1024).toStringAsFixed(2)} GB' : '${recMB.toStringAsFixed(1)} MB';
      final totStr = totMB >= 1024 ? '${(totMB/1024).toStringAsFixed(2)} GB' : '${totMB.toStringAsFixed(1)} MB';
      downloadingModelsSize['import_size'] = '$recStr / $totStr';

      if (status == 'Import complete' || status.startsWith('Import failed')) {
        isImporting = false;
      }
      notifyListeners();
    }
  }

  Future<void> restartApp() async {
    try {
      await _importChannel.invokeMethod('restartApp');
    } catch (_) {
      exit(0);
    }
  }

  Future<String?> pickAndImportModel() async {
    try {
      isImporting = true;
      importFileName = '';
      importStatus = 'Select a model file...';
      importProgressPercentage = 0.0;
      notifyListeners();

      final dir = await getModelDirectory();
      final result = await _importChannel.invokeMapMethod<String, dynamic>(
        'pickAndImportModel',
        {'modelsDir': dir.path},
      );

      isImporting = false;
      notifyListeners();

      if (result?['cancelled'] == true) return null;

      final filename = result?['filename'] as String?;
      if (filename != null && filename.isNotEmpty) {
        return '${dir.path}/$filename';
      }
      return null;
    } catch (e) {
      isImporting = false;
      importStatus = 'Error: $e';
      notifyListeners();
      return null;
    }
  }

  /// Get the directory where models are stored.
  Future<Directory> getModelDirectory() async {
    final docDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${docDir.path}/models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return modelDir;
  }

  /// Check if a model file exists locally.
  Future<bool> isModelDownloaded(String filename) async {
    final dir = await getModelDirectory();
    final file = File('${dir.path}/$filename');
    return await file.exists();
  }

  /// Get the absolute path of a downloaded model.
  Future<String?> getModelPath(String filename) async {
    final dir = await getModelDirectory();
    final file = File('${dir.path}/$filename');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  /// List all locally downloaded models
  Future<List<String>> listDownloadedModels() async {
    final dir = await getModelDirectory();
    if (!await dir.exists()) return [];
    
    final List<String> models = [];
    final entities = dir.listSync();
    for (var entity in entities) {
      if (entity is File && entity.path.endsWith('.gguf')) {
        models.add(entity.uri.pathSegments.last);
      }
    }
    return models;
  }

  /// Download a model with progress tracking.
  Future<void> downloadModel({
    required String url,
    required String modelName,
    required String filename,
    String? customDir,
    required Function() onComplete,
    required Function(String error) onError,
  }) async {
    downloadingModels[modelName] = true;
    downloadProgress[modelName] = 0.0;
    notifyListeners();
    try {
      final dir = customDir != null ? Directory(customDir) : await getModelDirectory();
      final savePath = '${dir.path}/$filename';
      final file = File(savePath);
      
      int downloadedBytes = 0;
      if (await file.exists()) {
        downloadedBytes = await file.length();
      }
      
      _cancelToken = CancelToken();
      int lastTimestamp = DateTime.now().millisecondsSinceEpoch;
      int lastRecv = downloadedBytes;

      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Range': 'bytes=$downloadedBytes-'},
          validateStatus: (status) => status != null && status <= 416,
        ),
        cancelToken: _cancelToken,
      );

      if (response.statusCode == 416) {
        // 416 Range Not Satisfiable means the file is already fully downloaded
        downloadingModels.remove(modelName);
        notifyListeners();
        onComplete();
        return;
      }
      
      if (response.statusCode == 200 && downloadedBytes > 0) {
        downloadedBytes = 0; 
        await file.writeAsBytes([]); 
      }

      final raf = await file.open(mode: FileMode.append);
      
      int total = -1;
      if (response.statusCode == 206) {
        final contentRange = response.headers.value('content-range');
        if (contentRange != null && contentRange.contains('/')) {
          total = int.tryParse(contentRange.split('/').last) ?? -1;
        }
      }
      
      if (total == -1) {
        total = int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '-1') ?? -1;
        if (total != -1 && response.statusCode == 206) {
          total += downloadedBytes; // Content-Length on 206 is the remaining size
        }
      }
      
      if (total != -1) {
        downloadProgress[modelName] = downloadedBytes / total;
        final recMB = downloadedBytes / (1024 * 1024);
        final totMB = total / (1024 * 1024);
        
        String recStr = recMB >= 1024 ? '${(recMB/1024).toStringAsFixed(2)} GB' : '${recMB.toStringAsFixed(1)} MB';
        String totStr = totMB >= 1024 ? '${(totMB/1024).toStringAsFixed(2)} GB' : '${totMB.toStringAsFixed(1)} MB';
        downloadingModelsSize[modelName + '_size'] = '$recStr / $totStr';
        downloadSpeed[modelName] = '';
      } else {
        downloadProgress[modelName] = -1.0;
        final recMB = downloadedBytes / (1024 * 1024);
        downloadingModelsSize[modelName + '_size'] = '${recMB.toStringAsFixed(1)} MB downloaded';
        downloadSpeed[modelName] = 'calculating...';
      }
      notifyListeners();

      if (response.data == null) throw Exception('Download response data is null');

      await for (final chunk in response.data!.stream) {
        if (_cancelToken!.isCancelled) break;
        await raf.writeFrom(chunk);
        downloadedBytes += chunk.length as int;
        
        int currentTimestamp = DateTime.now().millisecondsSinceEpoch;
        int timeDiff = currentTimestamp - lastTimestamp;
        if (timeDiff > 1000) {
          double speedMBps = ((downloadedBytes - lastRecv) / (1024 * 1024)) / (timeDiff / 1000);
          String speedStr = '${speedMBps.toStringAsFixed(1)} MB/s';
          
          if (total != -1) {
            downloadProgress[modelName] = downloadedBytes / total;
            final recMB = downloadedBytes / (1024 * 1024);
            final totMB = total / (1024 * 1024);
            
            String recStr = recMB >= 1024 ? '${(recMB/1024).toStringAsFixed(2)} GB' : '${recMB.toStringAsFixed(1)} MB';
            String totStr = totMB >= 1024 ? '${(totMB/1024).toStringAsFixed(2)} GB' : '${totMB.toStringAsFixed(1)} MB';
            downloadingModelsSize[modelName + '_size'] = '$recStr / $totStr';
            downloadSpeed[modelName] = speedStr;
          } else {
            downloadProgress[modelName] = -1.0;
            final recMB = downloadedBytes / (1024 * 1024);
            downloadingModelsSize[modelName + '_size'] = '${recMB.toStringAsFixed(1)} MB downloaded';
            downloadSpeed[modelName] = speedStr;
          }
          notifyListeners();
          
          lastTimestamp = currentTimestamp;
          lastRecv = downloadedBytes;
        }
      }
      await raf.close();
      
      if (!_cancelToken!.isCancelled) {
        downloadingModels.remove(modelName);
        notifyListeners();
        onComplete();
      }
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 416) {
        // 416 Range Not Satisfiable means the file is already fully downloaded
        downloadingModels.remove(modelName);
        notifyListeners();
        onComplete();
        return;
      }
      
      downloadingModels.remove(modelName);
      notifyListeners();
      if (e is DioException && CancelToken.isCancel(e)) {
        onError("Download cancelled");
      } else {
        onError(e.toString());
      }
    }
  }

  /// Fetch the remote size or local file size of the model.
  Future<String> fetchModelSize(String url) async {
    try {
      if (url.startsWith('http://') || url.startsWith('https://')) {
        var response = await _dio.head(url);
        var size = response.headers.value('content-length');

        if (size == null) {
          // Fallback to GET with Range if HEAD doesn't provide content-length (common for HF)
          response = await _dio.get(
            url,
            options: Options(
              headers: {'Range': 'bytes=0-0'},
            ),
          );
          if (response.statusCode == 206) {
            final contentRange = response.headers.value('content-range');
            if (contentRange != null && contentRange.contains('/')) {
              size = contentRange.split('/').last;
            }
          }
        }

        if (size == null) {
          size = response.headers.value('content-length');
        }

        if (size != null) {
          final bytes = int.tryParse(size) ?? 0;
          return _formatBytes(bytes);
        }
      } else {
        // Assume local file path
        final file = File(url);
        if (file.existsSync()) {
          return _formatBytes(file.lengthSync());
        }
      }
    } catch (e) {
      // Ignored
    }
    return 'Unknown Size';
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    final gb = bytes / (1024 * 1024 * 1024);
    if (gb >= 1.0) {
      return '${gb.toStringAsFixed(1)} GB';
    }
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// Cancel an ongoing download.
  void cancelDownload() {
    _cancelToken?.cancel("User cancelled download");
  }

  /// Delete a downloaded model.
  Future<void> deleteModel(String filename) async {
    final dir = await getModelDirectory();
    final file = File('${dir.path}/$filename');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
