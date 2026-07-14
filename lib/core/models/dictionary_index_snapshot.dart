import 'dictionary.dart';
import 'dictionary_entry.dart';

class DictionaryIndexSnapshot {
  final Dictionary dictionary;
  final List<WordIndexEntry> indexEntries;

  const DictionaryIndexSnapshot({
    required this.dictionary,
    required this.indexEntries,
  });

  Map<String, dynamic> toJson() => {
        'dictionary': dictionary.toJson(),
        'indexEntries': indexEntries.map((entry) => entry.toJson()).toList(),
      };

  factory DictionaryIndexSnapshot.fromJson(Map<String, dynamic> json) {
    return DictionaryIndexSnapshot(
      dictionary: Dictionary.fromJson(json['dictionary'] as Map<String, dynamic>),
      indexEntries: (json['indexEntries'] as List<dynamic>)
          .map((entry) => WordIndexEntry.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }

  factory DictionaryIndexSnapshot.fromCacheJson(Map<String, dynamic> json) {
    final dictionary = Dictionary.fromJson(json['dictionary'] as Map<String, dynamic>);
    final entries = json['entries'] as List<dynamic>? ?? [];
    return DictionaryIndexSnapshot(
      dictionary: dictionary,
      indexEntries: entries
          .map((entry) {
            final data = entry as Map<String, dynamic>;
            return WordIndexEntry(
              word: data['word'] as String,
              dictionaryId: data['dictionaryId'] as String,
              dictionaryName: data['dictionaryName'] as String,
              entryIndex: data['index'] as int? ?? data['entryIndex'] as int? ?? 0,
              articleReference: data['articleReference'] as int?,
            );
          })
          .toList(),
    );
  }
}
