import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/managers/dictionary_manager.dart';
import '../core/managers/lookup_tab_manager.dart';
import '../core/models/dictionary.dart';
import '../core/models/dictionary_entry.dart';
import '../core/models/word_search_result.dart';
import '../core/search/search_engine.dart';
import '../core/models/lookup_tab.dart';

final dictionaryManagerProvider =
    ChangeNotifierProvider<DictionaryManager>((ref) => DictionaryManager());

final lookupTabManagerProvider =
    ChangeNotifierProvider<LookupTabManager>((ref) => LookupTabManager());

final activeLookupTabProvider = Provider<LookupTab>((ref) {
  final manager = ref.watch(lookupTabManagerProvider);
  return manager.activeTab;
});

final searchEngineProvider = Provider<SearchEngine>((ref) {
  final manager = ref.watch(dictionaryManagerProvider);
  return SearchEngine(manager.wordIndex);
});

final activeDictionaryProvider = Provider<Dictionary?>((ref) {
  final manager = ref.watch(dictionaryManagerProvider);
  return manager.activeDictionary;
});

final wordListProvider = Provider<List<String>>((ref) {
  final manager = ref.watch(dictionaryManagerProvider);
  return manager.wordIndex.getAllWords();
});

final searchQueryProvider = Provider<String>((ref) {
  final manager = ref.watch(lookupTabManagerProvider);
  return manager.activeQuery;
});

final searchResultsProvider = Provider<List<WordSearchResult>>((ref) {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];

  final searchEngine = ref.watch(searchEngineProvider);
  final manager = ref.watch(dictionaryManagerProvider);
  final matches = searchEngine.search(query);

  // Build dictionary order lookup
  final orderMap = <String, int>{};
  final dicts = manager.dictionaries;
  for (var i = 0; i < dicts.length; i++) {
    orderMap[dicts[i].id] = dicts[i].displayOrder;
  }

  final grouped = <String, List<SearchResult>>{};
  final order = <String>[];

  for (final match in matches) {
    final existing = grouped[match.word];
    if (existing == null) {
      grouped[match.word] = [match];
      order.add(match.word);
    } else {
      existing.add(match);
    }
  }

  // Sort each word's matches by dictionary display order
  for (final list in grouped.values) {
    list.sort((a, b) {
      final oa = orderMap[a.dictionaryId] ?? 9999;
      final ob = orderMap[b.dictionaryId] ?? 9999;
      return oa.compareTo(ob);
    });
  }

  return order
      .map((word) => WordSearchResult(word: word, matches: grouped[word]!))
      .toList();
});

final currentEntryProvider = Provider<DictionaryEntry?>((ref) {
  final tabManager = ref.watch(lookupTabManagerProvider);
  final current = tabManager.activeNavigationEntry;
  if (current == null) return null;

  final dictionaryManager = ref.watch(dictionaryManagerProvider);
  return dictionaryManager.getEntry(current.dictionaryId, current.word);
});

final currentAvailableEntriesProvider = Provider<List<DictionaryEntry>>((ref) {
  final entry = ref.watch(currentEntryProvider);
  if (entry == null) return [];

  final dictionaryManager = ref.watch(dictionaryManagerProvider);
  return dictionaryManager.getEntriesForWord(entry.word);
});

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

enum DictionaryLoadState { idle, loading, loaded, error }

final dictionaryLoadStateProvider =
    StateProvider<DictionaryLoadState>((ref) => DictionaryLoadState.idle);

final dictionaryLoadErrorProvider = StateProvider<String?>((ref) => null);
