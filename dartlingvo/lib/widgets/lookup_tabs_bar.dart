import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/lookup_tab.dart';
import '../state/app_state.dart';

class LookupTabsBar extends ConsumerStatefulWidget {
  const LookupTabsBar({super.key});

  @override
  ConsumerState<LookupTabsBar> createState() => _LookupTabsBarState();
}

class _LookupTabsBarState extends ConsumerState<LookupTabsBar> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(lookupTabManagerProvider);
    final tabs = manager.tabs;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Scroll tabs left',
            onPressed: _scrollController.hasClients
                ? () => _scrollBy(-260)
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: SizedBox(
              height: 48,
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: tabs.length > 4,
                child: ListView.separated(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final tab = tabs[index];
                    return _LookupTabTile(
                      tab: tab,
                      selected: tab.id == manager.activeTabId,
                      onTap: () => ref.read(lookupTabManagerProvider).activateTab(tab.id),
                      onClose: () => ref.read(lookupTabManagerProvider).closeTab(tab.id),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${tabs.length} tabs',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Close other tabs',
            onPressed: tabs.length > 1
                ? () => ref.read(lookupTabManagerProvider).closeOtherTabs()
                : null,
            icon: const Icon(Icons.close_fullscreen),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Scroll tabs right',
            onPressed: _scrollController.hasClients
                ? () => _scrollBy(260)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
          const SizedBox(width: 4),
          IconButton.filledTonal(
            tooltip: 'New tab',
            onPressed: () => ref.read(lookupTabManagerProvider).openTab(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + delta).clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

}

class _LookupTabTile extends StatelessWidget {
  final LookupTab tab;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _LookupTabTile({
    required this.tab,
    required this.selected,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = selected
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minWidth: 132, maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tab.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Close tab',
                onPressed: onClose,
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                splashRadius: 18,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
