import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import '../state/app_state.dart';
import '../core/managers/lookup_tab_manager.dart';
import '../core/managers/dictionary_manager.dart';
import '../core/models/formatted_text.dart';
import '../core/models/dictionary_entry.dart';

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    entry.word,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                  ),
                ),
                _DictionaryToggle(
                  entries: availableEntries.isEmpty ? [entry] : availableEntries,
                  currentDictionaryId:
                      tabs.activeNavigationEntry?.dictionaryId ?? entry.dictionaryId,
                  onSelected: (dictionaryEntry) {
                    tabs.navigateTo(entry.word, dictionaryEntry.dictionaryId);
                  },
                ),
              ],
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
        final media = _resolveMediaReference(manager, entry, seg.text);
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _DictionaryMediaTile(
            label: seg.text.trim(),
            file: media,
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

  File? _resolveMediaReference(
    DictionaryManager manager,
    DictionaryEntry? entry,
    String mediaText,
  ) {
    final dictionary = entry == null ? null : manager.dictionaryById(entry.dictionaryId);
    final candidates = <Directory>[];

    if (dictionary != null) {
      final sourceDir = File(dictionary.sourcePath).parent;
      candidates.add(sourceDir);
      if (dictionary.cachedFilePath != null) {
        candidates.add(File(dictionary.cachedFilePath!).parent);
      }
    }

    final relative = mediaText.trim();
    if (relative.isEmpty) {
      return null;
    }

    for (final dir in candidates) {
      final candidate = File(p.normalize(p.join(dir.path, relative)));
      if (candidate.existsSync()) {
        return candidate;
      }

      final basenameCandidate = File(p.join(dir.path, p.basename(relative)));
      if (basenameCandidate.existsSync()) {
        return basenameCandidate;
      }
    }

    return null;
  }
}

class _DictionaryMediaTile extends StatefulWidget {
  final String label;
  final File? file;

  const _DictionaryMediaTile({
    required this.label,
    required this.file,
  });

  @override
  State<_DictionaryMediaTile> createState() => _DictionaryMediaTileState();
}

class _DictionaryMediaTileState extends State<_DictionaryMediaTile> {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  bool _isPlaying = false;

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _playAudio() async {
    if (widget.file == null) return;

    final player = _player ??= AudioPlayer();
    await player.setFilePath(widget.file!.path);
    await _playerStateSubscription?.cancel();
    _playerStateSubscription = player.playerStateStream.listen((state) {
      if (!mounted) return;
      final shouldShowPlaying = state.playing && state.processingState == ProcessingState.ready;
      if (_isPlaying != shouldShowPlaying) {
        setState(() => _isPlaying = shouldShowPlaying);
      }
    });
    await player.play();
  }

  void _showImage(BuildContext context) {
    if (widget.file == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(
          child: Image.file(widget.file!, fit: BoxFit.contain),
        ),
      ),
    );
  }

  bool get _isImage {
    final file = widget.file;
    if (file == null) return false;
    return RegExp(r'.+\.(bmp|gif|jpe?g|png|webp)$', caseSensitive: false)
        .hasMatch(file.path);
  }

  bool get _isAudio {
    final file = widget.file;
    if (file == null) return false;
    return RegExp(r'.+\.(wav|mp3|m4a|aac|ogg|flac)$', caseSensitive: false)
        .hasMatch(file.path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.file == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file_outlined,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_isImage) {
      return GestureDetector(
        onTap: () => _showImage(context),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 180, maxHeight: 140),
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.file(widget.file!, fit: BoxFit.contain),
        ),
      );
    }

    if (_isAudio) {
      return IconButton(
        tooltip: widget.label,
        icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle),
        onPressed: _playAudio,
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        widget.label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
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
