import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/agent_action.dart';
import 'local_inference_engine.dart';
import 'model_manager_service.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart' show ChatMessage;

class AiResponse {
  final String content;
  final int totalTokens;
  AiResponse(this.content, this.totalTokens);
}

class AiService {
  static const String _defaultBaseUrl = 'https://api.deepseek.com';
  static const String _defaultModel = 'deepseek-chat';
  static const String nvidiaBaseUrl = 'https://integrate.api.nvidia.com/v1';
  static const String nvidiaDefaultModel = 'z-ai/glm-5.2';

  /// Free, general-purpose chat endpoints verified in NVIDIA's NIM catalog.
  /// The live /models response is intersected with this list so unavailable or
  /// non-chat models never appear in PrivateAgent's NVIDIA model picker.
  static const List<String> nvidiaFreeChatModels = [
    'z-ai/glm-5.2',
    'nvidia/nemotron-3-nano-30b-a3b',
    'nvidia/nemotron-3-super-120b-a12b',
    'nvidia/nemotron-3-ultra-550b-a55b',
    'nvidia/nvidia-nemotron-nano-9b-v2',
    'openai/gpt-oss-20b',
    'openai/gpt-oss-120b',
    'meta/llama-3.3-70b-instruct',
    'meta/llama-3.2-3b-instruct',
    'meta/llama-3.1-8b-instruct',
    'meta/llama-3.1-70b-instruct',
    'mistralai/mistral-nemotron',
    'deepseek-ai/deepseek-v4-flash',
    'deepseek-ai/deepseek-v4-pro',
  ];

  static bool isNvidiaBaseUrl(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    return uri?.host.toLowerCase() == 'integrate.api.nvidia.com';
  }

  static List<String> filterNvidiaFreeModels(Iterable<String> models) {
    final availableModels = models.toSet();
    return nvidiaFreeChatModels
        .where(availableModels.contains)
        .toList(growable: false);
  }

  String? _apiKey;
  String _baseUrl = _defaultBaseUrl;
  String _model = _defaultModel;
  int _maxSteps = 15;
  bool _disableMaxSteps = false;
  double _temperature = 1.0;
  int _maxTokens = 1024;
  bool _useScreenCompression = true;
  bool _useSystemPrompt = true;
  bool _autoSwitchModel = true;
  bool _useOnDeviceInference = false;
  String? _onDeviceModelFilename;
  String? _defaultModelDownloadDir;
  
  final LocalInferenceEngine _localEngine = LocalInferenceEngine();
  List<String> _importedModels = [];
  
  // Getters
  List<String> get importedModels => _importedModels;
  final ModelManagerService _modelManager = ModelManagerService();
  final List<Map<String, String>> _conversationHistory = [];

  static const String _systemPrompt = '''
You are PrivateAgent, a helpful AI assistant that controls an Android phone. You can perform device actions and also have normal conversations.

When the user wants to perform a device action, you MUST respond with ONLY a JSON object (no markdown, no code fences, no extra text) in this exact format:
{"action": "action_name", "params": {"key": "value"}, "response": "What you say to the user"}

Available actions and their params:

SIMPLE ACTIONS (single step only):
- open_app: {"app_name": "YouTube"} - ONLY use this when the user JUST wants to open an app and nothing else
- make_call: {"contact_name": "Mom"} OR {"phone_number": "1234567890"} - Makes a phone call
- send_sms: {"contact_name": "John", "message": "Hello"} OR {"phone_number": "123", "message": "Hi"} - Sends SMS
- search_contact: {"query": "John"} - Searches contacts
- set_alarm: {"hour": 7, "minute": 30, "label": "Wake up"} - Sets an alarm
- set_volume: {"level": 50} - Sets volume (0-100)
- set_brightness: {"level": 50} - Sets brightness (0-100)
- read_screen: {} - Read what's currently on the screen
- press_back: {} - Press the back button

MULTI-STEP TASK (for anything that requires more than one action):
- execute_task: {"goal": "description of the full task"} - Automatically reads screen, taps, scrolls, types step by step

CRITICAL RULES:
1. If the user request contains "and" or involves MULTIPLE steps (open + search, open + send, open + find, etc.), you MUST use execute_task. NEVER use open_app for these.
2. execute_task handles everything: opening apps, finding elements, clicking, typing, scrolling.

Examples of when to use execute_task:
- "Create a new alarm for 7 AM" → execute_task with goal "Create a new alarm for 7 AM"
- "Go to YouTube and search for cats" → execute_task
- "Open WhatsApp and send hello to John" → execute_task
- "Open Settings and turn on WiFi" → execute_task
- "Search for restaurants on Google Maps" → execute_task

Examples of when to use open_app:
- "Open YouTube" → open_app (just opening, no further action)
- "Open Settings" → open_app (just opening)

For normal conversation (questions, chat, info requests), just respond with plain text naturally.
''';

  static const String _chatSystemPrompt = '''
You are PrivateAgent, a helpful conversational AI assistant. 
Provide direct, natural, and friendly text responses. You cannot perform device actions or run tools. 
Answer questions, explain concepts, brainstorm, write emails/messages, and chat with the user in plain text or markdown format.
''';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString('api_key');
    _baseUrl = prefs.getString('api_base_url') ?? _defaultBaseUrl;
    _model = prefs.getString('api_model') ?? _defaultModel;
    _maxSteps = prefs.getInt('api_max_steps') ?? 15;
    _disableMaxSteps = prefs.getBool('api_disable_max_steps') ?? false;
    _temperature = prefs.getDouble('api_temperature') ?? 1.0;
    _maxTokens = prefs.getInt('api_max_tokens') ?? 1024;
    _useScreenCompression = prefs.getBool('api_use_screen_compression') ?? true;
    _useSystemPrompt = prefs.getBool('api_use_system_prompt') ?? true;
    _autoSwitchModel = prefs.getBool('api_auto_switch_model') ?? true;
    _useOnDeviceInference = prefs.getBool('api_use_on_device_inference') ?? false;
    _onDeviceModelFilename = prefs.getString('api_on_device_model_filename');
    _defaultModelDownloadDir = prefs.getString('api_default_model_download_dir');
    _importedModels = prefs.getStringList('api_imported_models') ?? [];
    
    // Local models are now loaded lazily when the user sends a message
    // or when explicitly requested, preventing OOM crashes on startup.
  }

  Future<void> saveSettings({
    required String apiKey,
    String? baseUrl,
    String? model,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Clean up the API key in case the user pasted "Bearer sk-..."
    String cleanApiKey = apiKey.trim();
    if (cleanApiKey.toLowerCase().startsWith('bearer ')) {
      cleanApiKey = cleanApiKey.substring(7).trim();
    }

    _apiKey = cleanApiKey;
    await prefs.setString('api_key', cleanApiKey);

    if (baseUrl != null && baseUrl.isNotEmpty) {
      _baseUrl = baseUrl;
      await prefs.setString('api_base_url', baseUrl);
    }
    if (model != null && model.isNotEmpty) {
      _model = model;
      await prefs.setString('api_model', model);
    }
  }

  Future<void> saveMaxSteps(int steps) async {
    final prefs = await SharedPreferences.getInstance();
    _maxSteps = steps;
    await prefs.setInt('api_max_steps', steps);
  }

  Future<void> saveAutoSwitchModel(bool autoSwitch) async {
    final prefs = await SharedPreferences.getInstance();
    _autoSwitchModel = autoSwitch;
    await prefs.setBool('api_auto_switch_model', autoSwitch);
  }

  Future<void> saveDisableMaxSteps(bool disable) async {
    final prefs = await SharedPreferences.getInstance();
    _disableMaxSteps = disable;
    await prefs.setBool('api_disable_max_steps', disable);
  }

  Future<void> saveAdvancedSettings({
    required double temperature,
    required int maxTokens,
    required bool useScreenCompression,
    required bool useSystemPrompt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _temperature = temperature;
    _maxTokens = maxTokens;
    _useScreenCompression = useScreenCompression;
    _useSystemPrompt = useSystemPrompt;
    await prefs.setDouble('api_temperature', temperature);
    await prefs.setInt('api_max_tokens', maxTokens);
    await prefs.setBool('api_use_screen_compression', useScreenCompression);
    await prefs.setBool('api_use_system_prompt', useSystemPrompt);
  }

  bool get isConfigured => 
      _useOnDeviceInference || 
      _baseUrl.contains('127.0.0.1') || 
      (_apiKey != null && _apiKey!.isNotEmpty);
  String get baseUrl => _baseUrl;
  String get model => _model;
  String get apiKey => _apiKey ?? '';
  int get maxSteps => _disableMaxSteps ? 999999 : _maxSteps;
  int get rawMaxSteps => _maxSteps; // For the slider UI
  bool get disableMaxSteps => _disableMaxSteps;
  double get temperature => _temperature;
  int get maxTokens => _maxTokens;
  bool get useScreenCompression => _useScreenCompression;
  bool get useSystemPrompt => _useSystemPrompt;
  bool get autoSwitchModel => _autoSwitchModel;
  bool get useOnDeviceInference => _useOnDeviceInference;
  bool get isLocalEngineInitialized => _localEngine.isInitialized;
  
  Future<void> ejectLocalModel() async {
    await saveOnDeviceSettings(false, _onDeviceModelFilename);
  }

  String? get onDeviceModelFilename => _onDeviceModelFilename;
  String? get defaultModelDownloadDir => _defaultModelDownloadDir;
  ModelManagerService get modelManager => _modelManager;

  Future<void> saveDefaultModelDownloadDir(String? dir) async {
    final prefs = await SharedPreferences.getInstance();
    if (dir == null) {
      await prefs.remove('api_default_model_download_dir');
    } else {
      await prefs.setString('api_default_model_download_dir', dir);
    }
    _defaultModelDownloadDir = dir;
  }

  Future<void> addImportedModel(String path) async {
    if (!_importedModels.contains(path)) {
      _importedModels.add(path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('api_imported_models', _importedModels);
    }
  }

  Future<void> removeImportedModel(String path) async {
    _importedModels.remove(path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('api_imported_models', _importedModels);
    // If we delete the active model, disable it
    if (_useOnDeviceInference && _onDeviceModelFilename == path.split('/').last) {
      await saveOnDeviceSettings(false, null);
    }
  }

  Future<void> saveOnDeviceSettings(bool useOnDevice, String? filename, {bool autoLoad = true}) async {
    final prefs = await SharedPreferences.getInstance();
    _useOnDeviceInference = useOnDevice;
    if (filename != null) {
      _onDeviceModelFilename = filename;
      await prefs.setString('api_on_device_model_filename', filename);
    }
    await prefs.setBool('api_use_on_device_inference', useOnDevice);
    
    if (useOnDevice && _onDeviceModelFilename != null && autoLoad) {
      await initLocalModel();
    } else if (!useOnDevice) {
      await _localEngine.dispose();
    }
  }

  Future<void> initLocalModel() async {
    if (_onDeviceModelFilename == null) return;
    try {
      String? path;
      if (defaultModelDownloadDir != null) {
        final customFile = File('$defaultModelDownloadDir/$_onDeviceModelFilename');
        if (await customFile.exists()) {
          path = customFile.path;
        }
      }
      if (path == null) {
        for (var importedPath in _importedModels) {
          if (importedPath.endsWith(_onDeviceModelFilename!)) {
            final f = File(importedPath);
            if (await f.exists()) {
              path = f.path;
            }
            break;
          }
        }
      }
      if (path == null) {
        path = await _modelManager.getModelPath(_onDeviceModelFilename!);
      }
      
      if (path != null) {
        await _localEngine.loadModel(path);
      } else {
        throw Exception('Model file not found on device.');
      }
    } catch (e) {
      developer.log('Error loading local model: $e', name: 'AiService');
      throw Exception('Failed to initialize local model: $e');
    }
  }

  int get _effectiveMaxTokens {
    // GLM is a reasoning model. With the app's 1,024-token default it can
    // consume the whole budget reasoning and finish without visible content.
    if (isNvidiaBaseUrl(_baseUrl) &&
        _model == nvidiaDefaultModel &&
        _maxTokens < 4096) {
      return 4096;
    }
    return _maxTokens;
  }

  void clearHistory() {
    _conversationHistory.clear();
  }

  void addHistoryMessage(String role, String content) {
    _conversationHistory.add({'role': role, 'content': content});
    if (_conversationHistory.length > 20) {
      _conversationHistory.removeRange(0, _conversationHistory.length - 20);
    }
  }

  /// Send a message to the AI and get a response.
  
  Future<bool> _tryAutoSwitchModel(String baseUrl, String apiKey, Function(String, String, String)? onModelSwitch, String reason, {Set<String>? attemptedModels}) async {
    if (!_autoSwitchModel) return false;
    try {
      final models = await fetchAvailableModels(baseUrl, apiKey);
      if (models.isNotEmpty) {
        final validModels = models.where((m) => 
          !m.toLowerCase().contains('embedding') && 
          !m.toLowerCase().contains('aqa') &&
          !m.toLowerCase().contains('vision') &&
          !m.toLowerCase().contains('tts') &&
          !m.toLowerCase().contains('audio') &&
          !m.toLowerCase().contains('robotics') &&
          !m.toLowerCase().contains('antigravity') &&
          m != _model &&
          !(attemptedModels?.contains(m) ?? false)
        ).toList();
        
        if (validModels.isNotEmpty) {
          String? newModel;
          String currentFamily = _model.split('-').first.toLowerCase();
          for (var m in validModels) {
            if (m.toLowerCase().startsWith(currentFamily)) {
              newModel = m;
              break;
            }
          }
          newModel ??= validModels.first;
          
          String oldModel = _model;
          _model = newModel;
          await saveSettings(apiKey: apiKey, baseUrl: baseUrl, model: _model);
          if (onModelSwitch != null) {
            onModelSwitch(oldModel, _model, reason);
          }
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<String> sendMessage(String message, {bool isAgentMode = true, Function(String, String, String)? onModelSwitch, Set<String>? attemptedModels}) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API Key is not configured. Please go to Settings.');
    }

    if (attemptedModels == null) {
      // Add ONLY the text to the persistent conversation history to save tokens.
      _conversationHistory.add({'role': 'user', 'content': message});

      // Keep conversation history manageable (last 20 messages)
      if (_conversationHistory.length > 20) {
        _conversationHistory.removeRange(0, _conversationHistory.length - 20);
      }
    }

    try {
      // Build the prompt including system instructions
      final systemPrompt = isAgentMode ? _systemPrompt : _chatSystemPrompt;
      final messages = [
        if (_useSystemPrompt) {'role': 'system', 'content': systemPrompt},
        ..._conversationHistory,
      ];

      String requestUrl = _baseUrl;
      if (requestUrl.endsWith('/chat/completions')) {
        requestUrl = requestUrl; // User already included it
      } else {
        if (requestUrl.endsWith('/')) {
          requestUrl = '${requestUrl}chat/completions';
        } else {
          requestUrl = '$requestUrl/chat/completions';
        }
      }

      final requestBody = jsonEncode({
        'model': _model,
        'messages': messages,
        'temperature': _temperature,
        'max_tokens': _effectiveMaxTokens,
      });

      developer.log(
        'API Request: $requestUrl\n$requestBody',
        name: 'AiService',
      );

      final response = await http
          .post(
            Uri.parse(requestUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
              'HTTP-Referer': 'https://github.com/orailnoor/private-agent',
              'X-Title': 'PrivateAgent',
            },
            body: requestBody,
          )
          .timeout(const Duration(minutes: 30));

      developer.log(
        'API Response [${response.statusCode}]: ${response.body}',
        name: 'AiService',
      );

      if (response.statusCode != 200) {
        String errorMessage = response.body;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) {
            if (decoded['error'] is Map<String, dynamic>) {
              errorMessage =
                  decoded['error']['message']?.toString() ?? response.body;
            } else if (decoded['error'] is String) {
              errorMessage = decoded['error'];
            }
          }
        } catch (_) {
          // ignore parsing errors, use raw body
        }
        
        bool isInteractionsApiError = response.statusCode == 400 && errorMessage.contains('Interactions API');
        if (response.statusCode == 429 || response.statusCode == 404 || response.statusCode >= 500 || isInteractionsApiError) {
          attemptedModels ??= {};
          attemptedModels.add(_model);
          String reason = response.statusCode == 429 ? 'Rate limit reached' : (response.statusCode == 404 ? 'Model not found' : (isInteractionsApiError ? 'Interactions API required' : 'API Error (${response.statusCode})'));
          bool switched = await _tryAutoSwitchModel(_baseUrl, _apiKey!, onModelSwitch, reason, attemptedModels: attemptedModels);
          if (switched) {
            return await sendMessage(message, isAgentMode: isAgentMode, onModelSwitch: onModelSwitch, attemptedModels: attemptedModels);
          } else if (_baseUrl.toLowerCase().contains('google')) {
            throw Exception('All models have hit rate limit. Check here https://aistudio.google.com/rate-limit try after sometime or change api key from different account.');
          }
        }
        
        throw Exception('API error (${response.statusCode}): $errorMessage');
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || !data.containsKey('choices')) {
        throw Exception('Unexpected API response format: $data');
      }

      String assistantMessage =
          data['choices'][0]['message']['content'] as String;

      // Strip <think> and <thought> blocks commonly produced by reasoning models
      assistantMessage = assistantMessage
          .replaceAll(RegExp(r'<(think|thought)>.*?</\1>', dotAll: true), '')
          .trim();

      if (assistantMessage.trim().isEmpty) {
        throw Exception(
          'API returned an empty response. This may be due to rate limits or API instability.',
        );
      }

      _conversationHistory.add({
        'role': 'assistant',
        'content': assistantMessage,
      });

      return assistantMessage;
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Network error: $e');
    }
  }

  /// Send a message and stream the response chunk-by-chunk.
  Stream<String> sendMessageStream(
    String message, {
    bool isAgentMode = true,
    Function(String, String, String)? onModelSwitch,
    Set<String>? attemptedModels,
  }) async* {
    if (attemptedModels == null) {
      _conversationHistory.add({'role': 'user', 'content': message});

      if (_conversationHistory.length > 20) {
        _conversationHistory.removeRange(0, _conversationHistory.length - 20);
      }
    }

    if (_useOnDeviceInference) {
      if (!_localEngine.isInitialized) await initLocalModel();
      final systemPrompt = isAgentMode ? _systemPrompt : _chatSystemPrompt;
      
      final messages = <ChatMessage>[];
      if (_useSystemPrompt) {
        messages.add(ChatMessage(role: 'system', content: systemPrompt));
      }
      for (var msg in _conversationHistory) {
        messages.add(ChatMessage(role: msg['role'] ?? 'user', content: msg['content'] ?? ''));
      }
      
      final accumulatedContent = StringBuffer();
      await for (final token in _localEngine.generateChatStream(messages)) {
        accumulatedContent.write(token);
        yield token;
      }
      _conversationHistory.add({'role': 'assistant', 'content': accumulatedContent.toString().trim()});
      return;
    }

    try {
      final systemPrompt = isAgentMode ? _systemPrompt : _chatSystemPrompt;
      final messages = [
        if (_useSystemPrompt) {'role': 'system', 'content': systemPrompt},
        ..._conversationHistory,
      ];

      String requestUrl = _baseUrl;
      if (requestUrl.endsWith('/chat/completions')) {
        requestUrl = requestUrl;
      } else {
        if (requestUrl.endsWith('/')) {
          requestUrl = '${requestUrl}chat/completions';
        } else {
          requestUrl = '$requestUrl/chat/completions';
        }
      }

      final client = http.Client();
      final request = http.Request('POST', Uri.parse(requestUrl));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
        'HTTP-Referer': 'https://github.com/orailnoor/private-agent',
        'X-Title': 'PrivateAgent',
      });

      request.body = jsonEncode({
        'model': _model,
        'messages': messages,
        'temperature': _temperature,
        'max_tokens': _effectiveMaxTokens,
        'stream': true,
      });

      final response = await client
          .send(request)
          .timeout(const Duration(minutes: 30));

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        String errorMessage = body;
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) {
            if (decoded['error'] is Map<String, dynamic>) {
              errorMessage = decoded['error']['message']?.toString() ?? body;
            } else if (decoded['error'] is String) {
              errorMessage = decoded['error'];
            }
          }
        } catch (_) {}
        client.close();
        
        bool isInteractionsApiError = response.statusCode == 400 && errorMessage.contains('Interactions API');
        if (response.statusCode == 429 || response.statusCode == 404 || response.statusCode >= 500 || isInteractionsApiError) {
          attemptedModels ??= {};
          attemptedModels.add(_model);
          String reason = response.statusCode == 429 ? 'Rate limit reached' : (response.statusCode == 404 ? 'Model not found' : (isInteractionsApiError ? 'Interactions API required' : 'API Error (${response.statusCode})'));
          bool switched = await _tryAutoSwitchModel(_baseUrl, _apiKey!, onModelSwitch, reason, attemptedModels: attemptedModels);
          if (switched) {
            yield* sendMessageStream(message, isAgentMode: isAgentMode, onModelSwitch: onModelSwitch, attemptedModels: attemptedModels);
            return;
          } else if (_baseUrl.toLowerCase().contains('google')) {
            throw Exception('All models have hit rate limit. Check here https://aistudio.google.com/rate-limit try after sometime or change api key from different account.');
          }
        }
        
        throw Exception('API error (${response.statusCode}): $errorMessage');
      }

      final accumulatedContent = StringBuffer();
      bool inThinkBlock = false;

      // Listen to response stream
      final lineStream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lineStream) {
        final trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;
        if (trimmedLine.startsWith('data:')) {
          final dataStr = trimmedLine.substring(5).trim();
          if (dataStr == '[DONE]') break;
          try {
            final json = jsonDecode(dataStr);
            if (json is Map && json['choices'] is List) {
              final choices = json['choices'] as List;
              if (choices.isNotEmpty) {
                final choice = choices[0];
                if (choice is! Map) continue;
                final rawDelta = choice['delta'];
                final delta = rawDelta is Map ? rawDelta : const {};
                final rawContent = delta['content'];
                if (rawContent is String && rawContent.isNotEmpty) {
                  final content = rawContent;
                  accumulatedContent.write(content);

                  // Handle <think> and <thought> block stripping on the fly for better stream styling
                  if (content.contains('<think>') || content.contains('<thought>')) {
                    inThinkBlock = true;
                    final tag = content.contains('<think>') ? '<think>' : '<thought>';
                    final parts = content.split(tag);
                    if (parts[0].isNotEmpty) {
                      yield parts[0];
                    }
                  } else if (content.contains('</think>') || content.contains('</thought>')) {
                    inThinkBlock = false;
                    final tag = content.contains('</think>') ? '</think>' : '</thought>';
                    final parts = content.split(tag);
                    if (parts.length > 1 && parts[1].isNotEmpty) {
                      yield parts[1];
                    }
                  } else if (!inThinkBlock) {
                    yield content;
                  }
                }
                if (choice['finish_reason'] != null) break;
              }
            }
          } catch (_) {
            // Ignore incomplete chunks
          }
        }
      }

      client.close();

      // Clean up final accumulated response and add to history
      String finalResponse = accumulatedContent.toString().trim();
      finalResponse = finalResponse
          .replaceAll(RegExp(r'<(think|thought)>.*?</\1>', dotAll: true), '')
          .trim();

      if (finalResponse.isEmpty) {
        throw Exception(
          'The model finished without a visible answer. Increase Max Tokens '
          'or try another NVIDIA model.',
        );
      }
      _conversationHistory.add({'role': 'assistant', 'content': finalResponse});
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Network error: $e');
    }
  }

  /// Sends a task message (used by the agent for internal steps).
  /// This is much faster and cheaper than sendMessage.
  Future<AiResponse> sendTaskMessage(String systemPrompt, String prompt, {Function(String, String, String)? onModelSwitch, Set<String>? attemptedModels}) async {
    if (_useOnDeviceInference) {
      if (!_localEngine.isInitialized) await initLocalModel();
      final messages = <ChatMessage>[
        ChatMessage(role: 'system', content: systemPrompt),
        ChatMessage(role: 'user', content: prompt),
      ];
      final responseStr = await _localEngine.generateChat(messages);
      return AiResponse(responseStr.trim(), responseStr.length ~/ 4);
    }
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API Key is not configured. Please go to Settings.');
    }

    int maxRetries = 4;
    int currentTry = 0;

    while (true) {
      try {
        currentTry++;
        final messages = [
          if (_useSystemPrompt) {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': prompt},
        ];

        String requestUrl = _baseUrl;
        if (!requestUrl.endsWith('/chat/completions')) {
          if (requestUrl.endsWith('/')) {
            requestUrl = '${requestUrl}chat/completions';
          } else {
            requestUrl = '$requestUrl/chat/completions';
          }
        }

        final response = await http
            .post(
              Uri.parse(requestUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $_apiKey',
                'HTTP-Referer': 'https://github.com/orailnoor/private-agent',
                'X-Title': 'PrivateAgent',
              },
              body: jsonEncode({
                'model': _model,
                'messages': messages,
                'temperature': _temperature,
                'max_tokens': _effectiveMaxTokens,
              }),
            )
            .timeout(const Duration(minutes: 30));

        if (response.statusCode != 200) {
          String errorMessage = response.body;
          try {
            final decoded = jsonDecode(response.body);
            if (decoded is Map<String, dynamic>) {
              if (decoded['error'] is Map<String, dynamic>) {
                errorMessage = decoded['error']['message'] ?? response.body;
              } else if (decoded['error'] is String) {
                errorMessage = decoded['error'];
              }
            }
          } catch (_) {
            // ignore parsing errors, use raw body
          }
          
          bool isInteractionsApiError = response.statusCode == 400 && errorMessage.contains('Interactions API');
          if (response.statusCode == 429 || response.statusCode == 404 || response.statusCode >= 500 || isInteractionsApiError) {
            attemptedModels ??= {};
            attemptedModels.add(_model);
            String reason = response.statusCode == 429 ? 'Rate limit reached' : (response.statusCode == 404 ? 'Model not found' : (isInteractionsApiError ? 'Interactions API required' : 'API Error (${response.statusCode})'));
            bool switched = await _tryAutoSwitchModel(_baseUrl, _apiKey!, onModelSwitch, reason, attemptedModels: attemptedModels);
            if (switched) {
              return await sendTaskMessage(systemPrompt, prompt, onModelSwitch: onModelSwitch, attemptedModels: attemptedModels);
            } else if (_baseUrl.toLowerCase().contains('google')) {
              throw Exception('All models have hit rate limit. Check here https://aistudio.google.com/rate-limit try after sometime or change api key from different account.');
            }
          }
          
          throw Exception('API error (${response.statusCode}): $errorMessage');
        }

        final data = jsonDecode(response.body);
        if (data is! Map<String, dynamic> || !data.containsKey('choices')) {
          throw Exception('Unexpected API response format: $data');
        }
        String content = data['choices'][0]['message']['content'] as String;

        // Strip <think> and <thought> blocks commonly produced by reasoning models
        content = content
            .replaceAll(RegExp(r'<(think|thought)>.*?</\1>', dotAll: true), '')
            .trim();

        if (content.trim().isEmpty) {
          throw Exception(
            'API returned an empty response. This may be due to strict rate limits or safety filters.',
          );
        }

        int tokens = 0;
        if (data.containsKey('usage') &&
            data['usage']['total_tokens'] != null) {
          tokens = data['usage']['total_tokens'] as int;
        }
        return AiResponse(content, tokens);
      } catch (e) {
        if (currentTry > maxRetries) {
          if (e is Exception) rethrow;
          throw Exception('Network error after $maxRetries retries: $e');
        }
        int delaySeconds = 3 * currentTry;
        developer.log(
          'API call failed ($e), retrying $currentTry/$maxRetries in $delaySeconds seconds...',
          name: 'PrivateAgent',
        );
        await Future.delayed(Duration(seconds: delaySeconds));
      }
    }
  }

  /// Parse the AI response to check if it's an action or plain text
  AgentAction? parseAction(String response) {
    // Try to parse as JSON action
    try {
      // Strip <think> and <thought> blocks first so JSON parsing works
      String jsonStr = response
          .replaceAll(RegExp(r'<(think|thought)>.*?</\1>', dotAll: true), '')
          .trim();
          
      // Handle if the response is wrapped in code fences
      if (jsonStr.startsWith('```')) {
        final lines = jsonStr.split('\n');
        lines.removeAt(0); // Remove opening fence
        if (lines.isNotEmpty && lines.last.trim() == '```') {
          lines.removeLast(); // Remove closing fence
        }
        jsonStr = lines.join('\n').trim();
      }

      // If it looks like JSON but is missing a closing brace (common with some local models)
      if (jsonStr.startsWith('{') && !jsonStr.endsWith('}')) {
        jsonStr += '\n}';
      }

      if (jsonStr.startsWith('{') && jsonStr.contains('"action"')) {
        // Attempt to fix missing commas before parsing (common in small local models)
        // This matches a quote, closing brace, or bracket, followed by whitespace, followed by a quote, opening brace, or bracket.
        jsonStr = jsonStr.replaceAllMapped(RegExp(r'("|\}|\])\s+("|\{|\[)'), (match) {
          return '${match.group(1)}, ${match.group(2)}';
        });

        try {
          final json = jsonDecode(jsonStr) as Map<String, dynamic>;
          if (json.containsKey('action')) {
            return AgentAction.fromJson(json);
          }
        } catch (e) {
          // If it still fails, it might be deeply truncated, try adding another brace
          if (e.toString().contains('Unexpected end of input')) {
            jsonStr += '\n}';
            try {
              final json = jsonDecode(jsonStr) as Map<String, dynamic>;
              if (json.containsKey('action')) {
                return AgentAction.fromJson(json);
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {
      // Not JSON, it's plain text conversation
    }
    return null;
  }

  /// Fetches available models from the provider's /models endpoint
  Future<List<String>> fetchAvailableModels(
    String baseUrl,
    String apiKey,
  ) async {
    try {
      String cleanBaseUrl = baseUrl;
      if (cleanBaseUrl == 'Local On-Device Inference') {
        List<String> localModels = [];
        for (var path in _importedModels) {
          localModels.add(path.split('/').last);
        }
        if (_defaultModelDownloadDir != null) {
          final dir = Directory(_defaultModelDownloadDir!);
          if (await dir.exists()) {
            for (var file in dir.listSync()) {
              if (file.path.endsWith('.gguf')) {
                localModels.add(file.path.split('/').last);
              }
            }
          }
        }
        final defaultDir = await _modelManager.getModelDirectory();
        if (await defaultDir.exists()) {
          for (var file in defaultDir.listSync()) {
            if (file.path.endsWith('.gguf')) {
              localModels.add(file.path.split('/').last);
            }
          }
        }
        return localModels.toSet().toList();
      }

      // Many providers host it at /models, but some require the base URL without /chat/completions logic
      if (cleanBaseUrl.endsWith('/chat/completions')) {
        cleanBaseUrl = cleanBaseUrl.replaceAll('/chat/completions', '');
      }
      if (cleanBaseUrl.endsWith('/')) {
        cleanBaseUrl = cleanBaseUrl.substring(0, cleanBaseUrl.length - 1);
      }

      final response = await http.get(
        Uri.parse('$cleanBaseUrl/models'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<String> models;
        if (data is Map && data.containsKey('data')) {
          final modelsList = data['data'] as List;
          models = modelsList.map((m) => m['id'].toString()).toList();
        } else if (data is List) {
          models = data.map((m) => m['id'].toString()).toList();
        } else {
          return [];
        }

        if (isNvidiaBaseUrl(cleanBaseUrl)) {
          return filterNvidiaFreeModels(models);
        }
        models.sort();
        return models;
      }
      return [];
    } catch (e) {
      print('Error fetching models: $e');
      return [];
    }
  }
}
