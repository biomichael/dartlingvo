import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';
import 'entry_viewer.dart';

class WordList extends ConsumerWidget {
  const WordList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchResults = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);
    final tabs = ref.watch(lookupTabManagerProvider);
    final manager = ref.watch(dictionaryManagerProvider);
    final isWide = MediaQuery.of(context).size.width > 600;

    if (!manager.hasDictionaries) {
      return _EmptyState(
        icon: Icons.library_books_outlined,
        iconColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
        iconBackground: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
        title: 'No dictionaries loaded',
        message: 'Tap + to load an .lsd or .dsl file',
      );
    }

    if (query.isEmpty) {
      return _EmptyState(
        icon: Icons.search,
        iconColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
        iconBackground: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
        title: '${manager.totalWordCount} entries',
        message: 'across ${manager.dictionaries.length} dictionaries',
        pillText: 'Start typing to search',
      );
    }

    if (searchResults.isEmpty) {
      return _EmptyState(
        icon: Icons.search_off,
        iconColor: Theme.of(context).colorScheme.error.withValues(alpha: 0.7),
        iconBackground: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
        title: 'No results found',
        message: 'Try a different search term',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: searchResults.length,
      itemBuilder: (context, index) {
        final result = searchResults[index];
        final firstMatch = result.primary;
        final isSelected = tabs.activeNavigationEntry?.word == result.word;

        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Card(
            elevation: isSelected ? 1 : 0,
            color: isSelected
                ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
                : Theme.of(context).colorScheme.surface,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isSelected
                  ? BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3))
                  : BorderSide.none,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
                ref.read(lookupTabManagerProvider).navigateTo(
                  result.word,
                  firstMatch.dictionaryId,
                );
                if (!isWide) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const _WordDetailPage(),
                    ),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.article_outlined,
                        size: 18,
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.word,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 2),
                            Text(
                              firstMatch.dictionaryName,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (result.matches.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${result.matches.length}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSecondaryContainer,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String message;
  final String? pillText;

  const _EmptyState({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.message,
    this.pillText,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: iconBackground,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(icon, size: 48, color: iconColor),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (pillText != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        pillText!,
                        style: textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WordDetailPage extends ConsumerWidget {
  const _WordDetailPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(currentEntryProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(entry?.word ?? ''),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const EntryViewer(),
    );
  }
}
