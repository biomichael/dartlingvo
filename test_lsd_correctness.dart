import 'dart:io';
import 'dart:convert';
import 'lib/core/parsing/lsd_decoder_dart.dart';

void main() async {
  final path = r'C:\Users\MZDEV\Downloads\Dictionaries\EnglishEtymology.lsd';
  final sw = Stopwatch()..start();
  try {
    final decoder = LsdDecoderDart(path);
    final result = await decoder.decode();
    sw.stop();
    print('Total: ${result.entries.length} entries in ${sw.elapsed}');
    for (int i = 0; i < 5 && i < result.entries.length; i++) {
      final e = result.entries[i];
      print('--- Entry $i ---');
      print('  word: ${e.word}');
      final text = e.definitions.isNotEmpty ? e.definitions.first.plainText : '';
      final preview = text.length > 300 ? '${text.substring(0, 300)}...' : text;
      print('  article: $preview');
    }
    for (final idx in [5000, 10000, 15000, 19079]) {
      if (idx < result.entries.length) {
        final e = result.entries[idx];
        print('--- Entry $idx ---');
        print('  word: ${e.word}');
        final text = e.definitions.isNotEmpty ? e.definitions.first.plainText : '';
        final preview = text.length > 300 ? '${text.substring(0, 300)}...' : text;
        print('  article: $preview');
      }
    }
  } catch (e, st) {
    sw.stop();
    print('Error after ${sw.elapsed}: $e');
    print('Stack: $st');
  }
}
