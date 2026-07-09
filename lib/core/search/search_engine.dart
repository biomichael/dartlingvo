import '../models/dictionary_entry.dart';
import '../index/word_index.dart';

class SearchResult {
  final String word;
  final String dictionaryId;
  final String dictionaryName;
  final int relevanceScore;

  const SearchResult({
    required this.word,
    required this.dictionaryId,
    required this.dictionaryName,
    this.relevanceScore = 0,
  });

  String get lookupKey => '$dictionaryId:$word';
}

class SearchEngine {
  final WordIndex _index;

  SearchEngine(this._index);

  WordIndex get index => _index;

  List<SearchResult> search(String query,
      {String? dictionaryId, int maxResults = 100}) {
    if (query.isEmpty) return [];

    final results = <SearchResult>[];

    final trimmed = query.trim();
    final entries = _index.fuzzySearch(trimmed, maxResults: maxResults);

    for (final entry in entries) {
      if (dictionaryId != null && entry.dictionaryId != dictionaryId) {
        continue;
      }
      results.add(SearchResult(
        word: entry.word,
        dictionaryId: entry.dictionaryId,
        dictionaryName: entry.dictionaryName,
        relevanceScore: _computeScore(trimmed, entry.word),
      ));
    }

    return results;
  }

  List<SearchResult> prefixSearch(String prefix,
      {String? dictionaryId, int maxResults = 50}) {
    if (prefix.isEmpty) return [];

    final entries = _index.searchByPrefix(prefix);
    final results = <SearchResult>[];

    for (final entry in entries) {
      if (dictionaryId != null && entry.dictionaryId != dictionaryId) {
        continue;
      }
      if (results.any((r) =>
          r.word == entry.word && r.dictionaryId == entry.dictionaryId)) {
        continue;
      }
      results.add(SearchResult(
        word: entry.word,
        dictionaryId: entry.dictionaryId,
        dictionaryName: entry.dictionaryName,
      ));
    }

    if (results.length > maxResults) {
      return results.sublist(0, maxResults);
    }

    return results;
  }

  List<SearchResult> fullTextSearch(
    String query,
    List<DictionaryEntry> allEntries, {
    String? dictionaryId,
    int maxResults = 50,
  }) {
    if (query.isEmpty) return [];

    final lower = query.toLowerCase();
    final results = <SearchResult>[];

    for (final entry in allEntries) {
      if (dictionaryId != null && entry.dictionaryId != dictionaryId) continue;

      final wordLower = entry.word.toLowerCase();
      bool matched = false;

      if (wordLower.contains(lower)) {
        matched = true;
      } else {
        for (final def in entry.definitions) {
          if (def.plainText.toLowerCase().contains(lower)) {
            matched = true;
            break;
          }
        }
      }

      if (matched) {
        results.add(SearchResult(
          word: entry.word,
          dictionaryId: entry.dictionaryId,
          dictionaryName: entry.dictionaryName,
        ));
      }

      if (results.length >= maxResults) break;
    }

    return results;
  }

  int _computeScore(String query, String word) {
    final q = query.toLowerCase();
    final w = word.toLowerCase();

    if (w == q) return 0;
    if (w.startsWith(q)) return 1;
    if (w.contains(q)) return 2;
    return 10;
  }

  void rebuildIndex() {
    _index.clear();
  }
}
