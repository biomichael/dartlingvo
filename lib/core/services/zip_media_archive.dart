import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

class ZipMediaArchive {
  final String zipPath;
  final String cacheDirectoryPath;
  final Map<String, List<_ZipEntryMeta>> _entriesByKey;

  ZipMediaArchive._({
    required this.zipPath,
    required this.cacheDirectoryPath,
    required Map<String, List<_ZipEntryMeta>> entriesByKey,
  }) : _entriesByKey = entriesByKey;

  static ZipMediaArchive? open({
    required String zipPath,
    required String cacheDirectoryPath,
  }) {
    final file = File(zipPath);
    if (!file.existsSync()) {
      return null;
    }

    final archiveEntries = _readDirectoryEntries(file);
    if (archiveEntries.isEmpty) {
      return null;
    }

    final entriesByKey = <String, List<_ZipEntryMeta>>{};
    for (final entry in archiveEntries) {
      for (final key in _entryKeys(entry.filename)) {
        final list = entriesByKey.putIfAbsent(key, () => <_ZipEntryMeta>[]);
        list.add(entry);
      }
    }

    return ZipMediaArchive._(
      zipPath: file.path,
      cacheDirectoryPath: cacheDirectoryPath,
      entriesByKey: entriesByKey,
    );
  }

  File? resolveMediaReference(String mediaText, {String? entryWord}) {
    final entry = _resolveEntry(mediaText, entryWord: entryWord);
    if (entry == null) {
      return null;
    }

    final outputPath = _materializeEntry(entry);
    if (outputPath == null) {
      return null;
    }

    return File(outputPath);
  }

  _ZipEntryMeta? _resolveEntry(String mediaText, {String? entryWord}) {
    final candidates = _lookupKeys(mediaText, entryWord);
    for (final key in candidates) {
      final matches = _entriesByKey[key];
      if (matches == null || matches.isEmpty) {
        continue;
      }

      for (final entry in matches) {
        if (_matchesReferenceExtension(entry.filename, mediaText)) {
          return entry;
        }
      }
    }
    return null;
  }

  String? _materializeEntry(_ZipEntryMeta entry) {
    final cacheRoot = p.normalize(p.absolute(cacheDirectoryPath));
    final outputPath = p.normalize(p.join(cacheRoot, entry.filename));
    if (!p.isWithin(cacheRoot, outputPath) && outputPath != cacheRoot) {
      return null;
    }

    final outputFile = File(outputPath);
    if (outputFile.existsSync() && outputFile.lengthSync() > 0) {
      return outputFile.path;
    }

    final bytes = _readEntryBytes(entry);
    if (bytes.isEmpty) {
      return null;
    }

    outputFile.parent.createSync(recursive: true);
    outputFile.writeAsBytesSync(bytes, flush: true);
    return outputFile.path;
  }

  List<int> _readEntryBytes(_ZipEntryMeta entry) {
    final raf = File(zipPath).openSync(mode: FileMode.read);
    try {
      raf.setPositionSync(entry.localHeaderOffset);
      final localHeader = raf.readSync(_localHeaderSize);
      if (localHeader.length < _localHeaderSize) {
        return const <int>[];
      }

      final view = ByteData.sublistView(Uint8List.fromList(localHeader));
      if (view.getUint32(0, Endian.little) != _localHeaderSignature) {
        return const <int>[];
      }

      final nameLength = view.getUint16(26, Endian.little);
      final extraLength = view.getUint16(28, Endian.little);
      final dataOffset = entry.localHeaderOffset + _localHeaderSize + nameLength + extraLength;
      raf.setPositionSync(dataOffset);

      final payload = raf.readSync(entry.compressedSize);
      if (payload.isEmpty) {
        return const <int>[];
      }

      switch (entry.compressionMethod) {
        case 0:
          return payload;
        case 8:
          try {
            return Inflate(payload).getBytes();
          } catch (_) {
            return const <int>[];
          }
        default:
          return const <int>[];
      }
    } finally {
      raf.closeSync();
    }
  }

  static List<_ZipEntryMeta> _readDirectoryEntries(File file) {
    final raf = file.openSync(mode: FileMode.read);
    try {
      final layout = _readLayout(raf);
      if (layout == null) {
        return const [];
      }

      raf.setPositionSync(layout.centralDirectoryOffset);
      final dirBytes = raf.readSync(layout.centralDirectorySize);
      if (dirBytes.isEmpty) {
        return const [];
      }

      final dirStream = InputStream(dirBytes);
      final entries = <_ZipEntryMeta>[];
      while (!dirStream.isEOS) {
        final fileSig = dirStream.readUint32();
        if (fileSig != ZipFileHeader.SIGNATURE) {
          break;
        }
        final header = ZipFileHeader(dirStream);
        if (header.filename.isEmpty) {
          continue;
        }

        entries.add(_ZipEntryMeta(
          filename: header.filename,
          localHeaderOffset: header.localHeaderOffset ?? 0,
          compressedSize: header.compressedSize ?? 0,
          uncompressedSize: header.uncompressedSize ?? 0,
          compressionMethod: header.compressionMethod,
        ));
      }

      return entries;
    } finally {
      raf.closeSync();
    }
  }

  static _ZipLayout? _readLayout(RandomAccessFile raf) {
    final filePosition = _findEocdrSignature(raf);
    if (filePosition < 0) {
      return null;
    }

    raf.setPositionSync(filePosition);
    final eocdr = raf.readSync(_eocdrSize);
    if (eocdr.length < _eocdrSize) {
      return null;
    }
    final eocdrView = ByteData.sublistView(Uint8List.fromList(eocdr));
    final totalCentralDirectoryEntriesOnThisDisk = eocdrView.getUint16(10, Endian.little);
    final centralDirectorySize = eocdrView.getUint32(12, Endian.little);
    final centralDirectoryOffset = eocdrView.getUint32(16, Endian.little);
    final commentLength = eocdrView.getUint16(20, Endian.little);
    if (commentLength > 0) {
      raf.readSync(commentLength);
    }

    var directorySize = centralDirectorySize;
    var directoryOffset = centralDirectoryOffset;
    var totalEntries = totalCentralDirectoryEntriesOnThisDisk;

    if (centralDirectoryOffset == 0xffffffff ||
        centralDirectorySize == 0xffffffff ||
        totalCentralDirectoryEntriesOnThisDisk == 0xffff) {
      final layout = _readZip64Layout(raf, filePosition);
      if (layout == null) {
        return null;
      }
      directorySize = layout.centralDirectorySize;
      directoryOffset = layout.centralDirectoryOffset;
      totalEntries = layout.totalEntries;
    }

    if (directorySize <= 0 || directoryOffset < 0 || totalEntries < 0) {
      return null;
    }

    return _ZipLayout(
      centralDirectoryOffset: directoryOffset,
      centralDirectorySize: directorySize,
    );
  }

  static _ZipLayout? _readZip64Layout(RandomAccessFile raf, int filePosition) {
    final locPos = filePosition - _zip64EocdLocatorSize;
    if (locPos < 0) {
      return null;
    }

    raf.setPositionSync(locPos);
    final locatorBytes = raf.readSync(_zip64EocdLocatorSize);
    if (locatorBytes.length < _zip64EocdLocatorSize) {
      return null;
    }
    final locatorView = ByteData.sublistView(Uint8List.fromList(locatorBytes));
    final locatorSig = locatorView.getUint32(0, Endian.little);
    if (locatorSig != _zip64EocdLocatorSignature) {
      return null;
    }

    final zip64DirOffset = locatorView.getUint64(8, Endian.little);

    raf.setPositionSync(zip64DirOffset);
    final zip64Bytes = raf.readSync(_zip64EocdSize);
    if (zip64Bytes.length < _zip64EocdSize) {
      return null;
    }
    final zip64View = ByteData.sublistView(Uint8List.fromList(zip64Bytes));
    final zip64Sig = zip64View.getUint32(0, Endian.little);
    if (zip64Sig != _zip64EocdSignature) {
      return null;
    }

    final totalEntriesOnDisk = zip64View.getUint64(24, Endian.little);
    final totalEntries = zip64View.getUint64(32, Endian.little);
    final dirSize = zip64View.getUint64(40, Endian.little);
    final dirOffset = zip64View.getUint64(48, Endian.little);

    return _ZipLayout(
      centralDirectoryOffset: dirOffset,
      centralDirectorySize: dirSize,
      totalEntries: totalEntries,
      totalEntriesOnDisk: totalEntriesOnDisk,
    );
  }

  static int _findEocdrSignature(RandomAccessFile raf) {
    final pos = raf.positionSync();
    final length = raf.lengthSync();
    for (var ip = length - 5; ip >= 0; --ip) {
      raf.setPositionSync(ip);
      final sigBytes = raf.readSync(4);
      if (sigBytes.length < 4) {
        continue;
      }
      final sig = ByteData.sublistView(Uint8List.fromList(sigBytes)).getUint32(0, Endian.little);
      if (sig == _eocdLocatorSignature) {
        raf.setPositionSync(pos);
        return ip;
      }
    }
    return -1;
  }

  static List<String> _lookupKeys(String mediaText, String? entryWord) {
    final relative = _normalizeName(mediaText);
    final baseName = p.basename(relative);
    final normalizedRelative = _normalizeMediaKey(relative);
    final normalizedBase = _normalizeMediaKey(baseName);
    final normalizedStem = _normalizedStem(normalizedBase);
    final entryWordKey = entryWord == null ? '' : _normalizeMediaKey(entryWord);
    final entryStem = _normalizedStem(entryWordKey);

    final keys = <String>{
      normalizedRelative,
      normalizedBase,
      normalizedStem,
      entryWordKey,
      entryStem,
    };
    keys.removeWhere((value) => value.isEmpty);
    return keys.toList(growable: false);
  }

  static List<String> _entryKeys(String relativePath) {
    final normalizedRelative = _normalizeName(relativePath);
    final baseName = p.basename(relativePath);
    final normalizedBase = _normalizeMediaKey(baseName);
    final normalizedRelativeKey = _normalizeMediaKey(normalizedRelative);
    final normalizedBaseStem = _normalizedStem(normalizedBase);
    final normalizedRelativeStem = _normalizedStem(normalizedRelativeKey);

    final keys = <String>{
      normalizedRelativeKey,
      normalizedBase,
      normalizedBaseStem,
      normalizedRelativeStem,
    };
    keys.removeWhere((value) => value.isEmpty);
    return keys.toList(growable: false);
  }

  static bool _matchesReferenceExtension(String path, String mediaText) {
    final referenceExtension = p.extension(mediaText).toLowerCase();
    if (referenceExtension.isEmpty) {
      return true;
    }
    return p.extension(path).toLowerCase() == referenceExtension;
  }

  static String _normalizeName(String value) {
    var normalized = value.trim().replaceAll('\\', '/');
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    return normalized;
  }

  static String _normalizeMediaKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  static String _normalizedStem(String key) {
    if (key.isEmpty) {
      return '';
    }

    var stem = key.replaceFirst(RegExp(r'\d+$'), '');
    for (final prefix in const ['ame', 'bre', 'us', 'uk', 'ukr', 'us1', 'us2', 'bre1', 'bre2']) {
      if (stem.startsWith(prefix) && stem.length > prefix.length + 2) {
        stem = stem.substring(prefix.length);
        break;
      }
    }
    return stem;
  }

  static const int _eocdrSize = 22;
  static const int _zip64EocdLocatorSize = 20;
  static const int _zip64EocdSize = 56;
  static const int _eocdLocatorSignature = 0x06054b50;
  static const int _zip64EocdLocatorSignature = 0x07064b50;
  static const int _zip64EocdSignature = 0x06064b50;
}

class _ZipEntryMeta {
  final String filename;
  final int localHeaderOffset;
  final int compressedSize;
  final int uncompressedSize;
  final int compressionMethod;

  const _ZipEntryMeta({
    required this.filename,
    required this.localHeaderOffset,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.compressionMethod,
  });
}

class _ZipLayout {
  final int centralDirectoryOffset;
  final int centralDirectorySize;
  final int totalEntries;
  final int totalEntriesOnDisk;

  const _ZipLayout({
    required this.centralDirectoryOffset,
    required this.centralDirectorySize,
    this.totalEntries = 0,
    this.totalEntriesOnDisk = 0,
  });
}

const _localHeaderSignature = 0x04034b50;
const _localHeaderSize = 30;
