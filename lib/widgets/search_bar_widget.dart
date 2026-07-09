import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';

class DictionarySearchBar extends ConsumerStatefulWidget {
  const DictionarySearchBar({super.key});

  @override
  ConsumerState<DictionarySearchBar> createState() =>
      _DictionarySearchBarState();
}

class _DictionarySearchBarState extends ConsumerState<DictionarySearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String? _activeTabId;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(dictionaryManagerProvider);
    final tabs = ref.watch(lookupTabManagerProvider.select((value) => value.activeTabId));
    final activeTab = ref.read(activeLookupTabProvider);

    if (_activeTabId != tabs) {
      _activeTabId = tabs;
      final query = activeTab.searchQuery;
      if (_controller.text != query) {
        _controller.value = TextEditingValue(
          text: query,
          selection: TextSelection.collapsed(offset: query.length),
        );
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: manager.hasDictionaries,
        decoration: InputDecoration(
          hintText: manager.hasDictionaries
              ? 'Search words...'
              : 'Load a dictionary first',
          prefixIcon: const Icon(Icons.search),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (value) => ref.read(lookupTabManagerProvider).setQuery(value),
        onSubmitted: (value) => ref.read(lookupTabManagerProvider).setQuery(value),
      ),
    );
  }
}
