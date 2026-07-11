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
    final isCompact = MediaQuery.sizeOf(context).height < 500 ||
        MediaQuery.viewInsetsOf(context).bottom > 0;

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
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: isCompact ? 4 : 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: isCompact ? 38 : 46,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: manager.hasDictionaries,
                decoration: InputDecoration(
                  hintText: manager.hasDictionaries
                      ? 'Search words...'
                      : 'Load a dictionary first',
                  suffixIcon: IconButton(
                    icon: Icon(Icons.close, size: isCompact ? 16 : 18),
                    onPressed: () {
                      _controller.clear();
                      ref.read(lookupTabManagerProvider).setQuery('');
                    },
                  ),
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
