class LocalModelSuggestion {
  final String name;
  final String recommendedRam;
  final String description;
  final String url;
  final String size;

  const LocalModelSuggestion({
    required this.name,
    required this.recommendedRam,
    required this.description,
    required this.url,
    required this.size,
  });
}

class LocalModelsConfig {
  /// Developer configuration for local model suggestions.
  /// Add or replace models here as newer, more capable models become available.
  static const List<LocalModelSuggestion> suggestions = [
    LocalModelSuggestion(
      name: 'Qwen1.5 0.5B Chat (Small)',
      recommendedRam: '1GB+ RAM',
      description: 'Extremely fast and lightweight model for testing and basic conversations. Runs on almost any device.',
      url: 'https://huggingface.co/Qwen/Qwen1.5-0.5B-Chat-GGUF/resolve/main/qwen1_5-0_5b-chat-q4_k_m.gguf?download=true',
      size: '',
    ),
    LocalModelSuggestion(
      name: 'Ternary Bonsai 27B',
      recommendedRam: '8GB+ RAM',
      description: 'Higher precision model for devices with more RAM. Provides better reasoning and instruction following capabilities.',
      url: 'https://huggingface.co/prism-ml/Ternary-Bonsai-27B-gguf/resolve/main/Ternary-Bonsai-27B-Q2_0.gguf?download=true',
      size: '',
    ),
    LocalModelSuggestion(
      name: '1-bit Bonsai 27B',
      recommendedRam: '6GB RAM',
      description: 'Highly compressed model suitable for most modern devices with limited memory.',
      url: 'https://huggingface.co/prism-ml/Bonsai-27B-gguf/resolve/main/Bonsai-27B-Q1_0.gguf?download=true',
      size: '',
    ),
  ];
}
