import 'dart:io';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'lib/core/parsing/lsd_decoder_dart.dart' as decoder;

// Copy the key functions to instrument
void main() async {
  final path = r'C:\Users\MZDEV\Downloads\Dictionaries\EnglishEtymology.lsd';
  final data = await File(path).readAsBytes();
  final sw = Stopwatch()..start();
  
  final jsonString = await Isolate.run(() => _lsdDecodeInIsolate(data));
  
  sw.stop();
  final map = jsonDecode(jsonString) as Map<String, dynamic>;
  final entries = (map['entries'] as List).length;
  print('Done: $entries entries in ${sw.elapsed}');
}

String _lsdDecodeInIsolate(Uint8List data) {
  final sw = Stopwatch()..start();
  
  final bs = decoder.BitStream(data);
  final header = _readHeader(bs);
  
  if (header['magic'] != 'LingVo') {
    throw Exception('Not a valid LSD file');
  }

  // Read name, first, last, capitals
  final nameLen = bs.readByte();
  final name = bs.readUnicode(nameLen, false);
  final firstLen = bs.readByte();
  bs.readUnicode(firstLen, false);
  final lastLen = bs.readByte();
  bs.readUnicode(lastLen, false);
  final capitalsLen = _rev32(bs.readInt());
  bs.readUnicode(capitalsLen, false);

  int pagesEnd;
  if (header['version'] > 0x120000) {
    final iconSize = _rev16(bs.readWord());
    bs.readBytes(iconSize);
  }
  if (header['version'] > 0x140000) {
    bs.readInt();
  }
  pagesEnd = _rev32(bs.readInt());
  if (header['version'] > 0x120000) {
    bs.readInt();
  } else {
    pagesEnd = data.length;
  }
  if (header['version'] > 0x140000) {
    bs.readInt();
    bs.readInt();
  }

  final hi = header['version'] >> 16;
  // hi == 0x13 -> SystemDictionaryDecoder13
  final dec = _SystemDictionaryDecoder13(bs);
  
  bs.seek(header['encoderOffset']);
  final t0 = sw.elapsed;
  dec.read();
  final t1 = sw.elapsed;
  print('Isolate: decoder read took ${t1-t0}');
  
  // Read headings
  final headings = <Map>[];
  final pagesCount = (pagesEnd - header['pagesOffset']) ~/ 512;
  for (int page = 0; page < pagesCount; page++) {
    bs.seek(header['pagesOffset'] + 512 * page);
    final pageObj = _CachePage.read(bs);
    if (!pageObj.isLeaf) continue;
    
    String prefix = '';
    for (int idx = 0; idx < pageObj.headingsCount; idx++) {
      final prefixLen = dec.decodePrefixLen();
      final postfixLen = dec.decodePostfixLen();
      final reference = dec.readReference(dec.huffman1Number);
      
      final p = prefixLen > 0 && prefix.length >= prefixLen
          ? prefix.substring(0, prefixLen)
          : '';
      final heading = postfixLen > 0 ? dec.decodeHeading(postfixLen) : '';
      final fullWord = p + heading;
      
      headings.add({'words': [fullWord], 'reference': reference < 0 ? 0 : reference});
      if (fullWord.isNotEmpty) prefix = fullWord;
    }
  }
  final t2 = sw.elapsed;
  print('Isolate: heading read (${headings.length} headings, $pagesCount pages) took ${t2-t1}');
  print('Isolate: total so far: $t2');
  
  // Decode articles
  int? prevRef;
  final articles = <String>[];
  int articleDecodeTime = 0;
  int parseTime = 0;
  
  for (int i = 0; i < headings.length; i++) {
    final h = headings[i];
    int nextRef;
    if (i < headings.length - 1) {
      nextRef = headings[i + 1]['reference'];
    } else {
      nextRef = header['pagesOffset'] - header['articlesOffset'];
    }
    
    if (prevRef != null && prevRef == h['reference']) {
      articles.add('');
      continue;
    }
    
    String article = '';
    if (nextRef != 0) {
      bs.seek(header['articlesOffset'] + h['reference']);
      int size = bs.readBits(16);
      if (size == 0xFFFF) {
        size = bs.readBits(32);
      }
      final tDecode = Stopwatch()..start();
      article = dec.decodeArticle(size);
      tDecode.stop();
      articleDecodeTime += tDecode.elapsedMicroseconds;
    }
    articles.add(article);
    prevRef = h['reference'];
  }
  final t3 = sw.elapsed;
  print('Isolate: article decode ($articleDecodeTime us) took ${t3-t2}');
  
  // Parse articles
  for (int i = 0; i < headings.length && i < articles.length; i++) {
    final articleText = articles[i];
    if (articleText.isEmpty) continue;
    final tParse = Stopwatch()..start();
    _parseLsdDslArticle(articleText);
    tParse.stop();
    parseTime += tParse.elapsedMicroseconds;
  }
  final t4 = sw.elapsed;
  print('Isolate: article parse ($parseTime us) took ${t4-t3}');
  print('Isolate: total: $t4');
  
  final entries = <Map>[];
  for (int i = 0; i < headings.length; i++) {
    if (i >= articles.length) break;
    for (final word in headings[i]['words']) {
      entries.add({'word': word, 'dictionaryName': name, 'index': entries.length});
    }
  }
  
  return jsonEncode({'name': name, 'entries': entries});
}

Map _readHeader(BitStream bs) {
  final rawMagic = bs.readBytes(8);
  final magic = String.fromCharCodes(rawMagic).replaceAll('\x00', '');
  return {
    'magic': magic,
    'version': _rev32(bs.readInt()),
    'encoderOffset': _rev32(bs.readInt()), // skip fields
    'articlesOffset': _rev32(bs.readInt()),
    'pagesOffset': _rev32(bs.readInt()),
  };
}

int _rev32(int v) {
  final bytes = Uint8List(4);
  bytes[0] = v & 0xFF;
  bytes[1] = (v >> 8) & 0xFF;
  bytes[2] = (v >> 16) & 0xFF;
  bytes[3] = (v >> 24) & 0xFF;
  return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
}

int _rev16(int v) {
  final bytes = Uint8List(2);
  bytes[0] = v & 0xFF;
  bytes[1] = (v >> 8) & 0xFF;
  return (bytes[0] << 8) | bytes[1];
}

// Minimal copy of needed classes
class BitStream {
  final Uint8List data;
  int bytePos;
  int bitPos;
  BitStream(this.data) : bytePos = 0, bitPos = 0;
  
  int get length => data.length;
  
  bool seek(int pos) { bytePos = pos; bitPos = 0; return bytePos < length; }
  
  Uint8List readBytes(int count) {
    final result = Uint8List(count);
    result.setRange(0, count, data, bytePos);
    bytePos += count;
    return result;
  }
  
  int readByte() { final b = data[bytePos]; bytePos++; bitPos = 0; return b; }
  
  int readWord() {
    final hi = data[bytePos];
    final lo = data[bytePos + 1];
    bytePos += 2;
    bitPos = 0;
    return (hi << 8) | lo;
  }
  
  int readInt() {
    final b0 = data[bytePos];
    final b1 = data[bytePos + 1];
    final b2 = data[bytePos + 2];
    final b3 = data[bytePos + 3];
    bytePos += 4;
    bitPos = 0;
    return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
  }
  
  int readBit() {
    final b = data[bytePos];
    final bit = (b >> (7 - bitPos)) & 1;
    if (bitPos == 7) {
      bytePos++;
      bitPos = 0;
    } else {
      bitPos++;
    }
    return bit;
  }
  
  int readBits(int count) {
    if (count > 32) throw Exception('Too many bits: $count');
    int result = 0;
    for (int i = 0; i < count; i++) {
      result = (result << 1) | readBit();
    }
    return result;
  }
  
  String readUnicode(int size, [bool bigEndian = true]) {
    final sb = StringBuffer();
    for (int i = 0; i < size; i++) {
      int ch = readWord();
      if (!bigEndian) ch = _rev16(ch);
      sb.writeCharCode(ch);
    }
    return sb.toString();
  }
}

int bitLength(int num) {
  int res = 1;
  num >>= 1;
  while (num != 0) {
    res++;
    num >>= 1;
  }
  return res;
}

class _CachePage {
  final bool isLeaf;
  final int headingsCount;
  _CachePage(this.isLeaf, this.headingsCount);
  
  static _CachePage read(BitStream bs) {
    final isLeaf = bs.readBit() == 1;
    bs.readBits(16); bs.readBits(16); bs.readBits(16); bs.readBits(16);
    final headingsCount = bs.readBits(16);
    bs.toNearestByte();
    return _CachePage(isLeaf, headingsCount);
  }
}

extension on BitStream {
  void toNearestByte() {
    if (bitPos != 0) {
      bitPos = 0;
      bytePos++;
    }
  }
}

class _LenTable {
  final BitStream _bs;
  int count = 0;
  int bitsPerLen = 0;
  int idxBitSize = 0;
  late final List<int> symIdxToNodeIdx;
  final List<Map> nodes = [];
  int _nextNodePosition = 0;
  
  _LenTable(this._bs) {
    count = _bs.readBits(32);
    bitsPerLen = _bs.readBits(8);
    idxBitSize = bitLength(count);
    symIdxToNodeIdx = List.filled(count, -1);
    for (int i = 0; i < count - 1; i++) {
      nodes.add({'l': 0, 'r': 0, 'p': -1, 'w': -1});
    }
    final rootIdx = nodes.length - 1;
    for (int i = 0; i < count; i++) {
      final symIdx = _bs.readBits(idxBitSize);
      final length = _bs.readBits(bitsPerLen);
      _placeSymIdx(symIdx, rootIdx, length);
    }
  }
  
  bool _placeSymIdx(int symIdx, int nodeIdx, int size) {
    if (size == 1) {
      if (nodes[nodeIdx]['l'] == 0) {
        nodes[nodeIdx]['l'] = -1 - symIdx;
        symIdxToNodeIdx[symIdx] = nodeIdx;
        return true;
      }
      if (nodes[nodeIdx]['r'] == 0) {
        nodes[nodeIdx]['r'] = -1 - symIdx;
        symIdxToNodeIdx[symIdx] = nodeIdx;
        return true;
      }
      return false;
    }
    
    if (nodes[nodeIdx]['l'] == 0) {
      nodes.add({'l': 0, 'r': 0, 'p': nodeIdx, 'w': -1});
      _nextNodePosition++;
      nodes[nodeIdx]['l'] = _nextNodePosition;
    }
    
    if (nodes[nodeIdx]['l'] > 0) {
      if (_placeSymIdx(symIdx, nodes[nodeIdx]['l'] - 1, size - 1)) return true;
    }
    
    if (nodes[nodeIdx]['r'] == 0) {
      nodes.add({'l': 0, 'r': 0, 'p': nodeIdx, 'w': -1});
      _nextNodePosition++;
      nodes[nodeIdx]['r'] = _nextNodePosition;
    }
    
    if (nodes[nodeIdx]['r'] > 0) {
      if (_placeSymIdx(symIdx, nodes[nodeIdx]['r'] - 1, size - 1)) return true;
    }
    
    return false;
  }
  
  int decode() {
    int node = nodes.length - 1;
    while (true) {
      final bit = _bs.readBit();
      if (bit == 1) {
        if (nodes[node]['r'] < 0) return -1 - nodes[node]['r'];
        node = nodes[node]['r'] - 1;
      } else {
        if (nodes[node]['l'] < 0) return -1 - nodes[node]['l'];
        node = nodes[node]['l'] - 1;
      }
    }
  }
}

class _SystemDictionaryDecoder13 {
  final BitStream bs;
  String prefix = '';
  List<int> articleSymbols = [];
  List<int> headingSymbols = [];
  late _LenTable ltArticles;
  late _LenTable ltHeadings;
  late _LenTable ltPrefixLengths;
  late _LenTable ltPostfixLengths;
  int huffman1Number = 0;
  int huffman2Number = 0;
  
  _SystemDictionaryDecoder13(this.bs);
  
  void read() {
    final prefixLen = bs.readInt();
    prefix = bs.readUnicode(prefixLen);
    articleSymbols = bs.readSymbols();
    headingSymbols = bs.readSymbols();
    ltArticles = _LenTable(bs);
    ltHeadings = _LenTable(bs);
    ltPrefixLengths = _LenTable(bs);
    ltPostfixLengths = _LenTable(bs);
    huffman1Number = bs.readBits(32);
    huffman2Number = bs.readBits(32);
  }
  
  int decodePrefixLen() => ltPrefixLengths.decode();
  int decodePostfixLen() => ltPostfixLengths.decode();
  
  int readReference(int huffmanNumber) {
    final code = bs.readBits(2);
    if (code == 3) {
      bs.readBits(32);
      return -1;
    }
    final bits = bitLength(huffmanNumber);
    return (code << (bits - 2)) | bs.readBits(bits - 2);
  }
  
  String decodeHeading(int size) {
    final codes = <int>[];
    for (int i = 0; i < size; i++) {
      codes.add(headingSymbols[ltHeadings.decode()]);
    }
    return String.fromCharCodes(codes);
  }
  
  String decodeArticle(int size) {
    final codes = <int>[];
    while (codes.length < size) {
      final sym = articleSymbols[ltArticles.decode()];
      if (sym <= 0x80) {
        if (sym <= 0x3F) {
          final startIdx = bs.readBits(bitLength(prefix.length));
          final len = sym + 3;
          for (int j = startIdx; j < startIdx + len && j < prefix.length; j++) {
            codes.add(prefix.codeUnitAt(j));
          }
        } else {
          final startIdx = bs.readBits(bitLength(size));
          final len = sym - 0x3d;
          for (int j = startIdx; j < startIdx + len && j < codes.length; j++) {
            codes.add(codes[j]);
          }
        }
      } else {
        codes.add(sym - 0x80);
      }
    }
    return String.fromCharCodes(codes);
  }
}

extension on BitStream {
  List<int> readSymbols() {
    final size = readBits(32);
    final bitsPerSymbol = readBits(8);
    final symbols = <int>[];
    for (int i = 0; i < size; i++) {
      symbols.add(readBits(bitsPerSymbol));
    }
    return symbols;
  }
}

List<Map> _parseLsdDslArticle(String text) {
  if (text.isEmpty) return [];
  text = text.replaceAll('\n', '\n\t');
  text = '\t$text';
  final lines = text.split('\n');
  final blocks = <String>[];
  String current = '';
  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('[m1]') || trimmed.startsWith('[m2]')) {
      if (current.isNotEmpty) blocks.add(current.trim());
      current = line;
    } else {
      if (current.isNotEmpty) current += '\n';
      current += line;
    }
  }
  if (current.isNotEmpty) blocks.add(current.trim());
  return blocks.map((b) => <String, dynamic>{'text': b}).toList();
}
