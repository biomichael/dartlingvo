import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final manager = ref.watch(dictionaryManagerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Theme'),
            subtitle: Text(_themeName(themeMode)),
            onTap: () => _showThemePicker(context, ref),
          ),
          const Divider(),
          const _SectionHeader('Dictionaries'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Total Dictionaries'),
            trailing: Text('${manager.dictionaries.length}',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('Total Entries'),
            trailing: Text('${manager.totalWordCount}',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          if (manager.hasDictionaries) ...[
            const Divider(),
            const _SectionHeader('Loaded Dictionaries'),
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorder: (oldIndex, newIndex) {
                ref.read(dictionaryManagerProvider).reorderDictionaries(oldIndex, newIndex);
              },
              children: manager.dictionaries.map((dict) => ListTile(
                    key: ValueKey(dict.id),
                    leading: ReorderableDragStartListener(
                      index: manager.dictionaries.indexOf(dict),
                      child: const Icon(Icons.drag_handle),
                    ),
                    title: Text(dict.name),
                    subtitle: Text(
                      '${dict.wordCount} entries',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _confirmRemove(ref, context, dict.id, dict.name),
                    ),
                  )).toList(),
            ),
          ],
          if (manager.hasDictionaries) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_sweep, color: Colors.red),
              title: const Text('Remove All Dictionaries',
                  style: TextStyle(color: Colors.red)),
              onTap: () => _confirmClearAll(ref, context),
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About DartLingvo'),
            subtitle: const Text('Version 1.0.0'),
          ),
        ],
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
        return 'System Default';
    }
  }

  void _showThemePicker(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose Theme'),
        children: [
          for (final mode in [ThemeMode.light, ThemeMode.dark, ThemeMode.system])
            RadioListTile<ThemeMode>(
              title: Text(_themeName(mode)),
              value: mode,
              groupValue: ref.read(themeModeProvider),
              onChanged: (value) {
                ref.read(themeModeProvider.notifier).state = value!;
                Navigator.pop(ctx);
              },
            ),
        ],
      ),
    );
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

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
