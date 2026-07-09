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
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          if (tabs.length > 3)
            IconButton(
              tooltip: 'Scroll tabs left',
              onPressed: _scrollController.hasClients
                  ? () => _scrollBy(-260)
                  : null,
              icon: const Icon(Icons.chevron_left, size: 20),
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          const SizedBox(width: 4),
          Expanded(
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: tabs.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
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
          const SizedBox(width: 4),
          if (tabs.length > 3)
            IconButton(
              tooltip: 'Scroll tabs right',
              onPressed: _scrollController.hasClients
                  ? () => _scrollBy(260)
                  : null,
              icon: const Icon(Icons.chevron_right, size: 20),
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          const SizedBox(width: 4),
          const SizedBox(width: 4),
          if (tabs.length > 1)
            Tooltip(
              message: 'Close other tabs',
              child: SizedBox(
                height: 40,
                child: IconButton(
                  onPressed: () => ref.read(lookupTabManagerProvider).closeOtherTabs(),
                  icon: Icon(Icons.delete_sweep, size: 18),
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 12),
          Tooltip(
            message: 'New tab',
            child: SizedBox(
              height: 40,
              child: FilledButton.tonal(
                onPressed: () => ref.read(lookupTabManagerProvider).openTab(),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text('${tabs.length} +'),
              ),
            ),
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

    return SizedBox(
      height: 40,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minWidth: 120, maxWidth: 200),
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 14, color: foreground.withValues(alpha: 0.7)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
