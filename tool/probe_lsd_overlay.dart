import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart tool/probe_lsd_overlay.dart <path-to-lsd>');
    exitCode = 64;
    return;
  }

  final path = args.first;
  final file = File(path);
  if (!await file.exists()) {
    stderr.writeln('File not found: $path');
    exitCode = 66;
    return;
  }

  final raf = await file.open(mode: FileMode.read);
  try {
    final fileLength = await raf.length();
    final rawMagic = await raf.read(8);
    final magic = ascii.decode(rawMagic, allowInvalid: true).replaceAll('\x00', '');
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

    final nameLen = await _readUint8(raf);
    await _skipUnicode(raf, nameLen, maxChars: 256);
    final firstLen = await _readUint8(raf);
    await _skipUnicode(raf, firstLen, maxChars: 256);
    final lastLen = await _readUint8(raf);
    await _skipUnicode(raf, lastLen, maxChars: 256);
    final capitalsLen = await _readUint32Le(raf);
    await _skipUnicode(raf, capitalsLen, maxChars: 4096);

    if (version > 0x120000) {
      final iconSize = await _readUint16Le(raf);
      await _skipBytes(raf, iconSize);
    }
    if (version > 0x140000) {
      await _skipBytes(raf, 4);
    }

    final pagesEnd = await _readUint32Le(raf);
    final overlayData = await _readUint32Le(raf);

    stdout.writeln('fileLength=$fileLength');
    stdout.writeln('magic=$magic version=0x${version.toRadixString(16)} unk=$unk checksum=$checksum');
    stdout.writeln('entriesCount=$entriesCount annotationOffset=$annotationOffset dictionaryEncoderOffset=$dictionaryEncoderOffset articlesOffset=$articlesOffset pagesOffset=$pagesOffset');
    stdout.writeln('unk1=$unk1 lastPage=$lastPage unk3=$unk3 sourceLanguage=$sourceLanguage targetLanguage=$targetLanguage');
    stdout.writeln('pagesEnd=$pagesEnd overlayData=$overlayData cursor=${await raf.position()}');
    await _dumpBytes(raf, pagesEnd, 64, label: 'pagesEnd');
    if (overlayData >= 0) {
      await _dumpBytes(raf, overlayData, 64, label: 'overlayData');
    }
    await _scanForTable(raf, pagesEnd, fileLength);
  } finally {
    await raf.close();
  }
}

Future<int> _readUint8(RandomAccessFile raf) async {
  final bytes = await raf.read(1);
  return bytes.isEmpty ? 0 : bytes[0];
}

Future<int> _readUint16Le(RandomAccessFile raf) async {
  final bytes = await raf.read(2);
  if (bytes.length < 2) return 0;
  return ByteData.sublistView(Uint8List.fromList(bytes)).getUint16(0, Endian.little);
}

Future<int> _readUint32Le(RandomAccessFile raf) async {
  final bytes = await raf.read(4);
  if (bytes.length < 4) return 0;
  return ByteData.sublistView(Uint8List.fromList(bytes)).getUint32(0, Endian.little);
}

Future<void> _skipBytes(RandomAccessFile raf, int count) async {
  if (count <= 0) return;
  final current = await raf.position();
  await raf.setPosition(current + count);
}

Future<void> _skipUnicode(RandomAccessFile raf, int chars, {required int maxChars}) async {
  if (chars <= 0) return;
  final safeChars = chars > maxChars ? maxChars : chars;
  await _skipBytes(raf, safeChars * 2);
}

Future<void> _dumpBytes(RandomAccessFile raf, int offset, int length, {required String label}) async {
  final fileLength = await raf.length();
  if (offset < 0 || offset >= fileLength) {
    stdout.writeln('$label: out of range');
    return;
  }
  final safeLength = offset + length > fileLength ? fileLength - offset : length;
  await raf.setPosition(offset);
  final bytes = await raf.read(safeLength);
  stdout.writeln('$label bytes[${offset}..${offset + bytes.length}): ${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
}

Future<void> _scanForTable(RandomAccessFile raf, int pagesEnd, int fileLength) async {
  final candidates = <int>{
    pagesEnd - 64,
    pagesEnd - 32,
    pagesEnd - 16,
    pagesEnd,
    pagesEnd + 16,
    pagesEnd + 32,
    pagesEnd + 64,
  }.where((o) => o >= 0 && o < fileLength).toList()
    ..sort();

  for (final offset in candidates) {
    await raf.setPosition(offset);
    final rawCount = await raf.read(4);
    if (rawCount.length < 4) continue;
    final count = ByteData.sublistView(Uint8List.fromList(rawCount)).getUint32(0, Endian.little);
    if (count == 0 || count > 1000) {
      continue;
    }
    stdout.writeln('possible table at $offset count=$count');
    await raf.setPosition(offset + 4);
    for (var i = 0; i < count && i < 10; i++) {
      final nameLen = await _readUint8(raf);
      final nameBytes = await raf.read(nameLen * 2);
      final name = _decodeUtf16Le(nameBytes);
      final entryOffset = await _readUint32Le(raf);
      final unk2 = await _readUint32Le(raf);
      final inflatedSize = await _readUint32Le(raf);
      final streamSize = await _readUint32Le(raf);
      stdout.writeln('  entry[$i] name="$name" offset=$entryOffset unk2=$unk2 inflatedSize=$inflatedSize streamSize=$streamSize');
    }
  }
}

String _decodeUtf16Le(List<int> bytes) {
  final codeUnits = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    final ch = bytes[i] | (bytes[i + 1] << 8);
    if (ch == 0) break;
    codeUnits.add(ch);
  }
  return String.fromCharCodes(codeUnits);
}
