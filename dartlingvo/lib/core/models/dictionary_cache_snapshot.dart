import 'dictionary.dart';
import 'dictionary_entry.dart';

class DictionaryCacheSnapshot {
  final Dictionary dictionary;
  final List<DictionaryEntry> entries;

  const DictionaryCacheSnapshot({
    required this.dictionary,
    required this.entries,
  });

  Map<String, dynamic> toJson() => {
        'dictionary': dictionary.toJson(),
        'entries': entries.map((entry) => entry.toJson()).toList(),
      };

  factory DictionaryCacheSnapshot.fromJson(Map<String, dynamic> json) {
    return DictionaryCacheSnapshot(
      dictionary: Dictionary.fromJson(json['dictionary'] as Map<String, dynamic>),
      entries: (json['entries'] as List<dynamic>)
          .map((entry) => DictionaryEntry.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }
}
