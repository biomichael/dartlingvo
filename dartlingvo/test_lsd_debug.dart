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
    
    // Print first 20 entries
    for (int i = 0; i < 20 && i < result.entries.length; i++) {
      final e = result.entries[i];
      final text = e.definitions.isNotEmpty ? e.definitions.first.plainText : '';
      final preview = text.length > 100 ? '${text.substring(0, 100)}...' : text;
      print('$i: word="${e.word}"');
      if (preview.isNotEmpty) print('   art="$preview"');
    }
  } catch (e, st) {
    sw.stop();
    print('Error after ${sw.elapsed}: $e');
    print('Stack: $st');
  }
}
