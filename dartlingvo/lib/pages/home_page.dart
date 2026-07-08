import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';
import '../core/services/dictionary_service.dart';
import '../widgets/lookup_tabs_bar.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/word_list.dart';
import '../widgets/entry_viewer.dart';
import '../widgets/navigation_buttons.dart';
import '../widgets/settings_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  Timer? _loadTimer;
  int _loadSeconds = 0;
  bool _restoredPersistedDictionaries = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _restoredPersistedDictionaries) return;
      _restoredPersistedDictionaries = true;
      _restorePersistedDictionaries();
    });
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loadState = ref.watch(dictionaryLoadStateProvider);
    final loadError = ref.watch(dictionaryLoadErrorProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('DartLingvo'),
        actions: [
          const NavigationButtons(),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _loadDictionary(ref, context),
            tooltip: 'Load Dictionary',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const _SettingsPageWrapper(),
              ),
            ),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const LookupTabsBar(),
              const DictionarySearchBar(),
              if (loadState == DictionaryLoadState.error && loadError != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: Theme.of(context).colorScheme.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              loadError,
                              style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              ref.read(dictionaryLoadStateProvider.notifier).state =
                                  DictionaryLoadState.idle;
                              ref.read(dictionaryLoadErrorProvider.notifier).state = null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: _isLandscape(context)
                    ? const Row(
                        children: [
                          Expanded(flex: 2, child: WordList()),
                          VerticalDivider(width: 1),
                          Expanded(flex: 3, child: EntryViewer()),
                        ],
                      )
                    : const Column(
                        children: [
                          Expanded(flex: 1, child: WordList()),
                          Divider(height: 1),
                          Expanded(flex: 2, child: EntryViewer()),
                        ],
                      ),
              ),
            ],
          ),
          if (loadState == DictionaryLoadState.loading)
            Container(
              color: Colors.black38,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(32),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 20),
                        const Text(
                          'Loading dictionary\u2026',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatTime(_loadSeconds),
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return 'Elapsed: $m:$s';
  }

  bool _isLandscape(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width > 600;
  }

  Future<void> _loadDictionary(WidgetRef ref, BuildContext context) async {
    final manager = ref.read(dictionaryManagerProvider);
    final service = DictionaryService(manager);

    _loadSeconds = 0;
    _loadTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _loadSeconds++);
    });

    ref.read(dictionaryLoadStateProvider.notifier).state =
        DictionaryLoadState.loading;
    ref.read(dictionaryLoadErrorProvider.notifier).state = null;

    try {
      final path = await service.pickAndLoadDictionary();
      _loadTimer?.cancel();
      if (path != null) {
        ref.read(dictionaryLoadStateProvider.notifier).state =
            DictionaryLoadState.loaded;
      } else {
        ref.read(dictionaryLoadStateProvider.notifier).state =
            DictionaryLoadState.idle;
      }
    } catch (e) {
      _loadTimer?.cancel();
      ref.read(dictionaryLoadStateProvider.notifier).state =
          DictionaryLoadState.error;
      ref.read(dictionaryLoadErrorProvider.notifier).state = e.toString();
    }
  }

  Future<void> _restorePersistedDictionaries() async {
    final manager = ref.read(dictionaryManagerProvider);

    ref.read(dictionaryLoadStateProvider.notifier).state =
        DictionaryLoadState.loading;
    ref.read(dictionaryLoadErrorProvider.notifier).state = null;

    try {
      await manager.restorePersistedDictionaries();
      if (!mounted) return;
      ref.read(dictionaryLoadStateProvider.notifier).state =
          manager.hasDictionaries
              ? DictionaryLoadState.loaded
              : DictionaryLoadState.idle;
    } catch (e) {
      if (!mounted) return;
      ref.read(dictionaryLoadStateProvider.notifier).state =
          DictionaryLoadState.error;
      ref.read(dictionaryLoadErrorProvider.notifier).state = e.toString();
    }
  }
}

class _SettingsPageWrapper extends StatelessWidget {
  const _SettingsPageWrapper();

  @override
  Widget build(BuildContext context) {
    return const SettingsPage();
  }
}
