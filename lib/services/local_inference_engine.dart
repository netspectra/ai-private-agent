import 'dart:async';
import 'package:llama_flutter_android/llama_flutter_android.dart';

class LocalInferenceEngine {
  LlamaController? _controller;
  StreamSubscription? _subscription;
  Timer? _idleTimer;
  void Function()? _onStop;
  bool _disposed = false;
  bool _hasLoadedModel = false;

  bool get isInitialized => _hasLoadedModel && _controller != null;

  /// Load a model from the given path.
  Future<void> loadModel(String modelPath, {String deviceTier = 'mid', bool isTensorSoC = false}) async {
    _disposed = false;
    
    // Dispose previous if any
    await dispose();
    _disposed = false;

    _controller = LlamaController();

    // ── GPU Detection ──
    int gpuLayers = 0;
    String gpuNameStr = '';

    try {
      final gpu = await _controller!.detectGpu();
      gpuNameStr = gpu.gpuName;

      print('[Inference] GPU: ${gpu.gpuName}');
      print('[Inference]   Vulkan: ${gpu.vulkanSupported}');
      print('[Inference]   Free RAM: ${gpu.freeRamBytes ~/ 1024 ~/ 1024}MB');
      print('[Inference]   Recommended layers: ${gpu.recommendedGpuLayers}');

      if (gpu.vulkanSupported && gpu.recommendedGpuLayers > 0) {
        final gpuNum = _extractGpuModel(gpu.gpuName);
        if (gpuNum >= 700) {
          gpuLayers = 99;
          print('[Inference] ✓ High-end GPU ($gpuNum) → full offload');
        } else if (gpuNum >= 650) {
          gpuLayers = gpu.recommendedGpuLayers;
          print('[Inference] ✓ Upper-mid GPU ($gpuNum) → $gpuLayers layers');
        } else {
          gpuLayers = 0;
          print('[Inference] Mid-range GPU ($gpuNum) — CPU is faster, skipping GPU');
        }
      }
    } catch (e) {
      print('[Inference] GPU detection failed: $e — CPU fallback');
    }

    // ── Thread Tuning ──
    int threads;
    if (gpuLayers > 0) {
      threads = deviceTier == 'ultra' ? 4 : (deviceTier == 'high' ? 4 : 4);
    } else {
      threads = deviceTier == 'ultra' ? 6 : (deviceTier == 'high' ? 5 : (deviceTier == 'mid' ? 4 : 3));
    }

    // Google Tensor SoC (Pixel 6/7/8) has known Q4_K_M dequant bugs
    // that corrupt logits at >1 thread on Gemma models. Force single-threaded
    // to eliminate KV cache races in the quantization dot-product path.
    final modelName = modelPath.toLowerCase();
    if (isTensorSoC && modelName.contains('gemma')) {
      threads = 1;
      print('[Inference] Tensor SoC + Gemma detected — forcing single-threaded inference');
    }

    // ── Load ──
    try {
      await _controller!.loadModel(
        modelPath: modelPath,
        threads: threads,
        contextSize: 2048,
        gpuLayers: gpuLayers,
      );
      _hasLoadedModel = true;
      final accel = gpuLayers > 0 ? 'GPU ($gpuLayers layers, $gpuNameStr)' : 'CPU ($threads threads)';
      print('[Inference] ✓ Model loaded: $accel, ctx=2048');
    } catch (e) {
      _hasLoadedModel = false;
      throw Exception('Failed to load model: $e');
    }
  }

  /// Generate a response as a stream of strings using chat template.
  Stream<String> generateChatStream(List<ChatMessage> messages) async* {
    if (!_hasLoadedModel || _controller == null) {
      throw Exception('Inference engine not initialized. Call loadModel first.');
    }

    final completer = Completer<void>();
    StreamController<String> yieldController = StreamController<String>();
    bool completed = false;

    void finish() {
      if (!completed && !_disposed) {
        completed = true;
        _idleTimer?.cancel();
        _subscription?.cancel();
        _onStop = null;
        if (!completer.isCompleted) completer.complete();
        yieldController.close();
      }
    }

    _onStop = () => finish();

    _subscription = _controller!.generateChat(
      messages: messages,
      maxTokens: 1024,
      temperature: 0.7,
      topP: 0.9,
      topK: 40,
      minP: 0.05,
      repeatPenalty: 1.1,
      repeatLastN: 64,
    ).listen(
      (token) {
        final clean = _sanitizeGemmaGarbage(token);
        if (clean.isNotEmpty) {
          yieldController.add(clean);
        }
        _idleTimer?.cancel();
        _idleTimer = Timer(const Duration(seconds: 5), () => finish());
      },
      onDone: () => finish(),
      onError: (error) {
        if (!completer.isCompleted) completer.completeError(error);
        yieldController.addError(error);
        finish();
      },
    );

    _idleTimer = Timer(const Duration(seconds: 60), () {
      if (!completed) finish();
    });

    yield* yieldController.stream;
  }

  /// Generate a complete string response using chat template.
  Future<String> generateChat(List<ChatMessage> messages) async {
    if (!_hasLoadedModel || _controller == null) {
      throw Exception('Inference engine not initialized. Call loadModel first.');
    }
    
    final buffer = StringBuffer();
    final completer = Completer<String>();
    bool completed = false;

    void finish(String result) {
      if (!completed && !_disposed) {
        completed = true;
        _idleTimer?.cancel();
        _subscription?.cancel();
        _onStop = null;
        if (!completer.isCompleted) completer.complete(result);
      }
    }

    _onStop = () => finish(buffer.toString());
    
    _subscription = _controller!.generateChat(
      messages: messages,
      maxTokens: 1024,
      temperature: 0.7,
      topP: 0.9,
      topK: 40,
      minP: 0.05,
      repeatPenalty: 1.1,
      repeatLastN: 64,
    ).listen(
      (token) {
        final clean = _sanitizeGemmaGarbage(token);
        if (clean.isNotEmpty) buffer.write(clean);
        _idleTimer?.cancel();
        _idleTimer = Timer(const Duration(seconds: 5), () => finish(buffer.toString()));
      },
      onDone: () => finish(buffer.toString()),
      onError: (e) {
        finish(buffer.toString());
      },
    );

    _idleTimer = Timer(const Duration(seconds: 60), () {
      if (!completed) finish(buffer.toString());
    });
    
    return await completer.future;
  }

  /// Stop the current generation.
  Future<void> stop() async {
    if (_disposed) return;
    _idleTimer?.cancel();
    final stopCallback = _onStop;
    _onStop = null;
    stopCallback?.call();
    _subscription?.cancel();
    try {
      await _controller?.stop().timeout(const Duration(milliseconds: 800));
    } catch (_) {}
  }

  /// Dispose the engine and free memory.
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    if (_hasLoadedModel) {
      try {
        await _controller?.dispose();
      } catch (_) {}
    }
    _controller = null;
    _hasLoadedModel = false;
  }

  int _extractGpuModel(String gpuName) {
    final match = RegExp(r'(\d{3})').firstMatch(gpuName.toLowerCase());
    return match != null ? (int.tryParse(match.group(1)!) ?? 0) : 0;
  }

  String _sanitizeGemmaGarbage(String text) {
    return text
        .replaceAll(RegExp(r'<unused\d+>'), '')
        .replaceAll(RegExp(r'\[@BOS@\]'), '')
        .replaceAll('<bos>', '')
        .replaceAll('<mask>', '')
        .replaceAll('<pad>', '')
        .replaceAll('<unk>', '')
        .replaceAll('<s>', '')
        .replaceAll('</s>', '');
  }
}
