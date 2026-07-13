import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import '../state/app_state.dart';
import '../core/managers/lookup_tab_manager.dart';
import '../core/managers/dictionary_manager.dart';
import '../core/models/formatted_text.dart';
import '../core/models/dictionary_entry.dart';
import '../core/models/resolved_media.dart';

class EntryViewer extends ConsumerWidget {
  const EntryViewer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(currentEntryProvider);
    final manager = ref.watch(dictionaryManagerProvider);
    final tabs = ref.read(lookupTabManagerProvider);
    final availableEntries = ref.watch(currentAvailableEntriesProvider);

    if (entry == null) {
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(Icons.menu_book_outlined, size: 48,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 20),
              Text('Select a word to view',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('Tap any word from the list',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 560;
                final toggle = _DictionaryToggle(
                  entries: availableEntries.isEmpty ? [entry] : availableEntries,
                  currentDictionaryId:
                      tabs.activeNavigationEntry?.dictionaryId ?? entry.dictionaryId,
                  onSelected: (dictionaryEntry) {
                    tabs.navigateTo(entry.word, dictionaryEntry.dictionaryId);
                  },
                );
                final word = Text(
                  entry.word,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                );

                if (!isNarrow) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: word),
                      toggle,
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: toggle,
                    ),
                    const SizedBox(height: 12),
                    word,
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            ...entry.definitions.map(
              (def) => _buildDefinition(context, def, tabs, entry, manager),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefinition(
      BuildContext context,
      FormattedText def,
      LookupTabManager tabs,
      DictionaryEntry entry,
      DictionaryManager manager) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: RichText(
        text: _buildTextSpan(context, def.segments, tabs, entry, manager),
        textScaler: MediaQuery.textScalerOf(context),
      ),
    );
  }

  TextSpan _buildTextSpan(BuildContext context, List<TextSegment> segments,
      LookupTabManager tabs, DictionaryEntry entry, DictionaryManager manager) {
    final spans = <InlineSpan>[];

    for (final seg in segments) {
      final baseStyle = TextStyle(
        color: _segmentColor(context, seg),
        height: 1.6,
        fontWeight: seg.type == TextSegmentType.bold ? FontWeight.w600 : FontWeight.normal,
        fontStyle: seg.type == TextSegmentType.italic || seg.type == TextSegmentType.example
            ? FontStyle.italic
            : FontStyle.normal,
        decoration: seg.underline
            ? TextDecoration.underline
            : seg.strikeThrough
                ? TextDecoration.lineThrough
                : TextDecoration.none,
        fontSize: seg.superscript || seg.subscript ? 11 : null,
      );

      if (seg.type == TextSegmentType.reference) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () => _handleRefTap(seg.text, tabs),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(seg.text, style: baseStyle.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              )),
            ),
          ),
        ));
      } else if (_isMediaReference(seg)) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _DictionaryMediaTile(
            label: seg.text.trim(),
            entry: entry,
            manager: manager,
          ),
        ));
      } else {
        spans.add(TextSpan(text: seg.text, style: baseStyle));
      }
    }

    return TextSpan(children: spans);
  }

  void _handleRefTap(String word, LookupTabManager tabs) {
    final current = tabs.activeNavigationEntry;
    if (word.isNotEmpty && current != null) {
      tabs.navigateTo(word, current.dictionaryId);
    }
  }

  Color _segmentColor(BuildContext context, TextSegment segment) {
    final colorName = segment.color?.trim().toLowerCase();
    if (colorName != null && colorName.isNotEmpty) {
      const namedColors = <String, Color>{
        'black': Colors.black,
        'blue': Colors.blue,
        'brown': Colors.brown,
        'darkblue': Color(0xFF00008B),
        'darkcyan': Color(0xFF008B8B),
        'darkgray': Color(0xFFA9A9A9),
        'darkgrey': Color(0xFFA9A9A9),
        'darkgreen': Color(0xFF006400),
        'darkmagenta': Color(0xFF8B008B),
        'darkred': Color(0xFF8B0000),
        'gold': Color(0xFFFFD700),
        'lightblue': Color(0xFFADD8E6),
        'lightcyan': Color(0xFFE0FFFF),
        'lightgray': Color(0xFFD3D3D3),
        'lightgrey': Color(0xFFD3D3D3),
        'lightgreen': Color(0xFF90EE90),
        'lightpink': Color(0xFFFFB6C1),
        'lightyellow': Color(0xFFFFFFE0),
        'lime': Colors.lime,
        'cyan': Colors.cyan,
        'green': Colors.green,
        'magenta': Colors.purple,
        'maroon': Color(0xFF800000),
        'navy': Color(0xFF000080),
        'olive': Color(0xFF808000),
        'purple': Colors.purple,
        'silver': Color(0xFFC0C0C0),
        'red': Colors.red,
        'white': Colors.white,
        'yellow': Colors.yellow,
        'gray': Colors.grey,
        'grey': Colors.grey,
        'orange': Colors.orange,
        'pink': Colors.pink,
        'teal': Colors.teal,
      };

      final named = namedColors[colorName];
      if (named != null) {
        return named;
      }

      final normalizedColor = colorName.replaceFirst(RegExp(r'^(#|0x)'), '');
      final hexMatch = RegExp(r'^[0-9a-f]{3}$').firstMatch(normalizedColor);
      if (hexMatch != null) {
        final expanded = normalizedColor.split('').map((part) => '$part$part').join();
        final parsed = int.tryParse('ff$expanded', radix: 16);
        if (parsed != null) {
          return Color(parsed);
        }
      }

      final sixDigitMatch = RegExp(r'^[0-9a-f]{6}$').firstMatch(normalizedColor);
      if (sixDigitMatch != null) {
        final parsed = int.tryParse('ff$normalizedColor', radix: 16);
        if (parsed != null) {
          return Color(parsed);
        }
      }

      final eightDigitMatch = RegExp(r'^[0-9a-f]{8}$').firstMatch(normalizedColor);
      if (eightDigitMatch != null) {
        final parsed = int.tryParse(normalizedColor, radix: 16);
        if (parsed != null) {
          return Color(parsed);
        }
      }
    }

    if (segment.type == TextSegmentType.example) {
      return Theme.of(context).colorScheme.onSurfaceVariant;
    }

    return Theme.of(context).colorScheme.onSurface;
  }

  bool _isMediaReference(TextSegment segment) {
    if (!segment.strikeThrough) {
      return false;
    }

    final text = segment.text.trim();
    if (text.isEmpty) {
      return false;
    }

    final fileName = p.basename(text);
    return RegExp(
      r'.+\.(bmp|gif|jpe?g|png|webp|wav|mp3|m4a|aac|ogg|flac|mp4|mov|mkv)$',
      caseSensitive: false,
    ).hasMatch(fileName);
  }

}

class _DictionaryMediaTile extends StatefulWidget {
  final String label;
  final DictionaryEntry entry;
  final DictionaryManager manager;

  const _DictionaryMediaTile({
    required this.label,
    required this.entry,
    required this.manager,
  });

  @override
  State<_DictionaryMediaTile> createState() => _DictionaryMediaTileState();
}

class _DictionaryMediaTileState extends State<_DictionaryMediaTile> {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<void>? _playerCompleteSubscription;
  Timer? _resetTimer;
  bool _isPlaying = false;
  ResolvedMedia? _media;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_resolveMedia());
    });
  }

  Future<void> _resolveMedia() async {
    try {
      unawaited(widget.manager.preloadEmbeddedMediaIndex(widget.entry.dictionaryId));
      final media = widget.manager.resolveMediaReference(widget.entry, widget.label);
      if (!mounted) return;
      setState(() {
        _media = media;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _media = null;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _playerStateSubscription?.cancel();
    _playerCompleteSubscription?.cancel();
    try {
      _player?.dispose();
    } on MissingPluginException {
      // Desktop plugin registration may be unavailable after hot restart.
    }
    super.dispose();
  }

  Future<void> _playAudio() async {
    final media = _media;
    if (media == null) return;

    final player = _player ??= AudioPlayer();
    try {
      if (_isPlaying) {
        _resetTimer?.cancel();
        await player.pause();
        if (mounted && _isPlaying) {
          setState(() => _isPlaying = false);
        }
        return;
      }

      await _playerStateSubscription?.cancel();
      _playerStateSubscription = player.onPlayerStateChanged.listen((state) {
        if (!mounted) return;
        final shouldShowPlaying = state == PlayerState.playing;
        if (_isPlaying != shouldShowPlaying) {
          setState(() => _isPlaying = shouldShowPlaying);
        }
        if (!shouldShowPlaying) {
          _resetTimer?.cancel();
        }
      });
      await _playerCompleteSubscription?.cancel();
      _playerCompleteSubscription = player.onPlayerComplete.listen((_) {
        if (!mounted) return;
        _resetTimer?.cancel();
        if (_isPlaying) {
          setState(() => _isPlaying = false);
        }
      });
      if (defaultTargetPlatform == TargetPlatform.windows) {
        unawaited(
          player.setSourceBytes(media.bytes, mimeType: media.mimeType).catchError(
            (_) {
              // Windows can miss the prepared event even when the source is ready.
            },
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await player.resume();
      } else {
        await player.play(BytesSource(media.bytes, mimeType: media.mimeType));
      }
      if (mounted && !_isPlaying) {
        setState(() => _isPlaying = true);
      }
      unawaited(_scheduleAutoReset(player));
    } on MissingPluginException {
      // Audio plugin is not registered in this runtime.
    }
  }

  Future<void> _scheduleAutoReset(AudioPlayer player) async {
    _resetTimer?.cancel();

    Duration? duration;
    for (var attempt = 0; attempt < 20; attempt++) {
      duration = await player.getDuration();
      if (!mounted) return;
      if (duration != null && duration > Duration.zero) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    if (!mounted || duration == null || duration <= Duration.zero) {
      return;
    }

    _resetTimer = Timer(duration + const Duration(milliseconds: 500), () {
      if (!mounted) return;
      if (_isPlaying) {
        setState(() => _isPlaying = false);
      }
    });
  }

  void _showImage(BuildContext context) {
    final media = _media;
    if (media == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(
          child: Image.memory(media.bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }

  bool get _isImage {
    return _media?.isImage ?? false;
  }

  bool get _isAudio {
    return _media?.isAudio ?? false;
  }

  bool get _isVideo {
    return _media?.isVideo ?? false;
  }

  IconData _iconForLabel(String label) {
    final normalized = label.toLowerCase();
    if (RegExp(r'.+\.(bmp|gif|jpe?g|png|webp)$', caseSensitive: false).hasMatch(normalized)) {
      return Icons.image_outlined;
    }
    if (RegExp(r'.+\.(wav|mp3|m4a|aac|ogg|flac)$', caseSensitive: false).hasMatch(normalized)) {
      return Icons.graphic_eq;
    }
    if (RegExp(r'.+\.(mp4|mov|mkv|webm|avi)$', caseSensitive: false).hasMatch(normalized)) {
      return Icons.movie_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Widget _iconBadge({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required List<Color> colors,
    required Color foregroundColor,
    VoidCallback? onTap,
  }) {
    final badge = Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: 0.22),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(icon, size: 20, color: foregroundColor),
    );

    return Tooltip(
      message: tooltip,
      child: onTap == null
          ? badge
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: badge,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = widget.label;

    if (_loading) {
      return _iconBadge(
        context: context,
        icon: _iconForLabel(label),
        tooltip: label,
        colors: [
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        ],
        foregroundColor: theme.colorScheme.onSurfaceVariant,
      );
    }

    if (_media == null) {
      return _iconBadge(
        context: context,
        icon: Icons.cloud_off_outlined,
        tooltip: label,
        colors: [
          theme.colorScheme.errorContainer.withValues(alpha: 0.9),
          theme.colorScheme.errorContainer.withValues(alpha: 0.55),
        ],
        foregroundColor: theme.colorScheme.error,
      );
    }

    if (_isImage) {
      return _iconBadge(
        context: context,
        icon: Icons.photo_outlined,
        tooltip: label,
        colors: [
          const Color(0xFF56CCF2),
          const Color(0xFF2F80ED),
        ],
        foregroundColor: Colors.white,
        onTap: () {
          _showImage(context);
        },
      );
    }

    if (_isAudio) {
      return _iconBadge(
        context: context,
        icon: _isPlaying ? Icons.pause_circle_filled : Icons.graphic_eq_rounded,
        tooltip: label,
        colors: [
          const Color(0xFFFFA726),
          const Color(0xFFD84315),
        ],
        foregroundColor: Colors.white,
        onTap: () {
          _playAudio();
        },
      );
    }

    if (_isVideo) {
      return _iconBadge(
        context: context,
        icon: Icons.movie_outlined,
        tooltip: label,
        colors: [
          const Color(0xFF8E2DE2),
          const Color(0xFF4A00E0),
        ],
        foregroundColor: Colors.white,
      );
    }

    return _iconBadge(
      context: context,
      icon: _iconForLabel(label),
      tooltip: label,
      colors: [
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
      ],
      foregroundColor: theme.colorScheme.onSurfaceVariant,
    );
  }
}

class _DictionaryToggle extends StatelessWidget {
  final List<DictionaryEntry> entries;
  final String currentDictionaryId;
  final ValueChanged<DictionaryEntry> onSelected;

  const _DictionaryToggle({
    required this.entries,
    required this.currentDictionaryId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final currentIndex = entries.indexWhere((entry) => entry.dictionaryId == currentDictionaryId);
    final current = currentIndex >= 0 ? entries[currentIndex] : entries.first;
    final nextEntry = entries[(currentIndex >= 0 ? currentIndex + 1 : 0) % entries.length];
    final colorScheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colorScheme.onPrimaryContainer,
        );

    return Material(
      color: colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => onSelected(nextEntry),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(current.dictionaryName, style: labelStyle),
                  const SizedBox(width: 6),
                  Icon(Icons.swap_horiz, size: 16, color: colorScheme.onPrimaryContainer),
                ],
              ),
            ),
          ),
          VerticalDivider(width: 1, thickness: 1, color: colorScheme.onPrimaryContainer.withValues(alpha: 0.2)),
          PopupMenuButton<DictionaryEntry>(
            tooltip: 'Dictionaries containing this word',
            padding: EdgeInsets.zero,
            onSelected: onSelected,
            itemBuilder: (context) => [
              for (final entry in entries)
                PopupMenuItem<DictionaryEntry>(
                  value: entry,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: Text(entry.dictionaryName, overflow: TextOverflow.ellipsis)),
                      if (entry.dictionaryId == current.dictionaryId)
                        Icon(Icons.check, size: 16, color: colorScheme.primary),
                    ],
                  ),
                ),
            ],
            icon: Icon(Icons.arrow_drop_down, color: colorScheme.onPrimaryContainer),
          ),
        ],
      ),
    );
  }
}
