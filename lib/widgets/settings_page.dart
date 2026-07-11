import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:math' as math;
import '../state/app_state.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final manager = ref.watch(dictionaryManagerProvider);
    final enabledSet = ref.watch(enabledDictionaryIdsProvider);
    final fontFamily = ref.watch(fontFamilyProvider);
    final textScale = ref.watch(textScaleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 520;
          final appearanceControlWidth = math.min(320.0, math.max(240.0, constraints.maxWidth - 64));

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              _SectionCard(
                title: 'Appearance',
                children: [
                  _SettingsTile(
                    icon: Icons.brightness_6,
                    title: 'Theme',
                    subtitle: _themeName(themeMode),
                    trailing: _SegmentedThemeSelector(),
                    isNarrow: isNarrow,
                    controlWidth: appearanceControlWidth,
                  ),
                  const _Divider(),
                  _SettingsTile(
                    icon: Icons.text_fields,
                    title: 'Font',
                    subtitle: fontFamily,
                    trailing: _FontSelector(),
                    isNarrow: isNarrow,
                    controlWidth: appearanceControlWidth,
                  ),
                  const _Divider(),
                  _SettingsTile(
                    icon: Icons.format_size,
                    title: 'Text Size',
                    subtitle: '${textScale.toStringAsFixed(1)}x',
                    trailing: const _TextSizeSlider(),
                    isNarrow: isNarrow,
                    controlWidth: appearanceControlWidth,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Dictionaries',
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: isNarrow
                        ? Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: _StatBadge(
                                  icon: Icons.book,
                                  value: '${manager.dictionaries.length}',
                                  label: 'dictionaries',
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: _StatBadge(
                                  icon: Icons.text_snippet,
                                  value: '${manager.totalWordCount}',
                                  label: 'entries',
                                ),
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: _StatBadge(
                                  icon: Icons.book,
                                  value: '${manager.dictionaries.length}',
                                  label: 'dictionaries',
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _StatBadge(
                                  icon: Icons.text_snippet,
                                  value: '${manager.totalWordCount}',
                                  label: 'entries',
                                ),
                              ),
                            ],
                          ),
                  ),
                  if (manager.hasDictionaries) ...[
                    const _Divider(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                      child: Text(
                        'Loaded Dictionaries',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      onReorder: (oldIndex, newIndex) {
                        ref.read(dictionaryManagerProvider).reorderDictionaries(oldIndex, newIndex);
                      },
                      children: manager.dictionaries.map((dict) {
                        final index = manager.dictionaries.indexOf(dict);
                        final isEnabled = enabledSet.isEmpty || enabledSet.contains(dict.id);
                        return Padding(
                          key: ValueKey(dict.id),
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Material(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                child: isNarrow
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              ReorderableDragStartListener(
                                                index: index,
                                                child: Padding(
                                                  padding: const EdgeInsets.all(8),
                                                  child: Icon(
                                                    Icons.drag_indicator,
                                                    size: 20,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant
                                                        .withValues(alpha: 0.5),
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        dict.name,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                              fontWeight: FontWeight.w500,
                                                            ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '${dict.wordCount} entries',
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color: Theme.of(context)
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Switch(
                                                value: isEnabled,
                                                onChanged: (value) {
                                                  ref.read(enabledDictionaryIdsProvider.notifier).update((set) {
                                                    final updated = {...set};
                                                    if (value) {
                                                      updated.add(dict.id);
                                                      final all = ref.read(dictionaryManagerProvider).dictionaries;
                                                      for (final d in all) {
                                                        updated.add(d.id);
                                                      }
                                                    } else {
                                                      updated.remove(dict.id);
                                                    }
                                                    return updated;
                                                  });
                                                },
                                              ),
                                              IconButton(
                                                icon: Icon(
                                                  Icons.delete_outline,
                                                  size: 20,
                                                  color: Theme.of(context).colorScheme.error,
                                                ),
                                                onPressed: () => _confirmRemove(ref, context, dict.id, dict.name),
                                                tooltip: 'Remove dictionary',
                                              ),
                                            ],
                                          ),
                                        ],
                                      )
                                    : Row(
                                        children: [
                                          ReorderableDragStartListener(
                                            index: index,
                                            child: Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Icon(
                                                Icons.drag_indicator,
                                                size: 20,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant
                                                    .withValues(alpha: 0.5),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  dict.name,
                                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${dict.wordCount} entries',
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Switch(
                                            value: isEnabled,
                                            onChanged: (value) {
                                              ref.read(enabledDictionaryIdsProvider.notifier).update((set) {
                                                final updated = {...set};
                                                if (value) {
                                                  updated.add(dict.id);
                                                  final all = ref.read(dictionaryManagerProvider).dictionaries;
                                                  for (final d in all) {
                                                    updated.add(d.id);
                                                  }
                                                } else {
                                                  updated.remove(dict.id);
                                                }
                                                return updated;
                                              });
                                            },
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              Icons.delete_outline,
                                              size: 20,
                                              color: Theme.of(context).colorScheme.error,
                                            ),
                                            onPressed: () => _confirmRemove(ref, context, dict.id, dict.name),
                                            tooltip: 'Remove dictionary',
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const _Divider(),
                    ListTile(
                      leading: Icon(Icons.delete_sweep,
                          color: Theme.of(context).colorScheme.error),
                      title: Text('Remove All Dictionaries',
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      onTap: () => _confirmClearAll(ref, context),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'About',
                children: [
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.info_outline,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    title: const Text('DartLingvo'),
                    subtitle: const Text('Version 1.0.0'),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  String _themeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System';
    }
  }

  void _confirmRemove(WidgetRef ref, BuildContext context, String id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Dictionary'),
        content: Text('Remove "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              ref.read(enabledDictionaryIdsProvider.notifier).update((set) {
                final updated = {...set};
                updated.remove(id);
                return updated;
              });
              await ref.read(dictionaryManagerProvider).removeDictionary(id);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll(WidgetRef ref, BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All'),
        content: const Text('Remove all loaded dictionaries?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              ref.read(enabledDictionaryIdsProvider.notifier).state = {};
              await ref.read(dictionaryManagerProvider).clearAll();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
            },
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final bool isNarrow;
  final double controlWidth;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.isNarrow,
    required this.controlWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: isNarrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  )),
                          Text(subtitle,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  )),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: controlWidth,
                  child: trailing,
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              )),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              )),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: controlWidth,
                  child: trailing,
                ),
              ],
            ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Divider(
        height: 1,
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatBadge({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 6),
          Text(value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
          Text(label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
        ],
      ),
    );
  }
}

class _SegmentedThemeSelector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(themeModeProvider);
        return SizedBox(
          width: double.infinity,
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 16)),
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto, size: 16)),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 16)),
            ],
            selected: {current},
            onSelectionChanged: (selected) {
              ref.read(themeModeProvider.notifier).state = selected.first;
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FontSelector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(fontFamilyProvider);
        return PopupMenuButton<String>(
          tooltip: 'Select font',
          onSelected: (value) {
            ref.read(fontFamilyProvider.notifier).state = value;
          },
          itemBuilder: (context) => [
            for (final font in availableFonts)
              PopupMenuItem<String>(
                value: font,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      font,
                      style: TextStyle(
                        fontWeight: current == font ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    if (current == font) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary),
                    ],
                  ],
                ),
              ),
          ],
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    current,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TextSizeSlider extends StatefulWidget {
  const _TextSizeSlider({super.key});

  @override
  State<_TextSizeSlider> createState() => _TextSizeSliderState();
}

class _TextSizeSliderState extends State<_TextSizeSlider> {
  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(textScaleProvider);
        return SizedBox(
          width: double.infinity,
          child: Slider(
            value: current,
            min: 0.7,
            max: 1.6,
            divisions: 9,
            label: '${current.toStringAsFixed(1)}x',
            onChanged: (value) {
              ref.read(textScaleProvider.notifier).state = value;
            },
          ),
        );
      },
    );
  }
}
