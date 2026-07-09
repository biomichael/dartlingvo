import '../models/dictionary_entry.dart';

class TrieNode {
  final Map<String, TrieNode> children = {};
  final List<WordIndexEntry> entries = [];
}

class WordIndex {
  final TrieNode _root = TrieNode();
  final List<WordIndexEntry> _entries = [];
  bool _sorted = false;

  bool get isEmpty => _entries.isEmpty;
  int get size => _entries.length;
  List<WordIndexEntry> get entries => List.unmodifiable(_entries);

  void addEntry(WordIndexEntry entry) {
    _entries.add(entry);
    _insertTrie(entry.word.toLowerCase(), entry);
    _sorted = false;
  }

  void addEntries(Iterable<WordIndexEntry> entries) {
    for (final entry in entries) {
      _entries.add(entry);
      _insertTrie(entry.word.toLowerCase(), entry);
    }
    _sorted = false;
  }

  void removeWhere(bool Function(WordIndexEntry entry) test) {
    _entries.removeWhere(test);
    _rebuildTrie();
    _sorted = false;
  }

  void _insertTrie(String word, WordIndexEntry entry) {
    var node = _root;
    for (var i = 0; i < word.length; i++) {
      final ch = word[i];
      node = node.children.putIfAbsent(ch, () => TrieNode());
    }
    node.entries.add(entry);
  }

  List<WordIndexEntry> searchByPrefix(String prefix) {
    if (prefix.isEmpty) return [];

    final node = _findNode(prefix.toLowerCase());
    if (node == null) return [];

    final results = <WordIndexEntry>[];
    _collectEntries(node, results);

    if (results.length > 200) {
      results.sort((a, b) => a.word.compareTo(b.word));
      return results.take(200).toList();
    }

    return results;
  }

  TrieNode? _findNode(String prefix) {
    var node = _root;
    for (var i = 0; i < prefix.length; i++) {
      final child = node.children[prefix[i]];
      if (child == null) return null;
      node = child;
    }
    return node;
  }

  void _collectEntries(TrieNode node, List<WordIndexEntry> results) {
    if (results.length >= 200) return;

    for (final entry in node.entries) {
      if (results.length >= 200) return;
      results.add(entry);
    }

    final sortedKeys = node.children.keys.toList()..sort();
    for (final key in sortedKeys) {
      if (results.length >= 200) return;
      _collectEntries(node.children[key]!, results);
    }
  }

  List<WordIndexEntry> exactSearch(String word) {
    final result = <WordIndexEntry>[];
    final lower = word.toLowerCase();

    for (final entry in _entries) {
      if (entry.word.toLowerCase() == lower) {
        result.add(entry);
      }
    }
    return result;
  }

  List<WordIndexEntry> fuzzySearch(String query, {int maxResults = 50}) {
    final results = <_ScoredEntry>[];
    final lower = query.toLowerCase();

    for (final entry in _entries) {
      final entryLower = entry.word.toLowerCase();

      if (entryLower == lower) {
        results.add(_ScoredEntry(entry, 0));
        continue;
      }

      if (entryLower.startsWith(lower)) {
        results.add(_ScoredEntry(entry, 1));
        continue;
      }

      if (entryLower.contains(lower)) {
        results.add(_ScoredEntry(entry, 2));
        continue;
      }

      final score = _levenshteinDistance(lower, entryLower);
      if (score <= 3) {
        results.add(_ScoredEntry(entry, score + 10));
      }
    }

    results.sort();
    return results.take(maxResults).map((e) => e.entry).toList();
  }

  int _levenshteinDistance(String a, String b) {
    if (a.length > b.length) {
      final tmp = a;
      a = b;
      b = tmp;
    }

    final la = a.length;
    final lb = b.length;

    if (la == 0) return lb;
    if (lb - la > 3) return 99;

    var prev = List.generate(la + 1, (i) => i);
    var curr = List.filled(la + 1, 0);

    for (var i = 0; i < lb; i++) {
      curr[0] = i + 1;
      for (var j = 0; j < la; j++) {
        final cost = a[j] == b[i] ? 0 : 1;
        curr[j + 1] = [
          curr[j] + 1,
          prev[j + 1] + 1,
          prev[j] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }

    return prev[la];
  }

  Map<String, dynamic> serializeTrie() => _serializeNode(_root);

  Map<String, dynamic> _serializeNode(TrieNode node) => {
        'e': node.entries.map((e) => e.toJson()).toList(),
        'c': node.children.map((k, v) => MapEntry(k, _serializeNode(v))),
      };

  void deserializeTrie(Map<String, dynamic> data) {
    _root.children.clear();
    _entries.clear();
    _sorted = false;
    _deserializeNode(data, _root);
  }

  void _deserializeNode(Map<String, dynamic> data, TrieNode node) {
    for (final entryData in (data['e'] as List<dynamic>? ?? [])) {
      final entry = WordIndexEntry.fromJson(entryData as Map<String, dynamic>);
      node.entries.add(entry);
      _entries.add(entry);
    }
    for (final entry
        in (data['c'] as Map<String, dynamic>? ?? {}).entries) {
      final child = TrieNode();
      node.children[entry.key] = child;
      _deserializeNode(entry.value as Map<String, dynamic>, child);
    }
  }

  void clear() {
    _root.children.clear();
    _entries.clear();
  }

  void _rebuildTrie() {
    _root.children.clear();
    for (final entry in _entries) {
      _insertTrie(entry.word.toLowerCase(), entry);
    }
  }

  List<String> getAllWords() {
    if (!_sorted) {
      _entries.sort((a, b) => a.word.compareTo(b.word));
      _sorted = true;
    }
    return _entries.map((e) => e.word).toSet().toList();
  }
}

class _ScoredEntry implements Comparable<_ScoredEntry> {
  final WordIndexEntry entry;
  final int score;

  const _ScoredEntry(this.entry, this.score);

  @override
  int compareTo(_ScoredEntry other) {
    final scoreCmp = score.compareTo(other.score);
    if (scoreCmp != 0) return scoreCmp;
    return entry.word.compareTo(other.entry.word);
  }
}
