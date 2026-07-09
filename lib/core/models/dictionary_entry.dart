import 'formatted_text.dart';

class DictionaryEntry {
  final String word;
  final List<FormattedText> definitions;
  final String dictionaryId;
  final String dictionaryName;
  final int index;

  const DictionaryEntry({
    required this.word,
    required this.definitions,
    required this.dictionaryId,
    required this.dictionaryName,
    this.index = 0,
  });

  bool get isEmpty => word.isEmpty && definitions.isEmpty;

  Map<String, dynamic> toJson() => {
        'word': word,
        'definitions': definitions.map((d) => d.toJson()).toList(),
        'dictionaryId': dictionaryId,
        'dictionaryName': dictionaryName,
        'index': index,
      };

  factory DictionaryEntry.fromJson(Map<String, dynamic> json) =>
      DictionaryEntry(
        word: json['word'] as String,
        definitions: (json['definitions'] as List)
            .map((d) => FormattedText.fromJson(d as Map<String, dynamic>))
            .toList(),
        dictionaryId: json['dictionaryId'] as String,
        dictionaryName: json['dictionaryName'] as String,
        index: json['index'] as int? ?? 0,
      );
}

class WordIndexEntry {
  final String word;
  final String dictionaryId;
  final String dictionaryName;
  final int entryIndex;

  const WordIndexEntry({
    required this.word,
    required this.dictionaryId,
    required this.dictionaryName,
    this.entryIndex = 0,
  });

  String get lookupKey => '$dictionaryId:$word';

  Map<String, dynamic> toJson() => {
        'word': word,
        'dictionaryId': dictionaryId,
        'dictionaryName': dictionaryName,
        'entryIndex': entryIndex,
      };

  factory WordIndexEntry.fromJson(Map<String, dynamic> json) =>
      WordIndexEntry(
        word: json['word'] as String,
        dictionaryId: json['dictionaryId'] as String,
        dictionaryName: json['dictionaryName'] as String,
        entryIndex: json['entryIndex'] as int? ?? 0,
      );
}
