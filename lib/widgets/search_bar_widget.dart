import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';
import 'navigation_buttons.dart';

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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 46,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: manager.hasDictionaries,
                decoration: InputDecoration(
                  hintText: manager.hasDictionaries
                      ? 'Search words...'
                      : 'Load a dictionary first',
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    child: Icon(Icons.search, size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _controller.clear();
                            ref.read(lookupTabManagerProvider).setQuery('');
                          },
                        )
                      : null,
                ),
                textInputAction: TextInputAction.search,
                onChanged: (value) => ref.read(lookupTabManagerProvider).setQuery(value),
                onSubmitted: (value) => ref.read(lookupTabManagerProvider).setQuery(value),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const NavigationButtons(),
        ],
      ),
    );
  }
}
