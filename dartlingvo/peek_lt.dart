import 'dart:io';
import 'dart:typed_data';
import 'package:dartlingvo/core/parsing/lsd_decoder_dart.dart';

void main() {
  final path = r'C:\Users\MZDEV\Downloads\Dictionaries\EnglishEtymology.lsd';
  final file = File(path);
  final data = Uint8List.fromList(file.readAsBytesSync());

  // Parse header to get encoder offset
  var encoderOff = data[28] | (data[29] << 8) | (data[30] << 16) | (data[31] << 24);
  print('Encoder offset: $encoderOff');

  // Create BitStream and seek to encoder offset
  final bs = BitStream(data);
  bs.bytePos = encoderOff;

  // Read prefix (Python: self.prefix = self.bstr.read_unicode(self.bstr.read_int()))
  // read_int() is 4-byte big-endian
  final prefixLen = bs.readBits(32);
  // Wait, Python's read_int is a byte-level read (not bit-level). 
  // Let me read it as 4 bytes
  // Actually, the Python BitStream's read_int reads 4 bytes using struct.unpack_from('>L', ...)
  // This is a byte-level read that resets in_byte_pos
  
  // Actually this is where it gets tricky. The read_int() in Python is a byte-level operation,
  // but my Dart BitStream only has bit-level reads. Let me simulate byte-level reads.

  // For the Python code: prefix_len = self.bstr.read_int()
  // This reads 4 bytes as big-endian. In my bitstream, this would be readBits(32) if bitPos=0
  // But let me first check: is there a byte-level read_int in my BitStream?
  // Looking at lsd_decoder_dart.dart...
  
  // Actually let me read the LSD decoder and see how it reads the prefix
  // Then reproduce the exact same sequence
  
  // Hmm, let me instead just work directly with the data

  // The encoder section at offset encoderOff:
  // 4 bytes: prefixLen (big-endian)
  // prefixLen * 2 bytes: prefix text (UTF-16 big-endian)
  // Then read_symbols:
  //   32 bits: size
  //   8 bits: bitsPerSymbol
  //   size * bitsPerSymbol bits: symbols
  // Then LenTable:
  //   32 bits: count
  //   8 bits: bitsPerLen
  //   count entries of (idxBitSize-bit idx, bitsPerLen-bit length)

  // Let me just read with the BitStream from the encoder offset
  bs.bytePos = encoderOff;
  bs.bitPos = 0;
  
  // Step 1: prefixLen (32 bits = 4 bytes)
  final pLen = bs.readBits(32);
  print('\nPrefix len (readBits 32): $pLen');
  if (pLen == 16000) print('  ✓ matches expected 16000');
  else print('  ✗ expected 16000');
  
  // Verify
  var pLenBE = (data[encoderOff] << 24) | (data[encoderOff+1] << 16) | (data[encoderOff+2] << 8) | data[encoderOff+3];
  print('  Big-endian bytes: $pLenBE');
  
  // Step 2: read prefix text using the same method as the decoder
  final prefix = bs.readUnicode(pLen);
  print('After prefix text: bytePos=${bs.bytePos} bitPos=${bs.bitPos} (expected 33191, 0)');
  print('Prefix starts with: "${prefix.substring(0, 50)}"');
  
  // Step 3: read_symbols for articles (matches Python read_symbols)
  final articleSymCount = bs.readBits(32);
  final articleBitsPerSym = bs.readBits(8);
  print('\nArticle symbols: count=$articleSymCount bitsPerSym=$articleBitsPerSym');
  for (int i = 0; i < articleSymCount; i++) {
    bs.readBits(articleBitsPerSym);
  }
  print('After article symbols: bytePos=${bs.bytePos}, bitPos=${bs.bitPos}');
  
  // Step 4: read_symbols for headings (Python's 2nd call)
  final headingSymCount = bs.readBits(32);
  final headingBitsPerSym = bs.readBits(8);
  print('\nHeading symbols: count=$headingSymCount bitsPerSym=$headingBitsPerSym');
  for (int i = 0; i < headingSymCount; i++) {
    bs.readBits(headingBitsPerSym);
  }
  print('After heading symbols: bytePos=${bs.bytePos}, bitPos=${bs.bitPos}');
  
  // Step 5: LenTable for articles (ltArticles)
  print('\n--- LenTable (ltArticles) ---');
  final ltCount = bs.readBits(32);
  print('  count: $ltCount');
  final bitsPerLen = bs.readBits(8);
  print('  bitsPerLen: $bitsPerLen');
  
  if (ltCount > 0 && ltCount < 100000) {
    final idxBitSize = ltCount.bitLength;
    print('  idxBitSize: $idxBitSize');
    for (int i = 0; i < 10 && i < ltCount; i++) {
      final symIdx = bs.readBits(idxBitSize);
      final length = bs.readBits(bitsPerLen);
      print('  entry[$i]: symIdx=$symIdx length=$length');
    }
    // Skip rest
    for (int i = 10; i < ltCount; i++) {
      bs.readBits(idxBitSize);
      bs.readBits(bitsPerLen);
    }
  }
  
  print('After ltArticles: bytePos=${bs.bytePos}, bitPos=${bs.bitPos}');
  
  // Step 6: LenTable for headings (ltHeadings)
  print('\n--- LenTable (ltHeadings) ---');
  final ltCount2 = bs.readBits(32);
  print('  count: $ltCount2');
  final bitsPerLen2 = bs.readBits(8);
  print('  bitsPerLen: $bitsPerLen2');
  if (ltCount2 > 0 && ltCount2 < 100000) {
    final idxBitSize = ltCount2.bitLength;
    print('  idxBitSize: $idxBitSize');
    for (int i = 0; i < 10 && i < ltCount2; i++) {
      final symIdx = bs.readBits(idxBitSize);
      final length = bs.readBits(bitsPerLen2);
      print('  entry[$i]: symIdx=$symIdx length=$length');
    }
  }
  
  print('\nFinal: bytePos=${bs.bytePos}, bitPos=${bs.bitPos}');
}
