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
    print('Success: ${result.entries.length} entries in ${sw.elapsed}');
  } catch (e, st) {
    sw.stop();
    print('Error after ${sw.elapsed}: $e');
    print('Stack: $st');
  }
}
