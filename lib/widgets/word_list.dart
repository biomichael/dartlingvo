import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';
import '../core/managers/dictionary_manager.dart';

class WordList extends ConsumerWidget {
  const WordList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchResults = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);
    final tabs = ref.watch(lookupTabManagerProvider);
    final manager = ref.watch(dictionaryManagerProvider);

    if (query.isEmpty) {
      return _buildWordCount(context, manager);
    }

    if (searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text('No results found',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: searchResults.length,
      itemBuilder: (context, index) {
        final result = searchResults[index];
        final firstMatch = result.primary;

        return Opacity(
          opacity: 1.0,
          child: ListTile(
            leading: Icon(
              Icons.article_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              result.word,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              '${firstMatch.dictionaryName} • ${result.matches.length} dictionaries',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            selected: tabs.activeNavigationEntry?.word == result.word,
            onTap: () {
              ref.read(lookupTabManagerProvider).navigateTo(
                result.word,
                firstMatch.dictionaryId,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildWordCount(BuildContext context, DictionaryManager manager) {
    if (!manager.hasDictionaries) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_books_outlined, size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('No dictionaries loaded',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text('Tap + to load an .lsd or .dsl file',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search, size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            '${manager.totalWordCount} entries across ${manager.dictionaries.length} dictionaries',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text('Start typing to search',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
