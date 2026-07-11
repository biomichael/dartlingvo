import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io';
import '../models/dictionary_entry.dart';
import '../models/formatted_text.dart';
import 'lingvo_text_parser.dart';

int bitLength(int num) {
  int res = 1;
  num >>= 1;
  while (num != 0) {
    res++;
    num >>= 1;
  }
  return res;
}

int reverse32(int v) {
  final bytes = Uint8List(4);
  bytes[0] = v & 0xFF;
  bytes[1] = (v >> 8) & 0xFF;
  bytes[2] = (v >> 16) & 0xFF;
  bytes[3] = (v >> 24) & 0xFF;
  return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
}

int reverse16(int v) {
  final bytes = Uint8List(2);
  bytes[0] = v & 0xFF;
  bytes[1] = (v >> 8) & 0xFF;
  return (bytes[0] << 8) | bytes[1];
}

class BitStream {
  final Uint8List data;
  int bytePos;
  int bitPos;

  BitStream(this.data) : bytePos = 0, bitPos = 0;

  int get length => data.length;

  bool seek(int pos) {
    bytePos = pos;
    bitPos = 0;
    return bytePos < length;
  }

  Uint8List readBytes(int count) {
    final result = Uint8List(count);
    result.setRange(0, count, data, bytePos);
    bytePos += count;
    return result;
  }

  int readByte() {
    final b = data[bytePos];
    bytePos++;
    bitPos = 0;
    return b;
  }

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
    if (count == 0) return 0;
    int result = 0;
    // Finish current byte
    if (bitPos > 0) {
      final bitsHere = 8 - bitPos;
      if (count <= bitsHere) {
        final shift = bitsHere - count;
        result = (data[bytePos] >> shift) & ((1 << count) - 1);
        bitPos += count;
        if (bitPos == 8) { bytePos++; bitPos = 0; }
        return result;
      }
      result = data[bytePos] & ((1 << bitsHere) - 1);
      count -= bitsHere;
      bytePos++;
      bitPos = 0;
    }
    // Whole bytes
    while (count >= 8) {
      result = (result << 8) | data[bytePos];
      bytePos++;
      count -= 8;
    }
    // Remaining bits
    if (count > 0) {
      final shift = 8 - count;
      result = (result << count) | (data[bytePos] >> shift);
      bitPos = count;
    }
    return result;
  }

  void toNearestByte() {
    if (bitPos != 0) {
      bitPos = 0;
      bytePos++;
    }
  }

  List<int> readSymbols() {
    final size = readBits(32);
    final bitsPerSymbol = readBits(8);
    final symbols = <int>[];
    for (int i = 0; i < size; i++) {
      symbols.add(readBits(bitsPerSymbol));
    }
    return symbols;
  }

  String readUnicode(int size, [bool bigEndian = true]) {
    final sb = StringBuffer();
    for (int i = 0; i < size; i++) {
      int ch = readWord();
      if (!bigEndian) ch = reverse16(ch);
      sb.writeCharCode(ch);
    }
    return sb.toString();
  }

  int readSome(int length) {
    if (length == 1) return readByte();
    if (length == 2) return readWord();
    if (length == 4) return readInt();
    throw Exception('Invalid read length: $length');
  }
}

class HuffmanNode {
  int left;
  int right;
  int parent;
  int weight;

  HuffmanNode(this.left, this.right, this.parent, this.weight);
}

class LenTable {
  final BitStream _bs;
  int count = 0;
  int bitsPerLen = 0;
  int idxBitSize = 0;
  late final List<int> symIdxToNodeIdx;
  late final List<HuffmanNode> nodes;
  int _nextNodePosition = 0;

  LenTable(this._bs) {
    count = _bs.readBits(32);
    bitsPerLen = _bs.readBits(8);
    idxBitSize = bitLength(count);
    symIdxToNodeIdx = List.filled(count, -1);
    nodes = List.generate(count - 1, (_) => HuffmanNode(0, 0, -1, -1));
    final rootIdx = nodes.length - 1;
    for (int i = 0; i < count; i++) {
      final symIdx = _bs.readBits(idxBitSize);
      final length = _bs.readBits(bitsPerLen);
      _placeSymIdx(symIdx, rootIdx, length);
    }
  }

  bool _placeSymIdx(int symIdx, int nodeIdx, int size) {
    if (size == 1) {
      if (nodes[nodeIdx].left == 0) {
        nodes[nodeIdx].left = -1 - symIdx;
        symIdxToNodeIdx[symIdx] = nodeIdx;
        return true;
      }
      if (nodes[nodeIdx].right == 0) {
        nodes[nodeIdx].right = -1 - symIdx;
        symIdxToNodeIdx[symIdx] = nodeIdx;
        return true;
      }
      return false;
    }

    if (nodes[nodeIdx].left == 0) {
      nodes[_nextNodePosition] = HuffmanNode(0, 0, nodeIdx, -1);
      _nextNodePosition++;
      nodes[nodeIdx].left = _nextNodePosition;
    }

    if (nodes[nodeIdx].left > 0) {
      if (_placeSymIdx(symIdx, nodes[nodeIdx].left - 1, size - 1)) return true;
    }

    if (nodes[nodeIdx].right == 0) {
      nodes[_nextNodePosition] = HuffmanNode(0, 0, nodeIdx, -1);
      _nextNodePosition++;
      nodes[nodeIdx].right = _nextNodePosition;
    }

    if (nodes[nodeIdx].right > 0) {
      if (_placeSymIdx(symIdx, nodes[nodeIdx].right - 1, size - 1)) return true;
    }

    return false;
  }

  int decode() {
    int node = nodes.length - 1;
    final d = _bs.data;
    while (true) {
      final b = d[_bs.bytePos];
      final bit = (b >> (7 - _bs.bitPos)) & 1;
      if (_bs.bitPos == 7) {
        _bs.bytePos++;
        _bs.bitPos = 0;
      } else {
        _bs.bitPos++;
      }
      if (bit == 1) {
        if (nodes[node].right < 0) return -1 - nodes[node].right;
        node = nodes[node].right - 1;
      } else {
        if (nodes[node].left < 0) return -1 - nodes[node].left;
        node = nodes[node].left - 1;
      }
    }
  }
}

class LsdHeader {
  final String magic;
  final int version;
  final int unk;
  final int checksum;
  final int entriesCount;
  final int annotationOffset;
  final int dictionaryEncoderOffset;
  final int articlesOffset;
  final int pagesOffset;
  final int unk1;
  final int lastPage;
  final int unk3;
  final int sourceLanguage;
  final int targetLanguage;

  LsdHeader._({
    required this.magic,
    required this.version,
    required this.unk,
    required this.checksum,
    required this.entriesCount,
    required this.annotationOffset,
    required this.dictionaryEncoderOffset,
    required this.articlesOffset,
    required this.pagesOffset,
    required this.unk1,
    required this.lastPage,
    required this.unk3,
    required this.sourceLanguage,
    required this.targetLanguage,
  });

  int get hiVersion => version >> 16;

  factory LsdHeader.fromStream(BitStream bs) {
    final rawMagic = bs.readBytes(8);
    final magic = String.fromCharCodes(rawMagic).replaceAll('\x00', '');
    final version = reverse32(bs.readInt());
    final unk = reverse32(bs.readInt());
    final checksum = reverse32(bs.readInt());
    final entriesCount = reverse32(bs.readInt());
    final annotationOffset = reverse32(bs.readInt());
    final dictionaryEncoderOffset = reverse32(bs.readInt());
    final articlesOffset = reverse32(bs.readInt());
    final pagesOffset = reverse32(bs.readInt());
    final unk1 = reverse32(bs.readInt());
    final lastPage = reverse16(bs.readWord());
    final unk3 = reverse16(bs.readWord());
    final sourceLanguage = reverse16(bs.readWord());
    final targetLanguage = reverse16(bs.readWord());

    return LsdHeader._(
      magic: magic,
      version: version,
      unk: unk,
      checksum: checksum,
      entriesCount: entriesCount,
      annotationOffset: annotationOffset,
      dictionaryEncoderOffset: dictionaryEncoderOffset,
      articlesOffset: articlesOffset,
      pagesOffset: pagesOffset,
      unk1: unk1,
      lastPage: lastPage,
      unk3: unk3,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
  }
}

class CachePage {
  final bool isLeaf;
  final int number;
  final int prev;
  final int parent;
  final int next;
  final int headingsCount;

  CachePage(this.isLeaf, this.number, this.prev, this.parent, this.next, this.headingsCount);

  static CachePage read(BitStream bs) {
    final isLeaf = bs.readBit() == 1;
    final number = bs.readBits(16);
    final prev = bs.readBits(16);
    final parent = bs.readBits(16);
    final next = bs.readBits(16);
    final headingsCount = bs.readBits(16);
    bs.toNearestByte();
    return CachePage(isLeaf, number, prev, parent, next, headingsCount);
  }
}

abstract class Decoder {
  final BitStream bs;
  String prefix = '';
  int prefixBits = 0;
  List<int> articleSymbols = [];
  List<int> headingSymbols = [];
  late LenTable ltArticles;
  late LenTable ltHeadings;
  late LenTable ltPrefixLengths;
  late LenTable ltPostfixLengths;
  int huffman1Number = 0;
  int huffman2Number = 0;

  Decoder(this.bs);

  void read();
  String decodeHeading(int size);
  String decodeArticle(int size);

  int readReference(int huffmanNumber) {
    final code = bs.readBits(2);
    if (code == 3) {
      bs.readBits(32);
      return -1;
    }
    final bits = max(2, bitLength(huffmanNumber));
    return (code << (bits - 2)) | bs.readBits(bits - 2);
  }

  int decodePrefixLen() => ltPrefixLengths.decode();
  int decodePostfixLen() => ltPostfixLengths.decode();
}

class UserDictionaryDecoder extends Decoder {
  UserDictionaryDecoder(super.bs);

  @override
  void read() {
    final prefixLen = bs.readInt();
    prefix = bs.readUnicode(prefixLen);
    prefixBits = bitLength(prefix.length);
    articleSymbols = bs.readSymbols();
    headingSymbols = bs.readSymbols();
    ltArticles = LenTable(bs);
    ltHeadings = LenTable(bs);
    ltPrefixLengths = LenTable(bs);
    ltPostfixLengths = LenTable(bs);
    huffman1Number = bs.readBits(32);
    huffman2Number = bs.readBits(32);
  }

  @override
  String decodeHeading(int size) {
    final codes = <int>[];
    for (int i = 0; i < size; i++) {
      codes.add(headingSymbols[ltHeadings.decode()]);
    }
    return String.fromCharCodes(codes);
  }

  @override
  String decodeArticle(int size) {
    final codes = <int>[];
    final sizeBits = bitLength(size);
    while (codes.length < size) {
      final sym = articleSymbols[ltArticles.decode()];
      if (sym >= 0x10000) {
        if (sym >= 0x10040) {
          final startIdx = bs.readBits(sizeBits);
          final len = sym - 0x1003d;
          for (int j = startIdx; j < startIdx + len && j < codes.length; j++) {
            codes.add(codes[j]);
          }
        } else {
          final startIdx = bs.readBits(prefixBits);
          final len = sym - 0xfffd;
          for (int j = startIdx; j < startIdx + len && j < prefix.length; j++) {
            codes.add(prefix.codeUnitAt(j));
          }
        }
      } else {
        codes.add(sym);
      }
    }
    return String.fromCharCodes(codes);
  }
}

class SystemDictionaryDecoder13 extends Decoder {
  SystemDictionaryDecoder13(super.bs);

  @override
  void read() {
    final prefixLen = bs.readInt();
    prefix = bs.readUnicode(prefixLen);
    prefixBits = bitLength(prefix.length);
    articleSymbols = bs.readSymbols();
    headingSymbols = bs.readSymbols();
    ltArticles = LenTable(bs);
    ltHeadings = LenTable(bs);
    ltPrefixLengths = LenTable(bs);
    ltPostfixLengths = LenTable(bs);
    huffman1Number = bs.readBits(32);
    huffman2Number = bs.readBits(32);
  }

  @override
  String decodeHeading(int size) {
    final codes = <int>[];
    for (int i = 0; i < size; i++) {
      codes.add(headingSymbols[ltHeadings.decode()]);
    }
    return String.fromCharCodes(codes);
  }

  @override
  String decodeArticle(int size) {
    final codes = <int>[];
    final sizeBits = bitLength(size);
    while (codes.length < size) {
      final sym = articleSymbols[ltArticles.decode()];
      if (sym >= 0x10000) {
        if (sym >= 0x10040) {
          final startIdx = bs.readBits(sizeBits);
          final len = sym - 0x1003d;
          for (int j = startIdx; j < startIdx + len && j < codes.length; j++) {
            codes.add(codes[j]);
          }
        } else {
          final startIdx = bs.readBits(prefixBits);
          final len = sym - 0xfffd;
          for (int j = startIdx; j < startIdx + len && j < prefix.length; j++) {
            codes.add(prefix.codeUnitAt(j));
          }
        }
      } else {
        codes.add(sym);
      }
    }
    return String.fromCharCodes(codes);
  }
}

/// Decoder for Lingvo X5/X6 system dictionaries (v14/15, system dicts).
/// Uses `sym >= 0x10000` dispatch (same as user dict).
class SystemDictionaryDecoder14 extends Decoder {
  SystemDictionaryDecoder14(super.bs);

  @override
  void read() {
    final prefixLen = bs.readInt();
    prefix = bs.readUnicode(prefixLen);
    prefixBits = bitLength(prefix.length);
    articleSymbols = bs.readSymbols();
    headingSymbols = bs.readSymbols();
    ltArticles = LenTable(bs);
    ltHeadings = LenTable(bs);
    ltPostfixLengths = LenTable(bs);
    bs.readBits(32);
    ltPrefixLengths = LenTable(bs);
    huffman1Number = bs.readBits(32);
    huffman2Number = bs.readBits(32);
  }

  @override
  String decodeHeading(int size) {
    final codes = <int>[];
    for (int i = 0; i < size; i++) {
      codes.add(headingSymbols[ltHeadings.decode()]);
    }
    return String.fromCharCodes(codes);
  }

  @override
  String decodeArticle(int size) {
    final codes = <int>[];
    final sizeBits = bitLength(size);
    while (codes.length < size) {
      final sym = articleSymbols[ltArticles.decode()];
      if (sym >= 0x10000) {
        if (sym >= 0x10040) {
          final startIdx = bs.readBits(sizeBits);
          final len = sym - 0x1003d;
          for (int j = startIdx; j < startIdx + len && j < codes.length; j++) {
            codes.add(codes[j]);
          }
        } else {
          final startIdx = bs.readBits(prefixBits);
          final len = sym - 0xfffd;
          for (int j = startIdx; j < startIdx + len && j < prefix.length; j++) {
            codes.add(prefix.codeUnitAt(j));
          }
        }
      } else {
        codes.add(sym);
      }
    }
    return String.fromCharCodes(codes);
  }
}

class AbbreviationDictionaryDecoder extends Decoder {
  AbbreviationDictionaryDecoder(super.bs);

  @override
  void read() {
    prefix = _readXoredPrefix(bs.readInt());
    prefixBits = bitLength(prefix.length);
    articleSymbols = _readXoredSymbols();
    headingSymbols = _readXoredSymbols();
    ltArticles = LenTable(bs);
    ltHeadings = LenTable(bs);
    ltPrefixLengths = LenTable(bs);
    ltPostfixLengths = LenTable(bs);
    huffman1Number = bs.readBits(32);
    huffman2Number = bs.readBits(32);
  }

  List<int> _readXoredSymbols() {
    final size = bs.readBits(32);
    final bitsPerSymbol = bs.readBits(8);
    final result = <int>[];
    for (int i = 0; i < size; i++) {
      result.add(bs.readBits(bitsPerSymbol) ^ 0x1325);
    }
    return result;
  }

  String _readXoredPrefix(int size) {
    final sb = StringBuffer();
    for (int i = 0; i < size; i++) {
      sb.writeCharCode(bs.readBits(16) ^ 0x879A);
    }
    return sb.toString();
  }

  @override
  String decodeHeading(int size) {
    final codes = <int>[];
    for (int i = 0; i < size; i++) {
      codes.add(headingSymbols[ltHeadings.decode()]);
    }
    return String.fromCharCodes(codes);
  }

  @override
  String decodeArticle(int size) {
    final codes = <int>[];
    final sizeBits = bitLength(size);
    while (codes.length < size) {
      final sym = articleSymbols[ltArticles.decode()];
      if (sym >= 0x10000) {
        if (sym >= 0x10040) {
          final startIdx = bs.readBits(sizeBits);
          final len = sym - 0x1003d;
          for (int j = startIdx; j < startIdx + len && j < codes.length; j++) {
            codes.add(codes[j]);
          }
        } else {
          final startIdx = bs.readBits(prefixBits);
          final len = sym - 0xfffd;
          for (int j = startIdx; j < startIdx + len && j < prefix.length; j++) {
            codes.add(prefix.codeUnitAt(j));
          }
        }
      } else {
        codes.add(sym);
      }
    }
    return String.fromCharCodes(codes);
  }
}

const xorPad = [
  0x9C, 0xDF, 0x9B, 0xF3, 0xBE, 0x3A, 0x83, 0xD8,
  0xC9, 0xF5, 0x50, 0x98, 0x35, 0x4E, 0x7F, 0xBB,
  0x89, 0xC7, 0xE9, 0x6B, 0xC4, 0xC8, 0x4F, 0x85,
  0x1A, 0x10, 0x43, 0x66, 0x65, 0x57, 0x55, 0x54,
  0xB4, 0xFF, 0xD7, 0x17, 0x06, 0x31, 0xAC, 0x4B,
  0x42, 0x53, 0x5A, 0x46, 0xC5, 0xF8, 0xCA, 0x5E,
  0x18, 0x38, 0x5D, 0x91, 0xAA, 0xA5, 0x58, 0x23,
  0x67, 0xBF, 0x30, 0x3C, 0x8C, 0xCF, 0xD5, 0xA8,
  0x20, 0xEE, 0x0B, 0x8E, 0xA6, 0x5B, 0x49, 0x3F,
  0xC0, 0xF4, 0x13, 0x80, 0xCB, 0x7B, 0xA7, 0x1D,
  0x81, 0x8B, 0x01, 0xDD, 0xE3, 0x4C, 0x9A, 0xCE,
  0x40, 0x72, 0xDE, 0x0F, 0x26, 0xBD, 0x3B, 0xA3,
  0x05, 0x37, 0xE1, 0x5F, 0x9D, 0x1E, 0xCD, 0x69,
  0x6E, 0xAB, 0x6D, 0x6C, 0xC3, 0x71, 0x1F, 0xA9,
  0x84, 0x63, 0x45, 0x76, 0x25, 0x70, 0xD6, 0x8F,
  0xFD, 0x04, 0x2E, 0x2A, 0x22, 0xF0, 0xB8, 0xF2,
  0xB6, 0xD0, 0xDA, 0x62, 0x75, 0xB7, 0x77, 0x34,
  0xA2, 0x41, 0xB9, 0xB1, 0x74, 0xE4, 0x95, 0x1B,
  0x3E, 0xE7, 0x00, 0xBC, 0x93, 0x7A, 0xE8, 0x86,
  0x59, 0xA0, 0x92, 0x11, 0xF7, 0xFE, 0x03, 0x2F,
  0x28, 0xFA, 0x27, 0x02, 0xE5, 0x39, 0x21, 0x96,
  0x33, 0xD1, 0xB2, 0x7C, 0xB3, 0x73, 0xC6, 0xE6,
  0xA1, 0x52, 0xFB, 0xD4, 0x9E, 0xB0, 0xE2, 0x16,
  0x97, 0x08, 0xF6, 0x4A, 0x78, 0x29, 0x14, 0x12,
  0x4D, 0xC1, 0x99, 0xBA, 0x0D, 0x3D, 0xEF, 0x19,
  0xAF, 0xF9, 0x6F, 0x0A, 0x6A, 0x47, 0x36, 0x82,
  0x07, 0x9F, 0x7D, 0xA4, 0xEA, 0x44, 0x09, 0x5C,
  0x8D, 0xCC, 0x87, 0x88, 0x2D, 0x8A, 0xEB, 0x2C,
  0xB5, 0xE0, 0x32, 0xAD, 0xD3, 0x61, 0xAE, 0x15,
  0x60, 0xF1, 0x48, 0x0E, 0x7E, 0x94, 0x51, 0x0C,
  0xEC, 0xDB, 0xD2, 0x64, 0xDC, 0xFC, 0xC2, 0x56,
  0x24, 0xED, 0x2B, 0xD9, 0x1C, 0x68, 0x90, 0x79
];

class LsdDecoderDart {
  final String filePath;
  final String? dictionaryId;

  LsdDecoderDart(this.filePath, {this.dictionaryId});

  Future<LsdDecodeResult> decode() async {
    final file = File(filePath);
    final data = await file.readAsBytes();

    if (Platform.isIOS) {
      return _lsdDecodeCore(data, dictionaryId: dictionaryId);
    }

    final jsonString = await Isolate.run(() => _lsdDecodeInIsolateJson(
          data,
          dictionaryId: dictionaryId,
        ))
        .timeout(const Duration(seconds: 120));

    final map = jsonDecode(jsonString) as Map<String, dynamic>;
    return LsdDecodeResult.fromJson(map);
  }
}

String _lsdDecodeInIsolateJson(
  Uint8List data, {
  String? dictionaryId,
}) {
  return jsonEncode(_lsdDecodeCore(data, dictionaryId: dictionaryId).toJson());
}

LsdDecodeResult _lsdDecodeCore(
  Uint8List data, {
  String? dictionaryId,
}) {
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
    bs.readBytes(iconSize);
  }
  if (header.version > 0x140000) {
    bs.readInt();
  }
  reverse32(bs.readInt());
  if (header.version > 0x120000) {
    bs.readInt();
  }
  if (header.version > 0x140000) {
    bs.readInt();
    bs.readInt();
  }

  final decoder = _createDecoderInIsolate(header, bs, data);
  if (header.version == 0x151005) {
    int key = 0x7f;
    for (int i = header.dictionaryEncoderOffset; i < header.articlesOffset; i++) {
      final byte = data[i];
      data[i] = byte ^ key;
      key = xorPad[byte];
    }
  }
  bs.seek(header.dictionaryEncoderOffset);
  decoder.read();

  final headings = <ArticleHeadingInfo>[];
  final pagesCount = header.lastPage + 1;
  for (int page = 0; page < pagesCount; page++) {
    bs.seek(header.pagesOffset + 512 * page);
    final pageObj = CachePage.read(bs);
    if (!pageObj.isLeaf) continue;

    String prefix = '';
    for (int idx = 0; idx < pageObj.headingsCount; idx++) {
      final prefixLen = decoder.decodePrefixLen();
      final postfixLen = decoder.decodePostfixLen();

      final p = prefixLen > 0 && prefix.length >= prefixLen
          ? prefix.substring(0, prefixLen)
          : '';
      final heading = postfixLen > 0 ? decoder.decodeHeading(postfixLen) : '';
      final fullWord = p + heading;
      final reference = decoder.readReference(decoder.huffman2Number);

      if (bs.readBit() != 0) {
        final pairCount = bs.readBits(8);
        for (int i = 0; i < pairCount; i++) {
          bs.readBits(8);
          bs.readBits(16);
        }
      }

      final info = reference < 0
          ? ArticleHeadingInfo([fullWord], 0)
          : ArticleHeadingInfo([fullWord], reference);
      headings.add(info);
      if (info.words.isNotEmpty) prefix = info.words.last;
    }
  }

  final entries = <DictionaryEntry>[];
  ArticleHeadingInfo? prev;
  List<FormattedText>? previousDefinitions;
  for (int i = 0; i < headings.length; i++) {
    final h = headings[i];
    if (i < headings.length - 1) {
      h.nextReference = headings[i + 1].reference;
    } else {
      h.nextReference = header.pagesOffset - header.articlesOffset;
    }

    if (prev != null && prev.reference == h.reference) {
      prev.words.addAll(h.words);
      if (previousDefinitions != null) {
        for (final word in h.words) {
          entries.add(DictionaryEntry(
            word: word,
            definitions: previousDefinitions,
            dictionaryId: dictionaryId ?? header.entriesCount.toString(),
            dictionaryName: name,
            index: entries.length,
          ));
        }
      }
      continue;
    }

    String article = '';
    if (h.nextReference != 0) {
      bs.seek(header.articlesOffset + h.reference);
      int size = bs.readBits(16);
      if (size == 0xFFFF) {
        size = bs.readBits(32);
      }
      article = decoder.decodeArticle(size);
    }

    final definitions = parseLingvoFormattedText(article);
    previousDefinitions = definitions;
    for (final word in h.words) {
      entries.add(DictionaryEntry(
        word: word,
        definitions: definitions,
        dictionaryId: dictionaryId ?? header.entriesCount.toString(),
        dictionaryName: name,
        index: entries.length,
      ));
    }
    prev = h;
  }

  return LsdDecodeResult(name: name, entries: entries);
}

Decoder _createDecoderInIsolate(LsdHeader header, BitStream bs, Uint8List data) {
  final hi = header.hiVersion;
  final version = header.version;

  if (hi == 0x11 || hi == 0x12) {
    return UserDictionaryDecoder(bs);
  }

  if (hi == 0x13) {
    return SystemDictionaryDecoder13(bs);
  }

  if (hi == 0x14) {
    if (version == 0x142001) {
      return UserDictionaryDecoder(bs);
    }
    if (version == 0x145001 || version == 0x141004) {
      return SystemDictionaryDecoder14(bs);
    }
  }

  if (hi == 0x15) {
    if (version == 0x152001) {
      return UserDictionaryDecoder(bs);
    }
    if (version == 0x151005) {
      return SystemDictionaryDecoder14(bs);
    }
    if (version == 0x155001) {
      return AbbreviationDictionaryDecoder(bs);
    }
  }

  throw Exception('Unsupported LSD version: 0x${version.toRadixString(16)}');
}

class ArticleHeadingInfo {
  final List<String> words;
  int reference;
  int nextReference;

  ArticleHeadingInfo(this.words, this.reference, [this.nextReference = 0]);
}

class LsdDecodeResult {
  final String name;
  final List<DictionaryEntry> entries;

  LsdDecodeResult({required this.name, required this.entries});

  Map<String, dynamic> toJson() => {
        'name': name,
        'entries': entries.map((entry) => entry.toJson()).toList(),
      };

  factory LsdDecodeResult.fromJson(Map<String, dynamic> json) {
    return LsdDecodeResult(
      name: json['name'] as String,
      entries: (json['entries'] as List)
          .map((e) => DictionaryEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
