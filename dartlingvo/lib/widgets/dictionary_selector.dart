import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';

class DictionarySelector extends ConsumerWidget {
  const DictionarySelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(dictionaryManagerProvider);
    final activeId = manager.activeDictionaryId;

    if (!manager.hasDictionaries) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _buildChip(
            context,
            'All',
            activeId == null,
            () => manager.setActiveDictionary(null),
          ),
          const SizedBox(width: 8),
          ...manager.dictionaries.map((dict) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildChip(
                  context,
                  dict.name,
                  activeId == dict.id,
                  () => manager.setActiveDictionary(dict.id),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildChip(
      BuildContext context, String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
