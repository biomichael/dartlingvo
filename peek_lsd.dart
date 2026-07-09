import 'dart:io';
import 'dart:typed_data';

void main() {
  final path = r'C:\Users\MZDEV\Downloads\Dictionaries\EnglishEtymology.lsd';
  final file = File(path);
  final data = file.readAsBytesSync();
  
  var encoderOff = data[28] | (data[29] << 8) | (data[30] << 16) | (data[31] << 24);
  print('Encoder offset: $encoderOff');
  
  // After prefix (16000 chars), symbols table (231 symbols * 17 bits)
  // symbol table: 32 bits count + 8 bits perSym + 231 * 17 bits
  // After that, LenTable starts
  var prefixStart = encoderOff + 4;
  var prefixLen = (data[encoderOff] << 24) | (data[encoderOff+1] << 16) | (data[encoderOff+2] << 8) | data[encoderOff+3];
  
  // Symbols table position  
  var symStart = prefixStart + prefixLen * 2;
  // After 32-bit count (0,0,0,E7) and 8-bit bitsPerSym (11):
  var lenTableStartBits = 40; // bits from symStart
  var lenTableStartBytes = symStart + 5; // 4 for count + 1 for bitsPerSym
  // But the symbols themselves occupy 231 * 17 = 3927 bits = 490.875 bytes
  // So LenTable starts about 491 bytes after
  var totalSymBits = 40 + 231 * 17;
  var totalSymBytes = (totalSymBits + 7) ~/ 8;
  var ltStartByte = symStart + totalSymBytes;
  
  print('Prefix len: $prefixLen');
  print('Symbols start: $symStart');
  print('Total sym bits: $totalSymBits');
  print('LT start byte: $ltStartByte');
  
  // Dump bytes at LT start
  print('\n--- Bytes at LT start ($ltStartByte) ---');
  for (int i = 0; i < 80 && ltStartByte + i < data.length; i++) {
    print('  [${ltStartByte+i}] = 0x${data[ltStartByte+i].toRadixString(16).padLeft(2, '0')} (${data[ltStartByte+i]})');
  }
  
  // Try reading 12 bits as count
  var pos = ltStartByte;
  // First 12 bits
  var n12 = ((data[pos] << 4) | (data[pos+1] >> 4)) & 0xFFF;
  print('\nFirst 12 bits as count: $n12');
  
  // Try reading 32 bits as count (what Dart does)
  var n32 = (data[pos] << 24) | (data[pos+1] << 16) | (data[pos+2] << 8) | data[pos+3];
  print('First 32 bits as count: $n32');
  
  if (n12 > 0 && n12 < 10000) {
    print('\n--- Reading as 12-bit count + 8-bit lengths ---');
    var bp = pos;
    var n = ((data[bp] << 4) | (data[bp+1] >> 4)) & 0xFFF;
    bp += 1; // consumed 12 bits from first byte + part of second
    // Actually let me read bit by bit for accuracy
  }
  
  // Just show first 20 bytes as both formats
  print('\n--- First 20 bytes as 8-bit lengths ---');
  for (int i = 0; i < 20 && ltStartByte + i < data.length; i++) {
    print('  length[$i] = ${data[ltStartByte+i]}');
  }
  
  // Also show what Python-style 12/8 gives
  print('\n--- 12-bit count from bit 0 at LT start ---');
  // Read 12 bits properly:
  pos = ltStartByte;
  var bitBuf = 0;
  var bitCount = 0;
  // Read 12 bits
  for (int b = 0; b < 12; b++) {
    bitBuf = (bitBuf << 1) | ((data[pos] >> (7 - bitCount)) & 1);
    bitCount++;
    if (bitCount == 8) { pos++; bitCount = 0; }
  }
  print('count (12-bit): $bitBuf');
  
  // Now read 8-bit lengths
  if (bitBuf > 0 && bitBuf < 100000) {
    for (int k = 0; k < 10 && k < bitBuf; k++) {
      var lenVal = 0;
      for (int b = 0; b < 8; b++) {
        lenVal = (lenVal << 1) | ((data[pos] >> (7 - bitCount)) & 1);
        bitCount++;
        if (bitCount == 8) { pos++; bitCount = 0; }
      }
      print('  length[$k] = $lenVal');
    }
  }
}
