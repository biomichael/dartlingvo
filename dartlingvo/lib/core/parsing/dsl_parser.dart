import '../models/dictionary_entry.dart';
import '../models/formatted_text.dart';
import 'lingvo_text_parser.dart';

class DslParser {
  static const _namePattern = '#NAME\t';

  static String extractNameFromHeader(String dslText) {
    for (final line in dslText.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith(_namePattern)) {
        final value = trimmed.substring(_namePattern.length).trim();
        return value.replaceAll('"', '');
      }
    }
    return 'Unnamed Dictionary';
  }
  String? _currentDictionaryId;
  String? _currentDictionaryName;

  DslParser({String? dictionaryId, String? dictionaryName}) {
    _currentDictionaryId = dictionaryId;
    _currentDictionaryName = dictionaryName;
  }

  void setDictionary(String id, String name) {
    _currentDictionaryId = id;
    _currentDictionaryName = name;
  }

  List<DictionaryEntry> parseDsl(String dslText) {
    final entries = <DictionaryEntry>[];
    final lines = dslText.split('\n');
    var i = 0;
    var entryIndex = 0;

    while (i < lines.length) {
      final rawLine = lines[i];
      final trimmed = rawLine.trim();

      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        i++;
        continue;
      }

      final tabIndex = rawLine.indexOf('\t');
      final word = tabIndex >= 0 ? rawLine.substring(0, tabIndex).trim() : trimmed;
      final defLines = <String>[];

      if (tabIndex >= 0 && tabIndex + 1 < rawLine.length) {
        defLines.add(rawLine.substring(tabIndex + 1));
      }
      i++;

      while (i < lines.length) {
        final bodyLine = lines[i];
        final bodyTrimmed = bodyLine.trim();

        if (bodyTrimmed.isEmpty) {
          if (defLines.isNotEmpty) {
            defLines.add('');
          }
          i++;
          continue;
        }

        if (bodyLine.startsWith('\t')) {
          defLines.add(bodyLine.substring(1));
          i++;
          continue;
        }

        if (bodyLine.startsWith(' ')) {
          final stripped = bodyLine.trimLeft();
          if (stripped.startsWith('\t')) {
            defLines.add(stripped.substring(1));
            i++;
            continue;
          }
        }

        break;
      }

      if (word.isNotEmpty) {
        entries.add(DictionaryEntry(
          word: word,
          definitions: _parseDefinitions(defLines),
          dictionaryId: _currentDictionaryId ?? '',
          dictionaryName: _currentDictionaryName ?? '',
          index: entryIndex++,
        ));
      }
    }

    return entries;
  }

  List<FormattedText> _parseDefinitions(List<String> defLines) {
    final text = defLines.join('\n').trim();
    if (text.isEmpty) {
      return [
        FormattedText(
          segments: [
            const TextSegment(type: TextSegmentType.plain, text: ''),
          ],
        ),
      ];
    }

    return parseLingvoFormattedText(text);
  }
}
