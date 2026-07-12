import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class OverlayHeading {
  final String name;
  final int offset;
  final int unk2;
  final int inflatedSize;
  final int streamSize;

  const OverlayHeading({
    required this.name,
    required this.offset,
    required this.unk2,
    required this.inflatedSize,
    required this.streamSize,
  });
}

class LsdOverlayReader {
  final String filePath;
  final int overlayHeadingsOffset;
  final int overlayDataOffset;

  const LsdOverlayReader({
    required this.filePath,
    required this.overlayHeadingsOffset,
    required this.overlayDataOffset,
  });

  static Future<LsdOverlayReader?> open(String filePath) async {
    final layout = await _readLayout(filePath);
    if (layout == null) {
      return null;
    }
    if (layout.overlayHeadingsOffset <= 0 || layout.overlayDataOffset < 0) {
      return null;
    }
    return LsdOverlayReader(
      filePath: filePath,
      overlayHeadingsOffset: layout.overlayHeadingsOffset,
      overlayDataOffset: layout.overlayDataOffset,
    );
  }

  static LsdOverlayReader? openSync(String filePath) {
    final layout = _readLayoutSync(filePath);
    if (layout == null) {
      return null;
    }
    if (layout.overlayHeadingsOffset <= 0 || layout.overlayDataOffset < 0) {
      return null;
    }
    return LsdOverlayReader(
      filePath: filePath,
      overlayHeadingsOffset: layout.overlayHeadingsOffset,
      overlayDataOffset: layout.overlayDataOffset,
    );
  }

  Future<List<OverlayHeading>> readHeadings() async {
    if (overlayHeadingsOffset <= 0 || overlayDataOffset < 0) {
      return const [];
    }

    final raf = await File(filePath).open(mode: FileMode.read);
    try {
      return await _readHeadingsAtOffset(raf, overlayHeadingsOffset);
    } finally {
      await raf.close();
    }
  }

  List<OverlayHeading> readHeadingsSync() {
    if (overlayHeadingsOffset <= 0 || overlayDataOffset < 0) {
      return const [];
    }

    final raf = File(filePath).openSync(mode: FileMode.read);
    try {
      return _readHeadingsAtOffsetSync(raf, overlayHeadingsOffset);
    } finally {
      raf.closeSync();
    }
  }

  Future<List<int>> readEntry(OverlayHeading heading) async {
    final raf = await File(filePath).open(mode: FileMode.read);
    try {
      final start = overlayDataOffset + heading.offset;
      await raf.setPosition(start);
      final slice = await _readBytes(raf, heading.streamSize);
      if (slice.isEmpty) {
        return const [];
      }

      return const ZLibDecoder().decodeBytes(slice, verify: false);
    } finally {
      await raf.close();
    }
  }

  List<int> readEntrySync(OverlayHeading heading) {
    final raf = File(filePath).openSync(mode: FileMode.read);
    try {
      final start = overlayDataOffset + heading.offset;
      raf.setPositionSync(start);
      final slice = _readBytesSync(raf, heading.streamSize);
      if (slice.isEmpty) {
        return const [];
      }

      return const ZLibDecoder().decodeBytes(slice, verify: false);
    } finally {
      raf.closeSync();
    }
  }

  static Future<_OverlayLayout?> _readLayout(String filePath) async {
    final raf = await File(filePath).open(mode: FileMode.read);
    try {
      final header = await _readHeader(raf);
      if (header == null || header.magic != 'LingVo') {
        return null;
      }

      final nameLen = await _readUint8(raf);
      await _skipUnicodeString(raf, nameLen);
      final firstHeadingLen = await _readUint8(raf);
      await _skipUnicodeString(raf, firstHeadingLen);
      final lastHeadingLen = await _readUint8(raf);
      await _skipUnicodeString(raf, lastHeadingLen);

      final capitalsLen = await _readUint32Le(raf);
      await _skipUnicodeString(raf, capitalsLen);

      if (header.version > 0x120000) {
        final iconSize = await _readUint16Le(raf);
        await _skipBytes(raf, iconSize);
      }
      if (header.version > 0x140000) {
        await _skipBytes(raf, 4);
      }

      final pagesEnd = await _readUint32Le(raf);
      var overlayData = await _readUint32Le(raf);

      final fileLength = await raf.length();
      if (pagesEnd <= 0 || pagesEnd >= fileLength) {
        return null;
      }

      if (header.version < 0x120000) {
        overlayData = -1;
      } else if (header.version < 0x140000) {
        overlayData = 0;
      }

      return _OverlayLayout(
        overlayHeadingsOffset: pagesEnd,
        overlayDataOffset: overlayData,
      );
    } finally {
      await raf.close();
    }
  }

  static _OverlayLayout? _readLayoutSync(String filePath) {
    final raf = File(filePath).openSync(mode: FileMode.read);
    try {
      final header = _readHeaderSync(raf);
      if (header == null || header.magic != 'LingVo') {
        return null;
      }

      final nameLen = _readUint8Sync(raf);
      _skipUnicodeStringSync(raf, nameLen);
      final firstHeadingLen = _readUint8Sync(raf);
      _skipUnicodeStringSync(raf, firstHeadingLen);
      final lastHeadingLen = _readUint8Sync(raf);
      _skipUnicodeStringSync(raf, lastHeadingLen);

      final capitalsLen = _readUint32LeSync(raf);
      _skipUnicodeStringSync(raf, capitalsLen);

      if (header.version > 0x120000) {
        final iconSize = _readUint16LeSync(raf);
        _skipBytesSync(raf, iconSize);
      }
      if (header.version > 0x140000) {
        _skipBytesSync(raf, 4);
      }

      final pagesEnd = _readUint32LeSync(raf);
      var overlayData = _readUint32LeSync(raf);

      final fileLength = raf.lengthSync();
      if (pagesEnd <= 0 || pagesEnd >= fileLength) {
        return null;
      }

      if (header.version < 0x120000) {
        overlayData = -1;
      } else if (header.version < 0x140000) {
        overlayData = 0;
      }

      return _OverlayLayout(
        overlayHeadingsOffset: pagesEnd,
        overlayDataOffset: overlayData,
      );
    } finally {
      raf.closeSync();
    }
  }

  static Future<_LsdHeader?> _readHeader(RandomAccessFile raf) async {
    final rawMagic = await _readBytes(raf, 8);
    if (rawMagic.length < 8) {
      return null;
    }

    final magic = String.fromCharCodes(rawMagic).replaceAll('\x00', '');
    final version = await _readUint32Le(raf);
    final unk = await _readUint32Le(raf);
    final checksum = await _readUint32Le(raf);
    final entriesCount = await _readUint32Le(raf);
    final annotationOffset = await _readUint32Le(raf);
    final dictionaryEncoderOffset = await _readUint32Le(raf);
    final articlesOffset = await _readUint32Le(raf);
    final pagesOffset = await _readUint32Le(raf);
    final unk1 = await _readUint32Le(raf);
    final lastPage = await _readUint16Le(raf);
    final unk3 = await _readUint16Le(raf);
    final sourceLanguage = await _readUint16Le(raf);
    final targetLanguage = await _readUint16Le(raf);

    return _LsdHeader(
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

  static _LsdHeader? _readHeaderSync(RandomAccessFile raf) {
    final rawMagic = _readBytesSync(raf, 8);
    if (rawMagic.length < 8) {
      return null;
    }

    final magic = String.fromCharCodes(rawMagic).replaceAll('\x00', '');
    final version = _readUint32LeSync(raf);
    final unk = _readUint32LeSync(raf);
    final checksum = _readUint32LeSync(raf);
    final entriesCount = _readUint32LeSync(raf);
    final annotationOffset = _readUint32LeSync(raf);
    final dictionaryEncoderOffset = _readUint32LeSync(raf);
    final articlesOffset = _readUint32LeSync(raf);
    final pagesOffset = _readUint32LeSync(raf);
    final unk1 = _readUint32LeSync(raf);
    final lastPage = _readUint16LeSync(raf);
    final unk3 = _readUint16LeSync(raf);
    final sourceLanguage = _readUint16LeSync(raf);
    final targetLanguage = _readUint16LeSync(raf);

    return _LsdHeader(
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

  static Future<int> _readUint8(RandomAccessFile raf) async {
    final bytes = await _readBytes(raf, 1);
    return bytes.isEmpty ? 0 : bytes[0];
  }

  static int _readUint8Sync(RandomAccessFile raf) {
    final bytes = _readBytesSync(raf, 1);
    return bytes.isEmpty ? 0 : bytes[0];
  }

  static Future<int> _readUint16Le(RandomAccessFile raf) async {
    final bytes = await _readBytes(raf, 2);
    if (bytes.length < 2) {
      return 0;
    }
    return ByteData.sublistView(Uint8List.fromList(bytes)).getUint16(0, Endian.little);
  }

  static int _readUint16LeSync(RandomAccessFile raf) {
    final bytes = _readBytesSync(raf, 2);
    if (bytes.length < 2) {
      return 0;
    }
    return ByteData.sublistView(Uint8List.fromList(bytes)).getUint16(0, Endian.little);
  }

  static Future<int> _readUint32Le(RandomAccessFile raf) async {
    final bytes = await _readBytes(raf, 4);
    if (bytes.length < 4) {
      return 0;
    }
    return ByteData.sublistView(Uint8List.fromList(bytes)).getUint32(0, Endian.little);
  }

  static int _readUint32LeSync(RandomAccessFile raf) {
    final bytes = _readBytesSync(raf, 4);
    if (bytes.length < 4) {
      return 0;
    }
    return ByteData.sublistView(Uint8List.fromList(bytes)).getUint32(0, Endian.little);
  }

  static Future<String> _readUnicodeString(
    RandomAccessFile raf,
    int len, {
    required bool bigEndian,
  }) async {
    if (len <= 0) {
      return '';
    }

    final bytes = await _readBytes(raf, len * 2);
    if (bytes.isEmpty) {
      return '';
    }

    final data = Uint8List.fromList(bytes);
    final codeUnits = <int>[];
    for (var i = 0; i + 1 < data.length; i += 2) {
      final first = data[i];
      final second = data[i + 1];
      codeUnits.add(bigEndian ? (first << 8) | second : (second << 8) | first);
    }
    return String.fromCharCodes(codeUnits);
  }

  static String _readUnicodeStringSync(
    RandomAccessFile raf,
    int len, {
    required bool bigEndian,
  }) {
    if (len <= 0) {
      return '';
    }

    final bytes = _readBytesSync(raf, len * 2);
    if (bytes.isEmpty) {
      return '';
    }

    final data = Uint8List.fromList(bytes);
    final codeUnits = <int>[];
    for (var i = 0; i + 1 < data.length; i += 2) {
      final first = data[i];
      final second = data[i + 1];
      codeUnits.add(bigEndian ? (first << 8) | second : (second << 8) | first);
    }
    return String.fromCharCodes(codeUnits);
  }

  static Future<void> _skipUnicodeString(RandomAccessFile raf, int len) async {
    if (len <= 0) {
      return;
    }
    await _skipBytes(raf, len * 2);
  }

  static void _skipUnicodeStringSync(RandomAccessFile raf, int len) {
    if (len <= 0) {
      return;
    }
    _skipBytesSync(raf, len * 2);
  }

  static Future<void> _skipBytes(RandomAccessFile raf, int len) async {
    if (len <= 0) {
      return;
    }
    await raf.setPosition(raf.positionSync() + len);
  }

  static void _skipBytesSync(RandomAccessFile raf, int len) {
    if (len <= 0) {
      return;
    }
    raf.setPositionSync(raf.positionSync() + len);
  }

  static Future<List<int>> _readBytes(RandomAccessFile raf, int len) async {
    if (len <= 0) {
      return const [];
    }
    return await raf.read(len);
  }

  static List<int> _readBytesSync(RandomAccessFile raf, int len) {
    if (len <= 0) {
      return const [];
    }
    return raf.readSync(len);
  }

  static List<OverlayHeading> _readHeadingsAtOffsetSync(
    RandomAccessFile raf,
    int offset,
  ) {
    final fileLength = raf.lengthSync();
    if (offset <= 0 || offset >= fileLength) {
      return const [];
    }

    raf.setPositionSync(offset);
    final entriesCount = _readUint32LeSync(raf);
    if (entriesCount == 0) {
      return const [];
    }

    final entries = <OverlayHeading>[];
    for (var i = 0; i < entriesCount; i++) {
      final nameLen = _readUint8Sync(raf);
      final name = _readUnicodeStringSync(raf, nameLen, bigEndian: false);
      final offsetValue = _readUint32LeSync(raf);
      final unk2 = _readUint32LeSync(raf);
      final inflatedSize = _readUint32LeSync(raf);
      final streamSize = _readUint32LeSync(raf);

      if (inflatedSize == 0) {
        continue;
      }

      entries.add(OverlayHeading(
        name: name,
        offset: offsetValue,
        unk2: unk2,
        inflatedSize: inflatedSize,
        streamSize: streamSize,
      ));
    }

    return entries;
  }

  static Future<List<OverlayHeading>> _readHeadingsAtOffset(
    RandomAccessFile raf,
    int offset,
  ) async {
    final fileLength = await raf.length();
    if (offset <= 0 || offset >= fileLength) {
      return const [];
    }

    await raf.setPosition(offset);
    final entriesCount = await _readUint32Le(raf);
    if (entriesCount == 0) {
      return const [];
    }

    final entries = <OverlayHeading>[];
    for (var i = 0; i < entriesCount; i++) {
      final nameLen = await _readUint8(raf);
      final name = await _readUnicodeString(raf, nameLen, bigEndian: false);
      final offsetValue = await _readUint32Le(raf);
      final unk2 = await _readUint32Le(raf);
      final inflatedSize = await _readUint32Le(raf);
      final streamSize = await _readUint32Le(raf);

      if (inflatedSize == 0) {
        continue;
      }

      entries.add(OverlayHeading(
        name: name,
        offset: offsetValue,
        unk2: unk2,
        inflatedSize: inflatedSize,
        streamSize: streamSize,
      ));
    }

    return entries;
  }
}

class _OverlayLayout {
  final int overlayHeadingsOffset;
  final int overlayDataOffset;

  const _OverlayLayout({
    required this.overlayHeadingsOffset,
    required this.overlayDataOffset,
  });
}

class _LsdHeader {
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

  const _LsdHeader({
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
}
