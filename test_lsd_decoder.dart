import 'dart:io';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:dartlingvo/core/parsing/lsd_decoder_dart.dart';
import 'package:dartlingvo/core/models/dictionary_entry.dart';
import 'package:dartlingvo/core/models/formatted_text.dart';

void main() async {
  final path = r'C:\Users\MZDEV\Downloads\Dictionaries\EnglishEtymology.lsd';
  final data = File(path).readAsBytesSync();
  print('File size: ${data.length} bytes');
  
  final stopwatch = Stopwatch()..start();
  
  final jsonString = await Isolate.run(() => _decodeLsd(data));
  
  stopwatch.stop();
  
  final map = jsonDecode(jsonString) as Map<String, dynamic>;
  final name = map['name'] as String;
  final entries = (map['entries'] as List)
      .map((e) => DictionaryEntry.fromJson(e as Map<String, dynamic>))
      .toList();
  
  print('Name: $name');
  print('Entries: ${entries.length}');
  print('Elapsed: ${stopwatch.elapsedMilliseconds}ms');
  
  print('\n=== First 5 entries ===');
  for (int i = 0; i < 5 && i < entries.length; i++) {
    final e = entries[i];
    final text = e.definitions.isNotEmpty 
        ? e.definitions.first.segments.first.text 
        : '';
    print('${e.word}: ${text.substring(0, text.length > 120 ? 120 : text.length)}');
  }
  
  print('\n=== Entry 0 full ===');
  if (entries.isNotEmpty) {
    final e = entries[0];
    final text = e.definitions.isNotEmpty 
        ? e.definitions.first.segments.first.text 
        : '';
    print('Word: ${e.word}');
    print('Text length: ${text.length}');
    print('First 200 chars: "${text.substring(0, text.length > 200 ? 200 : text.length)}"');
    
    final units = text.codeUnits.toList();
    final ascii = units.where((c) => c >= 32 && c <= 126).length;
    final ctrl = units.where((c) => c < 32 && c != 10 && c != 13 && c != 9).length;
    print('ASCII printable: $ascii / ${units.length}');
    print('Control chars: $ctrl');
  }
}

// Copy of _lsdDecodeInIsolate logic from lsdfile
String _decodeLsd(Uint8List data) {
  final bs = BitStream(data);
  final header = LsdHeader.fromStream(bs);

  if (header.magic != 'LingVo') {
    throw Exception('Not a valid LSD file: magic "${header.magic}"');
  }

  final nameLen = bs.readByte();
  final name = bs.readUnicode(nameLen, false);
  final firstLen = bs.readByte();
  bs.readUnicode(firstLen, false);
  final lastLen = bs.readByte();
  bs.readUnicode(lastLen, false);
  final capitalsLen = reverse32(bs.readInt());
  bs.readUnicode(capitalsLen, false);

  if (header.version > 0x120000) {
    final iconSize = reverse16(bs.readWord());
    bs.bytePos += iconSize;
  }

  if (header.version > 0x140000) {
    bs.readInt();
  }
  int pagesEnd = reverse32(bs.readInt());
  if (header.version > 0x120000) {
    bs.readInt();
  } else {
    pagesEnd = data.length;
  }
  if (header.version > 0x140000) {
    bs.readInt();
    bs.readInt();
  }

  final hi = header.hiVersion;
  final ver = header.version;
  Decoder? decoder;
  if (hi == 0x11 || hi == 0x12) {
    decoder = UserDictionaryDecoder(bs);
  } else if (hi == 0x13) {
    decoder = SystemDictionaryDecoder13(bs);
  } else if (hi == 0x14) {
    if (ver == 0x142001) decoder = UserDictionaryDecoder(bs);
    else if (ver == 0x145001 || ver == 0x141004) decoder = SystemDictionaryDecoder14(bs);
  } else if (hi == 0x15) {
    if (ver == 0x152001) decoder = UserDictionaryDecoder(bs);
    else if (ver == 0x151005) {
      int key = 0x7f;
      for (int i = header.dictionaryEncoderOffset; i < header.articlesOffset; i++) {
        final byte = data[i];
        data[i] = byte ^ key;
        key = xorPad[byte];
      }
      decoder = SystemDictionaryDecoder14(bs);
    } else if (ver == 0x155001) decoder = AbbreviationDictionaryDecoder(bs);
  }

  if (decoder == null) throw Exception('Unsupported LSD version: 0x${ver.toRadixString(16)}');

  bs.seek(header.dictionaryEncoderOffset);
  decoder.read();

  final headings = <ArticleHeadingInfo>[];
  final pagesCount = (pagesEnd - header.pagesOffset) ~/ 512;
  print('Pages count: $pagesCount');
  for (int page = 0; page < pagesCount; page++) {
    bs.seek(header.pagesOffset + 512 * page);
    final pageObj = CachePage.read(bs);
    if (!pageObj.isLeaf) continue;

    String prefix = '';
    for (int idx = 0; idx < pageObj.headingsCount; idx++) {
      final prefixLen = decoder.decodePrefixLen();
      final postfixLen = decoder.decodePostfixLen();
      final reference = decoder.readReference(decoder.huffman1Number);

      // Debug first page headings - do decode separately for the first 5
      if (page == 0 && idx < 5) {
        // Re-seek and re-read for debug (save and restore position)
        // Just show the raw values without consuming extra bits
        print('  heading[$idx]: prefixLen=$prefixLen postfixLen=$postfixLen ref=$reference prefixChars=${prefix.length}');
      }

      final p = prefixLen > 0 && prefix.length >= prefixLen
          ? prefix.substring(0, prefixLen) : '';
      final heading = postfixLen > 0 ? decoder.decodeHeading(postfixLen) : '';
      final fullWord = p + heading;

      if (page == 0 && idx < 5) {
        print('    result: p="$p" heading="$heading" full="$fullWord"');
        print('    heading codes: ${heading.runes.toList()}');
      }

      final info = reference < 0
          ? ArticleHeadingInfo([fullWord], 0)
          : ArticleHeadingInfo([fullWord], reference);
      headings.add(info);
      if (info.words.isNotEmpty) prefix = info.words.last;
    }
  }

  final articles = <String>[];
  ArticleHeadingInfo? prev;
  for (int i = 0; i < headings.length; i++) {
    final h = headings[i];
    if (i < headings.length - 1) {
      h.nextReference = headings[i + 1].reference;
    } else {
      h.nextReference = header.pagesOffset - header.articlesOffset;
    }

    if (prev != null && prev.reference == h.reference) {
      prev.words.addAll(h.words);
      articles.add('');
      continue;
    }

    String article = '';
    if (h.nextReference != 0) {
      bs.seek(header.articlesOffset + h.reference);
      if (header.version == 0x151005) {
        int key = 0x7f;
        for (int j = header.articlesOffset + h.reference;
            j < header.articlesOffset + h.nextReference;
            j++) {
          final byte = data[j];
          data[j] = byte ^ key;
          key = xorPad[byte];
        }
      }

      int size = bs.readBits(16);
      if (size == 0xFFFF) {
        size = bs.readBits(32);
      }
      
      // Debug first few articles
      if (i < 5) {
        print('  article[$i]: ref=${h.reference} nextRef=${h.nextReference} size=$size bytePos=${bs.bytePos} bitPos=${bs.bitPos}');
      }
      
      article = decoder.decodeArticle(size);
      
      if (i < 5) {
        print('    article length=${article.length} first 50 chars="${article.substring(0, article.length > 50 ? 50 : article.length)}"');
        if (article.length > 0) {
          print('    first 50 code units: ${article.codeUnits.take(50).toList()}');
        }
      }
    }
    articles.add(article);
    prev = h;
  }

  final entries = <DictionaryEntry>[];
  final Map<int, List<FormattedText>> articleCache = {};
  for (int i = 0; i < headings.length; i++) {
    final heading = headings[i];
    if (i >= articles.length) break;
    final articleText = articles[i];
    final definitions = articleCache.putIfAbsent(i, () => _parseLsdDslArticle(articleText));
    for (final word in heading.words) {
      entries.add(DictionaryEntry(
        word: word,
        definitions: definitions,
        dictionaryId: header.entriesCount.toString(),
        dictionaryName: name,
        index: entries.length,
      ));
    }
  }

  return jsonEncode({'name': name, 'entries': entries.map((e) => e.toJson()).toList()});
}

// Copy of _parseLsdDslArticle
List<FormattedText> _parseLsdDslArticle(String text) {
  if (text.isEmpty) {
    return [FormattedText(segments: [const TextSegment(type: TextSegmentType.plain, text: '')])];
  }

  final result = <FormattedText>[];
  final len = text.length;
  int pos = 0;
  StringBuffer? block;

  while (pos < len) {
    final lineEnd = text.indexOf('\n', pos);
    final lineLimit = lineEnd == -1 ? len : lineEnd;

    int firstNonSpace = pos;
    while (firstNonSpace < lineLimit &&
        (text[firstNonSpace] == ' ' || text[firstNonSpace] == '\t')) {
      firstNonSpace++;
    }

    final isMarker = firstNonSpace < lineLimit &&
        text[firstNonSpace] == '[' &&
        ((lineLimit - firstNonSpace >= 4 &&
            text[firstNonSpace + 1] == 'm' &&
            (text[firstNonSpace + 2] == '1' || text[firstNonSpace + 2] == '2') &&
            text[firstNonSpace + 3] == ']'));

    if (isMarker) {
      if (block != null) {
        final blockText = block.toString().trim();
        if (blockText.isNotEmpty) {
          final segments = _parseLsdTags(blockText);
          if (segments.isNotEmpty) result.add(FormattedText(segments: segments));
        }
      }
      block = StringBuffer(text.substring(pos, lineLimit));
    } else {
      if (block == null) block = StringBuffer();
      if (block.length > 0) block.write('\n');
      block.write(text.substring(pos, lineLimit));
    }

    pos = lineEnd == -1 ? len : lineEnd + 1;
  }

  if (block != null) {
    final blockText = block.toString().trim();
    if (blockText.isNotEmpty) {
      final segments = _parseLsdTags(blockText);
      if (segments.isNotEmpty) result.add(FormattedText(segments: segments));
    }
  }

  if (result.isEmpty) {
    result.add(FormattedText(segments: [TextSegment(type: TextSegmentType.plain, text: text)]));
  }

  return result;
}

// Copy of _parseLsdTags
List<TextSegment> _parseLsdTags(String text) {
  final segments = <TextSegment>[];
  final stack = <TextSegmentType>[];
  int i = 0;

  while (i < text.length) {
    if (text[i] == '[') {
      final closeBracket = text.indexOf(']', i);
      if (closeBracket == -1) {
        _appendLsdPlain(segments, text.substring(i), stack);
        break;
      }

      final tag = text.substring(i + 1, closeBracket);
      final isClosing = tag.startsWith('/');

      if (isClosing) {
          final tagName = tag.substring(1).toLowerCase();
          if (['b', 'i', 'ref', 'ex', 'm1', 'm2', 'p', '*'].contains(tagName)) {
            if (stack.isNotEmpty) stack.removeLast();
          }
          i = closeBracket + 1;
          continue;
        } else {
          final tagName = tag.toLowerCase();
          if (tagName == 'b') {
            stack.add(TextSegmentType.bold);
          } else if (tagName == 'i') {
            stack.add(TextSegmentType.italic);
          } else if (tagName == 'ref') {
            stack.add(TextSegmentType.reference);
          } else if (tagName == 'ex') {
            stack.add(TextSegmentType.example);
          }
          i = closeBracket + 1;
          continue;
        }
    }

    final nextBracket = text.indexOf('[', i);
    if (nextBracket == -1) {
      _appendLsdPlain(segments, text.substring(i), stack);
      break;
    }

    _appendLsdPlain(segments, text.substring(i, nextBracket), stack);
    i = nextBracket;
  }

  return segments;
}

void _appendLsdPlain(List<TextSegment> segments, String text, List<TextSegmentType> stack) {
  if (text.isEmpty) return;
  final effectiveType = stack.isNotEmpty ? stack.last : TextSegmentType.plain;
  if (segments.isNotEmpty && segments.last.type == effectiveType && effectiveType != TextSegmentType.reference) {
    segments.last = TextSegment(type: effectiveType, text: segments.last.text + text);
  } else {
    segments.add(TextSegment(type: effectiveType, text: text));
  }
}
