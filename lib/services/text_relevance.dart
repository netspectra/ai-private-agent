class TextRelevance {
  static final RegExp _wordPattern = RegExp(
    r'[a-z0-9а-яё]{2,}',
    caseSensitive: false,
    unicode: true,
  );

  static const Set<String> _stopWords = {
    'and',
    'the',
    'for',
    'with',
    'from',
    'this',
    'that',
    'have',
    'open',
    'please',
    'you',
    'your',
    'как',
    'что',
    'это',
    'для',
    'или',
    'его',
    'ее',
    'она',
    'они',
    'мне',
    'мой',
    'моя',
    'надо',
    'нужно',
    'открой',
    'пожалуйста',
  };

  static Set<String> tokens(String text) => _wordPattern
      .allMatches(text.toLowerCase())
      .map((match) => match.group(0)!)
      .where((word) => !_stopWords.contains(word))
      .toSet();

  static double score(String query, String candidate) {
    final queryTokens = tokens(query);
    final candidateTokens = tokens(candidate);
    if (queryTokens.isEmpty || candidateTokens.isEmpty) return 0;
    final overlap = queryTokens.intersection(candidateTokens).length;
    return overlap / queryTokens.length;
  }
}
