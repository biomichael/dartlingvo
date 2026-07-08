import 'package:dartlingvo/core/parsing/lsd_decoder_dart.dart';

Future<void> main() async {
  final decoder = LsdDecoderDart(r'C:\Users\MZDEV\Downloads\Dictionaries\EnglishEtymology.lsd');
  final result = await decoder.decode();
  final matches = result.entries
      .where((entry) => entry.word.toLowerCase().contains('house'))
      .take(20)
      .toList();
  print('count=${result.entries.length}');
  for (final entry in matches) {
    print(entry.word);
  }
}
