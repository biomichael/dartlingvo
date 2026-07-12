import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../parsing/lsd_overlay_reader.dart';

class DictionaryMediaExtractor {
  Future<String?> ensureMediaAssets({
    required String dictionaryPath,
    required String dictionaryId,
    required String? cachedFilePath,
  }) async {
    final targetDir = await _prepareTargetDirectory(
      dictionaryId: dictionaryId,
      cachedFilePath: cachedFilePath,
    );
    if (targetDir == null) return null;

    final archivePath = await _ensureLocalArchive(
      dictionaryPath: dictionaryPath,
      targetDir: targetDir,
      dictionaryId: dictionaryId,
    );

    if (archivePath == null) {
      if (await targetDir.exists()) {
        await targetDir.delete(recursive: true);
      }
      return null;
    }

    return targetDir.path;
  }

  Future<String?> extractEmbeddedMedia({
    required String dictionaryPath,
    required String dictionaryId,
    required String? cachedFilePath,
    Directory? reuseExistingDirectory,
  }) async {
    final targetDir = reuseExistingDirectory ??
        await _prepareTargetDirectory(
          dictionaryId: dictionaryId,
          cachedFilePath: cachedFilePath,
        );
    if (targetDir == null) return null;

    final archivePath = await _ensureLocalArchive(
      dictionaryPath: dictionaryPath,
      targetDir: targetDir,
      dictionaryId: dictionaryId,
    );
    return archivePath == null ? null : targetDir.path;
  }

  Future<String?> extractSidecarZip({
    required String dictionaryPath,
    required String dictionaryId,
    required String? cachedFilePath,
    Directory? reuseExistingDirectory,
  }) async {
    final targetDir = reuseExistingDirectory ??
        await _prepareTargetDirectory(
          dictionaryId: dictionaryId,
          cachedFilePath: cachedFilePath,
        );
    if (targetDir == null) return null;

    final archivePath = await _copySidecarArchiveIfPresent(
      dictionaryPath: dictionaryPath,
      targetDir: targetDir,
      dictionaryId: dictionaryId,
    );
    return archivePath == null ? null : targetDir.path;
  }

  Future<Directory?> _prepareTargetDirectory({
    required String dictionaryId,
    required String? cachedFilePath,
  }) async {
    final mediaDirPath = cachedFilePath != null
        ? '${File(cachedFilePath).parent.path}${Platform.pathSeparator}${dictionaryId}_media'
        : '${Directory.systemTemp.path}${Platform.pathSeparator}dartlingvo_${dictionaryId}_media';

    final mediaDir = Directory(mediaDirPath);
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    return mediaDir;
  }

  Future<String?> _ensureLocalArchive({
    required String dictionaryPath,
    required Directory targetDir,
    required String dictionaryId,
  }) async {
    final existingArchive = _findArchiveInDirectory(targetDir);
    if (existingArchive != null) {
      return existingArchive;
    }

    final sidecar = await _copySidecarArchiveIfPresent(
      dictionaryPath: dictionaryPath,
      targetDir: targetDir,
      dictionaryId: dictionaryId,
    );
    if (sidecar != null) {
      return sidecar;
    }

    return _buildEmbeddedMediaArchive(
      dictionaryPath: dictionaryPath,
      targetDir: targetDir,
      dictionaryId: dictionaryId,
    );
  }

  Future<String?> _copySidecarArchiveIfPresent({
    required String dictionaryPath,
    required Directory targetDir,
    required String dictionaryId,
  }) async {
    final sourceArchive = await _findSidecarArchive(dictionaryPath);
    if (sourceArchive == null) return null;

    final targetArchive = _targetArchivePath(targetDir, dictionaryId);
    final targetFile = File(targetArchive);
    if (await targetFile.exists()) {
      return targetFile.path;
    }

    await targetFile.parent.create(recursive: true);
    await File(sourceArchive).copy(targetFile.path);
    return targetFile.path;
  }

  Future<String?> _buildEmbeddedMediaArchive({
    required String dictionaryPath,
    required Directory targetDir,
    required String dictionaryId,
  }) async {
    final targetArchive = _targetArchivePath(targetDir, dictionaryId);
    final targetFile = File(targetArchive);
    if (await targetFile.exists()) {
      return targetFile.path;
    }

    final reader = await LsdOverlayReader.open(dictionaryPath);
    if (reader == null) {
      return null;
    }

    final headings = await reader.readHeadings();
    if (headings.isEmpty) {
      return null;
    }

    final output = OutputFileStream(targetFile.path);
    final encoder = ZipEncoder();
    encoder.startEncode(output, level: 1);

    var added = 0;
    for (final heading in headings) {
      final safeName = _safeRelativePath(heading.name);
      if (safeName.isEmpty) {
        continue;
      }

      try {
        final bytes = await reader.readEntry(heading);
        if (bytes.isEmpty) {
          continue;
        }

        final archiveFile = ArchiveFile.stream(
          safeName,
          bytes.length,
          InputStream(bytes),
        );
        archiveFile.compress = true;
        archiveFile.lastModTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        encoder.addFile(archiveFile);
        added++;
      } catch (e) {
        debugPrint('[MediaExtractor] failed to stage embedded entry ${heading.name}: $e');
      }
    }

    encoder.endEncode();
    output.closeSync();

    if (added == 0) {
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      return null;
    }

    return targetFile.path;
  }

  Future<String?> _findSidecarArchive(String dictionaryPath) async {
    final sourceFile = File(dictionaryPath);
    final directory = sourceFile.parent;
    final fileName = sourceFile.uri.pathSegments.last;
    final baseName = p.basenameWithoutExtension(fileName);
    final candidates = <String>[
      p.join(directory.path, '$fileName.files.zip'),
      p.join(directory.path, '$baseName.files.zip'),
      p.join(directory.path, '$baseName.dsl.files.zip'),
      p.join(directory.path, '$baseName.lsd.files.zip'),
    ];

    for (final candidate in candidates) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
    return null;
  }

  String? _findArchiveInDirectory(Directory directory) {
    final entries = directory.listSync(followLinks: false);
    for (final entity in entries) {
      if (entity is! File) continue;
      if (entity.path.toLowerCase().endsWith('.files.zip')) {
        return entity.path;
      }
    }
    return null;
  }

  String _targetArchivePath(Directory targetDir, String dictionaryId) {
    return p.join(targetDir.path, '$dictionaryId.files.zip');
  }

  String _safeRelativePath(String name) {
    var normalized = name.trim().replaceAll('\\', '/');
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }

    final parts = normalized.split('/');
    final sanitized = parts
        .where((part) => part.isNotEmpty)
        .map((part) => part
            .replaceAll(RegExp(r'[<>:"|?*]'), '_')
            .replaceAll(RegExp(r'\s+$'), '')
            .replaceAll(RegExp(r'^\s+'), ''))
        .where((part) => part.isNotEmpty)
        .toList();
    return sanitized.join('/');
  }
}
