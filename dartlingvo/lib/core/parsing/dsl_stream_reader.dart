import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';
import '../models/dictionary_entry.dart';
import '../models/formatted_text.dart';
import 'lingvo_text_parser.dart';

enum _FileEncoding { utf8, utf16le, utf16be }

class DslStreamReader {
  final String dictionaryId;
  final String dictionaryName;

  DslStreamReader({required this.dictionaryId, required this.dictionaryName});

  Future<List<DictionaryEntry>> readAll(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final did = dictionaryId;
    final dn = dictionaryName;

    final jsonString = await Isolate.run(() => _dslParseInIsolate(bytes, did, dn));

    final list = jsonDecode(jsonString) as List;
    return list.map((e) => DictionaryEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<String> extractName(String filePath) async {
    final file = File(filePath);
    final raf = await file.open(mode: FileMode.read);
    final bytes = await raf.read(8192);
    await raf.close();
    final lines = _decodeLines(bytes);
    for (final line in lines) {
      if (line.startsWith('#NAME')) {
        final match = RegExp(r'#NAME\s+"([^"]*)"').firstMatch(line);
        if (match != null) return match.group(1)!;
      }
    }
    return 'Unnamed Dictionary';
  }
}

String _dslParseInIsolate(Uint8List bytes, String dictionaryId, String dictionaryName) {
  final lines = _decodeLines(bytes);
  final entries = _parseEntries(lines, dictionaryId, dictionaryName);
  return jsonEncode(entries.map((e) => e.toJson()).toList());
}

List<String> _decodeLines(Uint8List bytes) {
  if (bytes.length < 2) {
    return utf8.decode(bytes).split('\n');
  }

  _FileEncoding enc;
  int offset;

  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    enc = _FileEncoding.utf8;
    offset = 3;
  } else if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
    enc = _FileEncoding.utf16le;
    offset = 2;
  } else if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
    enc = _FileEncoding.utf16be;
    offset = 2;
  } else {
    enc = _FileEncoding.utf8;
    offset = 0;
  }

  if (enc == _FileEncoding.utf8) {
    return utf8.decode(bytes.sublist(offset)).split('\n');
  }

  final codeUnits = <int>[];
  final len = bytes.length;
  int i = offset;

  if (enc == _FileEncoding.utf16le) {
    while (i + 1 < len) {
      final cu = ByteData.view(bytes.buffer, bytes.offsetInBytes + i, 2).getUint16(0, Endian.little);
      if (cu == 0) break;
      codeUnits.add(cu);
      i += 2;
    }
  } else {
    while (i + 1 < len) {
      final cu = ByteData.view(bytes.buffer, bytes.offsetInBytes + i, 2).getUint16(0, Endian.big);
      if (cu == 0) break;
      codeUnits.add(cu);
      i += 2;
    }
  }

  return String.fromCharCodes(codeUnits).split('\n');
}

List<DictionaryEntry> _parseEntries(List<String> lines, String dictId, String dictName) {
  final entries = <DictionaryEntry>[];
  int i = 0;
  int entryIndex = 0;

  while (i < lines.length) {
    final rawLine = lines[i];
    final trimmed = rawLine.trim();

    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      i++;
      continue;
    }

    final tabIndex = trimmed.indexOf('\t');
    String word;
    String? inlineDef;

    if (tabIndex >= 0) {
      word = trimmed.substring(0, tabIndex);
      inlineDef = rawLine.substring(rawLine.indexOf('\t'));
    } else {
      word = trimmed;
    }
    i++;

    final defLines = <String>[];
    if (inlineDef != null) {
      defLines.add(inlineDef);
    }

    while (i < lines.length) {
      final bodyLine = lines[i];
      if (bodyLine.trim().isEmpty) {
        i++;
        continue;
      }
      if (bodyLine.startsWith('\t')) {
        defLines.add(bodyLine);
        i++;
      } else if (bodyLine.trimLeft().startsWith('\t')) {
        defLines.add(bodyLine.trimLeft());
        i++;
      } else {
        break;
      }
    }

    if (word.isNotEmpty) {
      entries.add(DictionaryEntry(
        word: word,
        definitions: _parseDefinitions(defLines),
        dictionaryId: dictId,
        dictionaryName: dictName,
        index: entryIndex++,
      ));
    }
  }

  return entries;
}

List<FormattedText> _parseDefinitions(List<String> defLines) {
  if (defLines.isEmpty) {
    return [FormattedText(segments: [const TextSegment(type: TextSegmentType.plain, text: '')])];
  }

  final combined = defLines.join('\n');
  return parseLingvoFormattedText(combined);
}


