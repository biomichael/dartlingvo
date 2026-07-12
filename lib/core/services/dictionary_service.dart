import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../managers/dictionary_manager.dart';

class DictionaryService {
  final DictionaryManager _manager;

  DictionaryService(this._manager);

  DictionaryManager get manager => _manager;

  Future<String?> pickAndLoadDictionary() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: _pickerType(),
        allowedExtensions: _pickerType() == FileType.custom ? ['lsd', 'dsl'] : null,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return null;

      final filePath = result.files.single.path;
      if (filePath == null) return null;

      final extension = p.extension(filePath).toLowerCase();

      switch (extension) {
        case '.lsd':
          await _manager.loadLsdFile(filePath);
          break;
        case '.dsl':
          await _manager.loadDslFile(filePath);
          break;
        default:
          throw Exception('Unsupported file format: $extension');
      }

      return filePath;
    } catch (e) {
      debugPrint('Failed to load dictionary: $e');
      rethrow;
    }
  }

  FileType _pickerType() {
    if (Platform.isAndroid || Platform.isIOS) {
      return FileType.any;
    }
    return FileType.custom;
  }

  Future<List<String>> loadDictionariesFromDirectory(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return [];

    final loaded = <String>[];
    final files = <File>[];

    await for (final entity in dir.list()) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (ext == '.lsd' || ext == '.dsl') {
          files.add(entity);
        }
      }
    }

    for (final file in files) {
      try {
        final ext = p.extension(file.path).toLowerCase();
        if (ext == '.lsd') {
          await _manager.loadLsdFile(file.path);
        } else if (ext == '.dsl') {
          await _manager.loadDslFile(file.path);
        }
        loaded.add(file.path);
      } catch (e) {
        debugPrint('Failed to load ${file.path}: $e');
      }
    }

    return loaded;
  }

  void removeDictionary(String id) {
    _manager.removeDictionary(id);
  }

  void clearAll() {
    _manager.clearAll();
  }
}
