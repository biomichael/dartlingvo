import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/dictionary.dart';
import '../models/dictionary_cache_snapshot.dart';
import '../models/dictionary_index_snapshot.dart';
import '../models/dictionary_entry.dart';
import '../models/resolved_media.dart';
import '../index/word_index.dart';
import '../parsing/dsl_stream_reader.dart';
import '../parsing/lsd_decoder_dart.dart';
import '../parsing/lsd_overlay_reader.dart';

class DictionaryManager extends ChangeNotifier {
  static const _storageFolderName = 'dartlingvo_dictionaries';
  static const _manifestFileName = 'manifest.json';
  static const _dlcMagic = 0x444C4442;

  final List<Dictionary> _dictionaries = [];
  final WordIndex _wordIndex = WordIndex();
  final Map<String, List<DictionaryEntry>> _entriesCache = {};
  final Set<String> _loadedEntryDictionaryIds = {};
  final Map<String, _EmbeddedMediaIndex> _embeddedMediaIndexCache = {};
  final Map<String, Map<String, ResolvedMedia>> _resolvedMediaCache = {};
  final Map<String, Future<void>> _embeddedMediaIndexWarmers = {};
  String? _activeDictionaryId;
  bool _restoredPersistedDictionaries = false;

  List<Dictionary> get dictionaries => List.unmodifiable(_dictionaries);
  WordIndex get wordIndex => _wordIndex;
  bool get hasDictionaries => _dictionaries.isNotEmpty;

  String? get activeDictionaryId => _activeDictionaryId;

  Dictionary? get activeDictionary {
    if (_activeDictionaryId == null) return null;
    try {
      return _dictionaries.firstWhere((d) => d.id == _activeDictionaryId);
    } catch (_) {
      return null;
    }
  }

  void setActiveDictionary(String? id) {
    _activeDictionaryId = id;
    notifyListeners();
    if (id != null) {
      final dictionary = _dictionaryById(id);
      if (dictionary != null) {
        unawaited(
          preloadEmbeddedMediaIndexForPath(
            dictionaryId: dictionary.id,
            sourcePath: dictionary.sourcePath,
            cachedFilePath: dictionary.cachedFilePath,
          ),
        );
      }
    }
  }

  Future<void> restorePersistedDictionaries() async {
    if (_restoredPersistedDictionaries) return;
    _restoredPersistedDictionaries = true;

    final persisted = await _readPersistedDictionaries();
    if (persisted.isEmpty) return;

    for (final record in persisted) {
      if (record.sourcePath.isEmpty) continue;
      unawaited(
        preloadEmbeddedMediaIndexForPath(
          dictionaryId: record.id,
          sourcePath: record.sourcePath,
          cachedFilePath: record.cachedFilePath,
        ),
      );
    }

    // Fast path: restore entire trie from global cache (single file read, instant)
    if (await _tryRestoreFromTrieCache(persisted)) {
      notifyListeners();
      return;
    }

    // Fallback: restore from per-dictionary index snapshots (rebuilds trie)
    for (final record in persisted) {
      try {
        final cachePath = record.cachedFilePath;
        if (cachePath == null) continue;

        List<WordIndexEntry>? indexEntries;

        // Try fast index snapshot first
        final indexSnapshot = await _readDictionaryIndexSnapshot(
          File(_indexCachePathFor(cachePath)),
        );
        if (indexSnapshot != null) {
          indexEntries = indexSnapshot.indexEntries;
        } else {
          // Fall back to full JSON cache snapshot (old dictionaries pre-date .index.json)
          final cacheSnapshot = await _readDictionaryCacheSnapshot(
            File(cachePath),
          );
          if (cacheSnapshot != null) {
            indexEntries = cacheSnapshot.entries.map((e) => WordIndexEntry(
              word: e.word,
              dictionaryId: record.id,
              dictionaryName: record.name,
              entryIndex: e.index,
            )).toList(growable: false);
          }
        }

        if (indexEntries == null || indexEntries.isEmpty) {
          debugPrint('No cached data for ${record.name}, skipping');
          continue;
        }

        _addDictionaryRestored(record, indexEntries);
      } catch (e) {
        debugPrint('Failed to restore dictionary ${record.name}: $e');
      }
    }

      if (_dictionaries.isNotEmpty) {
        if (!Platform.isIOS) {
          await _writeGlobalTrieCache();
        }
        notifyListeners();
      }
  }

  Future<int> loadLsdFile(
    String filePath, {
    String? sourcePath,
    bool persist = true,
  }) async {
    try {
      debugPrint('[DictionaryManager] loadLsdFile start filePath=$filePath sourcePath=$sourcePath persist=$persist');
      final originalPath = _canonicalizePath(sourcePath ?? filePath);
      debugPrint('[DictionaryManager] normalized lsd path=$originalPath');
      final existing = _dictionaryByFilePath(originalPath);
      if (existing != null) {
        debugPrint('[DictionaryManager] existing dictionary found id=${existing.id} name=${existing.name}');
        await _refreshDictionaryMediaIfNeeded(existing);
        debugPrint('[DictionaryManager] loadLsdFile reused existing dictionary id=${existing.id} mediaDir=${existing.mediaDirectoryPath}');
        setActiveDictionary(existing.id);
        return existing.wordCount;
      }

      final id = 'dict_${DateTime.now().millisecondsSinceEpoch}';
      final decoder = LsdDecoderDart(filePath, dictionaryId: id);
      final result = await decoder.decode();

      final dictName = result.name.isNotEmpty ? result.name : 'Dictionary';
      final entries = result.entries;
      final persistSnapshot = persist && !Platform.isIOS && !Platform.isAndroid && !Platform.isWindows;
      final persistCaches = persist;

      final cachedFilePath = persist ? await _cachePathFor(filePath, id) : null;
      final cachedIndexFilePath = persist && cachedFilePath != null
          ? _indexCachePathFor(cachedFilePath)
          : null;
      debugPrint('[DictionaryManager] assigned id=$id dictName="$dictName" cachedFilePath=$cachedFilePath indexCachePath=$cachedIndexFilePath');
      final dictionary = Dictionary(
        id: id,
        name: dictName,
        filePath: originalPath,
        sourcePath: originalPath,
        cachedFilePath: cachedFilePath,
        mediaDirectoryPath: null,
        wordCount: entries.length,
        displayOrder: _dictionaries.length,
      );

      final normalized = _addDictionary(dictionary, entries, persistManifest: persist);
      debugPrint('[DictionaryManager] dictionary added id=$id entries=${normalized.length} wordCount=${dictionary.wordCount}');

      if (persist) {
        await _persistDictionaryArtifacts(
          dictionary: dictionary,
          entries: normalized,
          cachedFilePath: cachedFilePath,
          cachedIndexFilePath: cachedIndexFilePath,
          persistSnapshot: persistSnapshot,
          persistCaches: persistCaches,
        );
      }

      unawaited(preloadEmbeddedMediaIndex(id));
      debugPrint('[DictionaryManager] loadLsdFile complete id=$id');
      return normalized.length;
    } catch (e) {
      debugPrint('[DictionaryManager] loadLsdFile failed: $e');
      rethrow;
    }
  }

  Future<int> loadDslFile(
    String filePath, {
    String? sourcePath,
    bool persist = true,
  }) async {
    try {
      debugPrint('[DictionaryManager] loadDslFile start filePath=$filePath sourcePath=$sourcePath persist=$persist');
      final originalPath = _canonicalizePath(sourcePath ?? filePath);
      debugPrint('[DictionaryManager] normalized dsl path=$originalPath');
      final existing = _dictionaryByFilePath(originalPath);
      if (existing != null) {
        debugPrint('[DictionaryManager] existing dictionary found id=${existing.id} name=${existing.name}');
        await _refreshDictionaryMediaIfNeeded(existing);
        debugPrint('[DictionaryManager] loadDslFile reused existing dictionary id=${existing.id} mediaDir=${existing.mediaDirectoryPath}');
        setActiveDictionary(existing.id);
        return existing.wordCount;
      }

      final id = 'dict_${DateTime.now().millisecondsSinceEpoch}';
      final reader = DslStreamReader(dictionaryId: id, dictionaryName: '');
      final dictName = await DslStreamReader.extractName(filePath);

      final entries = await reader.readAll(filePath);

      final dictNameResolved = dictName.isNotEmpty ? dictName : 'Dictionary';
      final persistSnapshot = persist && !Platform.isIOS && !Platform.isAndroid && !Platform.isWindows;
      final persistCaches = persist;
      final cachedFilePath = persist ? await _cachePathFor(filePath, id) : null;
      final cachedIndexFilePath = persist && cachedFilePath != null
          ? _indexCachePathFor(cachedFilePath)
          : null;
      debugPrint('[DictionaryManager] assigned id=$id dictName="$dictNameResolved" cachedFilePath=$cachedFilePath indexCachePath=$cachedIndexFilePath');
      final dictionary = Dictionary(
        id: id,
        name: dictNameResolved,
        filePath: originalPath,
        sourcePath: originalPath,
        cachedFilePath: cachedFilePath,
        mediaDirectoryPath: null,
        wordCount: entries.length,
        displayOrder: _dictionaries.length,
      );

      final normalized = _addDictionary(dictionary, entries, persistManifest: persist);
      debugPrint('[DictionaryManager] dictionary added id=$id entries=${normalized.length} wordCount=${dictionary.wordCount}');

      if (persist) {
        await _persistDictionaryArtifacts(
          dictionary: dictionary,
          entries: normalized,
          cachedFilePath: cachedFilePath,
          cachedIndexFilePath: cachedIndexFilePath,
          persistSnapshot: persistSnapshot,
          persistCaches: persistCaches,
        );
      }

      unawaited(preloadEmbeddedMediaIndex(id));
      debugPrint('[DictionaryManager] loadDslFile complete id=$id');
      return normalized.length;
    } catch (e) {
      debugPrint('[DictionaryManager] loadDslFile failed: $e');
      rethrow;
    }
  }

  DictionaryEntry? getEntry(String dictionaryId, String word) {
    // If already bulk-loaded, use the complete cache (case-sensitive then insensitive)
    if (_loadedEntryDictionaryIds.contains(dictionaryId)) {
      final entries = _entriesCache[dictionaryId];
      if (entries != null) {
        for (final entry in entries) {
          if (entry.word == word) return entry;
        }
        final lower = word.toLowerCase();
        for (final entry in entries) {
          if (entry.word.toLowerCase() == lower) return entry;
        }
      }
    }

    // DLC single-entry load (fast path, preserves case)
    final wordIndexEntry = _findWordIndexEntry(dictionaryId, word);
    if (wordIndexEntry.isNotEmpty) {
      final entry = _loadSingleEntryByIndex(
        dictionaryId,
        wordIndexEntry['index'] as int,
      );
      if (entry != null) {
        _cacheSingleEntry(dictionaryId, entry);
        return entry;
      }
    }

    // Fallback: bulk load and scan
    if (!_ensureDictionaryEntriesLoaded(dictionaryId)) return null;

    final entries = _entriesCache[dictionaryId];
    if (entries == null) return null;

    for (final entry in entries) {
      if (entry.word == word) return entry;
    }

    final lower = word.toLowerCase();
    for (final entry in entries) {
      if (entry.word.toLowerCase() == lower) return entry;
    }

    return null;
  }

  DictionaryEntry? getEntryByIndex(String dictionaryId, int index) {
    // Fast path: load single entry from DLC cache
    final entry = _loadSingleEntryByIndex(dictionaryId, index);
    if (entry != null) {
      _cacheSingleEntry(dictionaryId, entry);
      return entry;
    }

    // Fallback: bulk load
    if (!_ensureDictionaryEntriesLoaded(dictionaryId)) return null;

    final entries = _entriesCache[dictionaryId];
    if (entries == null || index < 0 || index >= entries.length) return null;
    return entries[index];
  }

  void _cacheSingleEntry(String dictionaryId, DictionaryEntry entry) {
    final existing = _entriesCache[dictionaryId];
    if (existing == null) {
      _entriesCache[dictionaryId] = [entry];
    } else if (!existing.any((e) => e.index == entry.index)) {
      existing.add(entry);
    }
  }

  List<DictionaryEntry> getEntriesForWord(String word, {String? dictionaryId}) {
    final results = <DictionaryEntry>[];

    final indexMatches = <WordIndexEntry>[];
    for (final entry in _wordIndex.entries) {
      if (dictionaryId != null && entry.dictionaryId != dictionaryId) {
        continue;
      }
      if (entry.word == word) {
        indexMatches.add(entry);
      }
    }

    if (indexMatches.isEmpty) {
      final lower = word.toLowerCase();
      for (final entry in _wordIndex.entries) {
        if (dictionaryId != null && entry.dictionaryId != dictionaryId) {
          continue;
        }
        if (entry.word.toLowerCase() == lower) {
          indexMatches.add(entry);
        }
      }
    }

    for (final indexEntry in indexMatches) {
      final entry = getEntryByIndex(
        indexEntry.dictionaryId,
        indexEntry.entryIndex,
      );
      if (entry != null) {
        results.add(entry);
      }
    }

    // Sort by dictionary display order
    final orderMap = <String, int>{};
    for (var i = 0; i < _dictionaries.length; i++) {
      orderMap[_dictionaries[i].id] = _dictionaries[i].displayOrder;
    }
    results.sort((a, b) {
      final oa = orderMap[a.dictionaryId] ?? 9999;
      final ob = orderMap[b.dictionaryId] ?? 9999;
      return oa.compareTo(ob);
    });

    return results;
  }

  Future<void> removeDictionary(String id) async {
    Dictionary? dictionary;
    for (final candidate in _dictionaries) {
      if (candidate.id == id) {
        dictionary = candidate;
        break;
      }
    }
    _dictionaries.removeWhere((d) => d.id == id);
    _entriesCache.remove(id);
    _embeddedMediaIndexCache.remove(id);
    _resolvedMediaCache.remove(id);

    if (_activeDictionaryId == id) {
      _activeDictionaryId = _dictionaries.isNotEmpty ? _dictionaries.first.id : null;
    }

    _wordIndex.removeWhere((entry) => entry.dictionaryId == id);

    if (dictionary != null) {
      final cachePath = dictionary.cachedFilePath;
      if (cachePath != null) {
        final cacheFile = File(cachePath);
        if (await cacheFile.exists()) {
          await cacheFile.delete();
        }
        final dlcFile = File(_dlcCachePathFor(cachePath));
        if (await dlcFile.exists()) {
          await dlcFile.delete();
        }
        final indexCacheFile = File(_indexCachePathFor(cachePath));
        if (await indexCacheFile.exists()) {
          await indexCacheFile.delete();
        }
      }
      final mediaPath = dictionary.mediaDirectoryPath;
      if (mediaPath != null) {
        final mediaDir = Directory(mediaPath);
        if (await mediaDir.exists()) {
          await mediaDir.delete(recursive: true);
        }
      }
    }

    await _writeGlobalTrieCache();
    await _writePersistedDictionaries();

    notifyListeners();
  }

  Future<void> clearAll() async {
    for (final dictionary in _dictionaries) {
      final cachePath = dictionary.cachedFilePath;
      if (cachePath == null) continue;
      final cacheFile = File(cachePath);
      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }
      final dlcFile = File(_dlcCachePathFor(cachePath));
      if (await dlcFile.exists()) {
        await dlcFile.delete();
      }
      final indexCacheFile = File(_indexCachePathFor(cachePath));
      if (await indexCacheFile.exists()) {
        await indexCacheFile.delete();
      }
      final mediaPath = dictionary.mediaDirectoryPath;
      if (mediaPath != null) {
        final mediaDir = Directory(mediaPath);
        if (await mediaDir.exists()) {
          await mediaDir.delete(recursive: true);
        }
      }
    }

    _dictionaries.clear();
    _entriesCache.clear();
    _loadedEntryDictionaryIds.clear();
    _wordIndex.clear();
    _embeddedMediaIndexCache.clear();
    _resolvedMediaCache.clear();
    _activeDictionaryId = null;

    final storageDir = await _storageDirectory();
    final manifest = File('${storageDir.path}${Platform.pathSeparator}$_manifestFileName');
    if (await manifest.exists()) {
      await manifest.delete();
    }
    final trieCache = File('${storageDir.path}${Platform.pathSeparator}trie_cache.json');
    if (await trieCache.exists()) {
      await trieCache.delete();
    }

    notifyListeners();
  }

  int get totalWordCount =>
      _dictionaries.fold(0, (sum, d) => sum + d.wordCount);

  Future<void> reorderDictionaries(int oldIndex, int newIndex) async {
    // ReorderableListView gives newIndex as if the item is already removed
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= _dictionaries.length) return;
    if (newIndex < 0 || newIndex >= _dictionaries.length) return;

    final item = _dictionaries.removeAt(oldIndex);
    _dictionaries.insert(newIndex, item);

    for (var i = 0; i < _dictionaries.length; i++) {
      _dictionaries[i] = _dictionaries[i].copyWith(displayOrder: i);
    }

    await _writePersistedDictionaries();
    notifyListeners();
  }

  Dictionary? _dictionaryByFilePath(String filePath) {
    final normalized = _normalizePath(filePath);
    for (final dictionary in _dictionaries) {
      if (_normalizePath(dictionary.filePath) == normalized ||
          _normalizePath(dictionary.sourcePath) == normalized) {
        return dictionary;
      }
    }
    return null;
  }

  String _canonicalizePath(String path) {
    try {
      return File(path).resolveSymbolicLinksSync();
    } catch (_) {
      return File(path).absolute.path;
    }
  }

  Future<String> _cachePathFor(String filePath, String id) async {
    final storageDir = await _storageDirectory();
    final fileName = File(filePath).uri.pathSegments.last;
    return '${storageDir.path}${Platform.pathSeparator}${id}_$fileName';
  }

  Future<void> _refreshDictionaryMediaIfNeeded(Dictionary dictionary) async {
    // Embedded media is resolved directly from the source .lsd on click.
    // Nothing to refresh here.
  }

  Future<Directory> _storageDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final storageDir = Directory('${supportDir.path}${Platform.pathSeparator}$_storageFolderName');
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }
    return storageDir;
  }

  Future<void> _writePersistedDictionaries() async {
    final storageDir = await _storageDirectory();
    final manifestFile = File('${storageDir.path}${Platform.pathSeparator}$_manifestFileName');
    final payload = {
      'dictionaries': _dictionaries.map((dictionary) => dictionary.toJson()).toList(),
    };
    await manifestFile.writeAsString(jsonEncode(payload));
  }

  Future<List<Dictionary>> _readPersistedDictionaries() async {
    final storageDir = await _storageDirectory();
    final manifestFile = File('${storageDir.path}${Platform.pathSeparator}$_manifestFileName');
    if (!await manifestFile.exists()) return [];

    try {
      final content = await manifestFile.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      final dictionaries = decoded['dictionaries'] as List<dynamic>? ?? [];
      return dictionaries.map((entry) {
        return Dictionary.fromJson(entry as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      debugPrint('Failed to read dictionary manifest: $e');
      return [];
    }
  }

  List<DictionaryEntry> _addDictionary(
    Dictionary dictionary,
    List<DictionaryEntry> entries, {
    bool persistManifest = true,
  }) {
    final normalizedEntries = _entriesMatchDictionary(entries, dictionary)
        ? entries
        : entries
            .map(
              (entry) => DictionaryEntry(
                word: entry.word,
                definitions: entry.definitions,
                dictionaryId: dictionary.id,
                dictionaryName: dictionary.name,
                index: entry.index,
              ),
            )
            .toList(growable: false);

    _dictionaries.add(dictionary);
    _entriesCache[dictionary.id] = normalizedEntries;
    _loadedEntryDictionaryIds.add(dictionary.id);

    final indexEntries = normalizedEntries.map((entry) => WordIndexEntry(
          word: entry.word,
          dictionaryId: dictionary.id,
          dictionaryName: dictionary.name,
          entryIndex: entry.index,
        ));
    _wordIndex.addEntries(indexEntries);

    _activeDictionaryId ??= dictionary.id;

    if (persistManifest) {
      notifyListeners();
    }

    return normalizedEntries;
  }

  bool _entriesMatchDictionary(
    List<DictionaryEntry> entries,
    Dictionary dictionary,
  ) {
    for (final entry in entries) {
      if (entry.dictionaryId != dictionary.id ||
          entry.dictionaryName != dictionary.name) {
        return false;
      }
    }
    return true;
  }

  Future<void> _writeDictionarySnapshot(
    File file,
    DictionaryCacheSnapshot snapshot,
  ) async {
    await file.writeAsString(jsonEncode(snapshot.toJson()));
  }

  Future<void> _persistDictionaryArtifacts({
    required Dictionary dictionary,
    required List<DictionaryEntry> entries,
    required String? cachedFilePath,
    required String? cachedIndexFilePath,
    required bool persistSnapshot,
    required bool persistCaches,
  }) async {
    try {
      await Future<void>.delayed(Duration.zero);

      if (persistSnapshot && cachedFilePath != null) {
        debugPrint('[DictionaryManager] writing JSON cache snapshot path=$cachedFilePath');
        await _writeDictionarySnapshot(
          File(cachedFilePath),
          DictionaryCacheSnapshot(dictionary: dictionary, entries: entries),
        );
      }

      if (persistCaches && cachedFilePath != null) {
        debugPrint('[DictionaryManager] writing DLC and index caches path=$cachedFilePath');
        await writeDlcCache(
          File(_dlcCachePathFor(cachedFilePath)),
          dictionary,
          entries,
        );
        if (cachedIndexFilePath != null) {
          await _writeDictionaryIndexSnapshot(
            File(cachedIndexFilePath),
            dictionary,
            entries,
          );
        }
      }

      if (!Platform.isIOS) {
        debugPrint('[DictionaryManager] writing global trie cache');
        await _writeGlobalTrieCache();
      }

      debugPrint('[DictionaryManager] writing persisted dictionary manifest');
      await _writePersistedDictionaries();
    } catch (e) {
      debugPrint('[DictionaryManager] background persistence failed: $e');
    }
  }

  void _addDictionaryRestored(
    Dictionary dictionary,
    List<WordIndexEntry> indexEntries,
  ) {
    _dictionaries.add(dictionary);
    _activeDictionaryId ??= dictionary.id;
    _wordIndex.addEntries(indexEntries);
  }

  Future<bool> _tryRestoreFromTrieCache(List<Dictionary> persisted) async {
    final storageDir = await _storageDirectory();
    final trieFile = File(
      '${storageDir.path}${Platform.pathSeparator}trie_cache.json',
    );
    if (!await trieFile.exists()) return false;

    try {
      final content = await trieFile.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      _wordIndex.deserializeTrie(decoded);

      for (final record in persisted) {
        _dictionaries.add(record);
        _activeDictionaryId ??= record.id;
      }
      return true;
    } catch (e) {
      debugPrint('Failed to restore trie cache: $e');
      return false;
    }
  }

  Future<void> _writeGlobalTrieCache() async {
    final storageDir = await _storageDirectory();
    final trieFile = File(
      '${storageDir.path}${Platform.pathSeparator}trie_cache.json',
    );
    await trieFile.writeAsString(jsonEncode(_wordIndex.serializeTrie()));
  }

  Future<void> _writeDictionaryIndexSnapshot(
    File file,
    Dictionary dictionary,
    List<DictionaryEntry> entries,
  ) async {
    final sink = file.openWrite();
    try {
      sink.write('{"dictionary":');
      sink.write(jsonEncode(dictionary.toJson()));
      sink.write(',"indexEntries":[');
      for (var i = 0; i < entries.length; i++) {
        if (i > 0) sink.write(',');
        final entry = entries[i];
        sink.write(jsonEncode({
          'word': entry.word,
          'dictionaryId': dictionary.id,
          'dictionaryName': dictionary.name,
          'entryIndex': entry.index,
        }));
        if (i % 1000 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      sink.write(']}');
    } finally {
      await sink.flush();
      await sink.close();
    }
  }

  Future<DictionaryCacheSnapshot?> _readDictionaryCacheSnapshot(
    File cacheFile,
  ) async {
    try {
      if (!await cacheFile.exists()) return null;
      final content = await cacheFile.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      return DictionaryCacheSnapshot.fromJson(decoded);
    } catch (e) {
      debugPrint('Failed to read dictionary cache snapshot: $e');
      return null;
    }
  }

  Future<DictionaryIndexSnapshot?> _readDictionaryIndexSnapshot(
    File indexFile,
  ) async {
    try {
      if (!await indexFile.exists()) return null;
      final content = await indexFile.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      return DictionaryIndexSnapshot.fromJson(decoded);
    } catch (e) {
      debugPrint('Failed to read dictionary index snapshot: $e');
      return null;
    }
  }

  bool _ensureDictionaryEntriesLoaded(String dictionaryId) {
    if (_loadedEntryDictionaryIds.contains(dictionaryId)) {
      return true;
    }

    final dictionary = _dictionaryById(dictionaryId);
    final cachePath = dictionary?.cachedFilePath;
    if (dictionary == null || cachePath == null) return false;

    // Try binary DLC format first (fastest)
    final dlcPath = _dlcCachePathFor(cachePath);
    if (File(dlcPath).existsSync()) {
      final entries = _readAllEntriesFromDlcSync(dlcPath);
      if (entries != null) {
        final normalized = entries
            .map((e) => DictionaryEntry(
                  word: e.word,
                  definitions: e.definitions,
                  dictionaryId: dictionary.id,
                  dictionaryName: dictionary.name,
                  index: e.index,
                ))
            .toList(growable: false);
        _entriesCache[dictionary.id] = normalized;
        _loadedEntryDictionaryIds.add(dictionary.id);
        return true;
      }
    }

    // Fallback to old JSON format
    final cacheFile = File(cachePath);
    if (!cacheFile.existsSync()) return false;

    try {
      final decoded = _readDictionaryCacheJsonSync(cacheFile.path);
      final snapshot = DictionaryCacheSnapshot.fromJson(decoded);
      final normalizedEntries = snapshot.entries
          .map(
            (entry) => DictionaryEntry(
              word: entry.word,
              definitions: entry.definitions,
              dictionaryId: dictionary.id,
              dictionaryName: dictionary.name,
              index: entry.index,
            ),
          )
          .toList(growable: false);

      _entriesCache[dictionary.id] = normalizedEntries;
      _loadedEntryDictionaryIds.add(dictionary.id);

      // Generate .dlc cache for future fast single-entry access
      if (!File(dlcPath).existsSync()) {
        writeDlcCache(File(dlcPath), dictionary, normalizedEntries);
      }

      return true;
    } catch (e) {
      debugPrint('Failed to lazy-load dictionary entries ${dictionary.id}: $e');
      return false;
    }
  }

  DictionaryEntry? _loadSingleEntryByIndex(String dictionaryId, int entryIndex) {
    final dictionary = _dictionaryById(dictionaryId);
    final cachePath = dictionary?.cachedFilePath;
    if (dictionary == null || cachePath == null) return null;

    final dlcPath = _dlcCachePathFor(cachePath);
    if (!File(dlcPath).existsSync()) return null;

    return _readSingleEntryFromDlcSync(dlcPath, entryIndex);
  }

  Map<String, dynamic> _findWordIndexEntry(String dictionaryId, String word) {
    // Case-sensitive exact match first
    for (final entry in _wordIndex.entries) {
      if (entry.dictionaryId == dictionaryId && entry.word == word) {
        return {'index': entry.entryIndex, 'word': entry.word};
      }
    }
    // Fallback to case-insensitive
    final lower = word.toLowerCase();
    for (final entry in _wordIndex.entries) {
      if (entry.dictionaryId == dictionaryId && entry.word.toLowerCase() == lower) {
        return {'index': entry.entryIndex, 'word': entry.word};
      }
    }
    return {};
  }

  Dictionary? _dictionaryById(String id) {
    for (final dictionary in _dictionaries) {
      if (dictionary.id == id) {
        return dictionary;
      }
    }
    return null;
  }

  Dictionary? dictionaryById(String id) => _dictionaryById(id);

  ResolvedMedia? resolveMediaReference(DictionaryEntry? entry, String mediaText) {
    if (entry == null) return null;

    final dictionary = _dictionaryById(entry.dictionaryId);
    if (dictionary == null) return null;

    final media = _resolveEmbeddedMedia(dictionary, mediaText.trim(), entry.word);
    if (media != null) {
      return media;
    }

    return null;
  }

  ResolvedMedia? _resolveEmbeddedMedia(
    Dictionary dictionary,
    String mediaText,
    String? entryWord,
  ) {
    final index = _loadEmbeddedMediaIndex(dictionary);
    if (index == null) return null;

    final lookupKeys = _mediaLookupKeys(mediaText, entryWord);
    for (final key in lookupKeys) {
      final heading = index.headingsByKey[key];
      if (heading == null) continue;

      final cacheKey = _resolvedMediaCacheKey(mediaText, entryWord, heading.name);
      final cached = _resolvedMediaCache[dictionary.id]?[cacheKey];
      if (cached != null) {
        return cached;
      }

      try {
        final bytes = index.reader.readEntrySync(heading);
        if (bytes.isEmpty) continue;

        final media = ResolvedMedia(
          name: heading.name,
          bytes: Uint8List.fromList(bytes),
        );
        _resolvedMediaCache.putIfAbsent(dictionary.id, () => <String, ResolvedMedia>{})[cacheKey] = media;
        return media;
      } catch (e) {
        debugPrint('Failed to read media entry ${heading.name} for ${dictionary.name}: $e');
      }
    }

    return null;
  }

  _EmbeddedMediaIndex? _loadEmbeddedMediaIndex(Dictionary dictionary) {
    final cached = _embeddedMediaIndexCache[dictionary.id];
    if (cached != null) {
      return cached;
    }

    final reader = LsdOverlayReader.openSync(dictionary.sourcePath);
    if (reader == null) {
      return null;
    }

    final headings = reader.readHeadingsSync();
    if (headings.isEmpty) {
      return null;
    }

    return _cacheEmbeddedMediaIndex(
      dictionaryId: dictionary.id,
      reader: reader,
      headings: headings,
    );
  }

  Future<void> preloadEmbeddedMediaIndex(String dictionaryId) async {
    final dictionary = _dictionaryById(dictionaryId);
    if (dictionary == null) {
      return;
    }

    return preloadEmbeddedMediaIndexForPath(
      dictionaryId: dictionary.id,
      sourcePath: dictionary.sourcePath,
      cachedFilePath: dictionary.cachedFilePath,
    );
  }

  Future<void> preloadEmbeddedMediaIndexForPath({
    required String dictionaryId,
    required String sourcePath,
    String? cachedFilePath,
  }) async {
    if (_embeddedMediaIndexCache.containsKey(dictionaryId)) {
      return;
    }

    final existing = _embeddedMediaIndexWarmers[dictionaryId];
    if (existing != null) {
      return existing;
    }

    final future = () async {
      try {
        final reader = await LsdOverlayReader.open(sourcePath);
        if (reader == null) return;

        final headings = await reader.readHeadings();
        if (headings.isEmpty) return;

        _cacheEmbeddedMediaIndex(
          dictionaryId: dictionaryId,
          reader: reader,
          headings: headings,
        );
      } catch (e) {
        debugPrint('[DictionaryManager] preloadEmbeddedMediaIndex failed for $dictionaryId: $e');
      } finally {
        _embeddedMediaIndexWarmers.remove(dictionaryId);
      }
    }();

    _embeddedMediaIndexWarmers[dictionaryId] = future;
    return future;
  }

  Future<void> preloadEmbeddedMediaIndexes({String? preferredDictionaryId}) async {
    final ordered = <Dictionary>[];
    if (preferredDictionaryId != null) {
      final preferred = _dictionaryById(preferredDictionaryId);
      if (preferred != null) {
        ordered.add(preferred);
      }
    }
    for (final dictionary in _dictionaries) {
      if (dictionary.id == preferredDictionaryId) continue;
      ordered.add(dictionary);
    }

    for (final dictionary in ordered) {
      unawaited(
        preloadEmbeddedMediaIndexForPath(
          dictionaryId: dictionary.id,
          sourcePath: dictionary.sourcePath,
          cachedFilePath: dictionary.cachedFilePath,
        ),
      );
    }
  }

  _EmbeddedMediaIndex _cacheEmbeddedMediaIndex({
    required String dictionaryId,
    required LsdOverlayReader reader,
    required List<OverlayHeading> headings,
  }) {
    final cached = _embeddedMediaIndexCache[dictionaryId];
    if (cached != null) {
      return cached;
    }

    final headingsByKey = <String, OverlayHeading>{};
    for (final heading in headings) {
      for (final key in _mediaLookupKeys(heading.name, null)) {
        headingsByKey.putIfAbsent(key, () => heading);
      }
    }

    final index = _EmbeddedMediaIndex(
      reader: reader,
      headingsByKey: headingsByKey,
    );
    _embeddedMediaIndexCache[dictionaryId] = index;
    return index;
  }

  List<String> _mediaLookupKeys(String mediaText, String? entryWord) {
    final relative = mediaText.trim();
    final baseName = p.basename(relative);
    final normalizedRelative = _normalizeMediaKey(relative);
    final normalizedBase = _normalizeMediaKey(baseName);
    final normalizedStem = _normalizedStem(normalizedBase);
    final entryWordKey = entryWord == null ? '' : _normalizeMediaKey(entryWord);
    final entryStem = _normalizedStem(entryWordKey);
    final ext = p.extension(baseName).toLowerCase();

    final keys = <String>{
      normalizedRelative,
      normalizedBase,
      normalizedStem,
      entryWordKey,
      entryStem,
      if (ext.isNotEmpty) '$normalizedBase$ext',
      if (ext.isNotEmpty) '$normalizedStem$ext',
    };
    keys.removeWhere((key) => key.isEmpty);
    return keys.toList(growable: false);
  }

  String _resolvedMediaCacheKey(
    String mediaText,
    String? entryWord,
    String headingName,
  ) {
    return '${_normalizeMediaKey(mediaText)}|${_normalizeMediaKey(entryWord ?? '')}|${_normalizeMediaKey(headingName)}';
  }

  String _normalizeMediaKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  String _normalizedStem(String key) {
    if (key.isEmpty) return '';
    var stem = key.replaceFirst(RegExp(r'\d+$'), '');
    for (final prefix in const ['ame', 'bre', 'us', 'uk', 'ukr', 'us1', 'us2', 'bre1', 'bre2']) {
      if (stem.startsWith(prefix) && stem.length > prefix.length + 2) {
        stem = stem.substring(prefix.length);
        break;
      }
    }
    return stem;
  }

  String _indexCachePathFor(String snapshotPath) {
    if (snapshotPath.toLowerCase().endsWith('.json')) {
      return '${snapshotPath.substring(0, snapshotPath.length - 5)}.index.json';
    }
    return '$snapshotPath.index.json';
  }

  String _dlcCachePathFor(String cachePath) => '$cachePath.dlc';

  static Map<String, dynamic> _readDictionaryCacheJsonSync(String filePath) {
    final content = File(filePath).readAsStringSync();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  // ── Binary DLC cache format ──────────────────────────────────────────
  //
  // [4 bytes] magic: 0x444C4442 ('DLDB')
  // [4 bytes] version: 1 (Uint32 LE)
  // [4 bytes] entry count (Uint32 LE)
  // [4 bytes] metadata JSON length (Uint32 LE)
  // [metadata_length bytes] metadata JSON (UTF-8)
  // [entry_count * 8 bytes] offset array (Uint64 LE each)
  //     offset[i] = byte offset of entry i's 4-byte length prefix
  // [entry data: length-prefixed JSON strings]
  //     for each entry:
  //       [4 bytes] JSON length (Uint32 LE)
  //       [length bytes] JSON data (UTF-8)

  static Future<void> writeDlcCache(
    File file,
    Dictionary dictionary,
    List<DictionaryEntry> entries,
  ) async {
    final metaBytes = utf8.encode(jsonEncode(dictionary.toJson()));
    final entryLengths = List<int>.filled(entries.length, 0);

    final headerSize = 16;
    final metaSectionLen = metaBytes.length;
    final offsetArraySize = entries.length * 8;

    for (var i = 0; i < entries.length; i++) {
      final jsonStr = jsonEncode(entries[i].toJson());
      final jsonBytes = utf8.encode(jsonStr);
      entryLengths[i] = jsonBytes.length;
      if (i % 500 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    final raf = file.openSync(mode: FileMode.write);
    try {
      final header = ByteData(16);
      header.setUint32(0, _dlcMagic, Endian.little);
      header.setUint32(4, 1, Endian.little);
      header.setUint32(8, entries.length, Endian.little);
      header.setUint32(12, metaBytes.length, Endian.little);
      raf.writeFromSync(header.buffer.asUint8List());
      raf.writeFromSync(metaBytes);

      var entryOffset = headerSize + metaSectionLen + offsetArraySize;
      for (var i = 0; i < entries.length; i++) {
        final offsetBytes = ByteData(8)..setUint64(0, entryOffset, Endian.little);
        raf.writeFromSync(offsetBytes.buffer.asUint8List());
        entryOffset += 4 + entryLengths[i];
      }

      for (var i = 0; i < entries.length; i++) {
        final jsonBytes = utf8.encode(jsonEncode(entries[i].toJson()));
        final lenBytes = ByteData(4)..setUint32(0, jsonBytes.length, Endian.little);
        raf.writeFromSync(lenBytes.buffer.asUint8List());
        raf.writeFromSync(jsonBytes);
        if (i % 500 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    } finally {
      raf.closeSync();
    }
  }

  static DictionaryEntry? _readSingleEntryFromDlcSync(
    String filePath,
    int entryIndex,
  ) {
    final file = File(filePath);
    if (!file.existsSync()) return null;
    try {
      final raf = file.openSync(mode: FileMode.read);
      try {
        // Read header: magic(4) + version(4) + count(4) + metaLen(4) = 16
        final header = raf.readSync(16);
        if (header.lengthInBytes < 16) return null;
        final headerView = ByteData.view(header.buffer);

        if (headerView.getUint32(0, Endian.little) != _dlcMagic) return null;
        final count = headerView.getUint32(8, Endian.little);
        final metaLen = headerView.getUint32(12, Endian.little);
        if (entryIndex < 0 || entryIndex >= count) return null;

        final offsetArrayStart = 16 + metaLen;
        // Seek to offset entry in the offset array
        raf.setPositionSync(offsetArrayStart + entryIndex * 8);
        final offsetBytes = raf.readSync(8);
        if (offsetBytes.lengthInBytes < 8) return null;
        final entryOffset = ByteData.view(offsetBytes.buffer).getUint64(0, Endian.little);

        // Read entry length prefix (4 bytes) at entryOffset
        raf.setPositionSync(entryOffset);
        final lenBytes = raf.readSync(4);
        if (lenBytes.lengthInBytes < 4) return null;
        final entryLen = ByteData.view(lenBytes.buffer).getUint32(0, Endian.little);

        // Read entry JSON
        raf.setPositionSync(entryOffset + 4);
        final entryBytes = raf.readSync(entryLen);
        if (entryBytes.lengthInBytes < entryLen) return null;
        final jsonStr = utf8.decode(entryBytes);
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        return DictionaryEntry.fromJson(decoded);
      } finally {
        raf.closeSync();
      }
    } catch (e) {
      debugPrint('DLC single-entry read failed: $e');
      return null;
    }
  }

  static List<DictionaryEntry>? _readAllEntriesFromDlcSync(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) return null;

    final bytes = file.readAsBytesSync();
    if (bytes.lengthInBytes < 16) return null;

    final view = ByteData.view(bytes.buffer);
    if (view.getUint32(0, Endian.little) != _dlcMagic) return null;

    final count = view.getUint32(8, Endian.little);
    final metaLen = view.getUint32(12, Endian.little);

    final offsetArrayStart = 16 + metaLen;
    final entries = <DictionaryEntry>[];
    for (var i = 0; i < count; i++) {
      final entryOffset = view.getUint64(offsetArrayStart + i * 8, Endian.little);
      final entryLen = view.getUint32(entryOffset, Endian.little);
      final entryStart = entryOffset + 4;
      final jsonStr = utf8.decode(bytes.sublist(entryStart, entryStart + entryLen));
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      entries.add(DictionaryEntry.fromJson(decoded));
    }
    return entries;
  }

  String _normalizePath(String path) {
    final absolutePath = _canonicalizePath(path);
    return Platform.isWindows ? absolutePath.toLowerCase() : absolutePath;
  }

  List<String> _collectMediaReferenceNames(List<DictionaryEntry> entries) {
    final refs = <String>{};
    for (final entry in entries) {
      for (final def in entry.definitions) {
        for (final segment in def.segments) {
          if (!segment.strikeThrough) {
            continue;
          }
          final text = segment.text.trim();
          if (text.isEmpty) {
            continue;
          }
          if (!_isMediaReferenceText(text)) {
            continue;
          }
          refs.add(text);
        }
      }
    }
    return refs.toList(growable: false);
  }

  bool _isMediaReferenceText(String text) {
    final fileName = p.basename(text);
    return RegExp(
      r'.+\.(bmp|gif|jpe?g|png|webp|wav|mp3|m4a|aac|ogg|flac|mp4|mov|mkv|webm|avi)$',
      caseSensitive: false,
    ).hasMatch(fileName);
  }
}

class _EmbeddedMediaIndex {
  final LsdOverlayReader reader;
  final Map<String, OverlayHeading> headingsByKey;

  const _EmbeddedMediaIndex({
    required this.reader,
    required this.headingsByKey,
  });
}
