import 'dart:typed_data';

class ResolvedMedia {
  final String name;
  final Uint8List bytes;

  const ResolvedMedia({
    required this.name,
    required this.bytes,
  });

  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot).toLowerCase();
  }

  String? get mimeType {
    final inferred = inferredExtension;
    switch (inferred) {
      case '.bmp':
        return 'image/bmp';
      case '.gif':
        return 'image/gif';
      case '.jpeg':
      case '.jpg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.wav':
        return 'audio/wav';
      case '.mp3':
        return 'audio/mpeg';
      case '.m4a':
      case '.aac':
        return 'audio/aac';
      case '.ogg':
        return 'audio/ogg';
      case '.flac':
        return 'audio/flac';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.mkv':
        return 'video/x-matroska';
      case '.webm':
        return 'video/webm';
      case '.avi':
        return 'video/x-msvideo';
      default:
        return null;
    }
  }

  String get inferredExtension {
    if (_hasPrefix([0x52, 0x49, 0x46, 0x46]) && _hasAsciiAt(8, 'WAVE')) {
      return '.wav';
    }
    if (_hasPrefix([0x49, 0x44, 0x33]) || _looksLikeMp3Frame()) {
      return '.mp3';
    }
    if (_hasPrefix([0x4f, 0x67, 0x67, 0x53])) {
      return '.ogg';
    }
    if (_hasPrefix([0x66, 0x4c, 0x61, 0x43])) {
      return '.flac';
    }
    if (_hasPrefix([0x00, 0x00, 0x00, 0x18]) && _hasAsciiAt(4, 'ftyp')) {
      return '.mp4';
    }
    if (_hasPrefix([0x00, 0x00, 0x00, 0x14]) && _hasAsciiAt(4, 'ftyp')) {
      return '.mp4';
    }
    return extension;
  }

  bool get isImage => const {'.bmp', '.gif', '.jpeg', '.jpg', '.png', '.webp'}.contains(inferredExtension);
  bool get isAudio => const {'.wav', '.mp3', '.m4a', '.aac', '.ogg', '.flac'}.contains(inferredExtension);
  bool get isVideo => const {'.mp4', '.mov', '.mkv', '.webm', '.avi'}.contains(inferredExtension);

  bool _hasPrefix(List<int> prefix) {
    if (bytes.length < prefix.length) {
      return false;
    }
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }

  bool _hasAsciiAt(int offset, String text) {
    if (bytes.length < offset + text.length) {
      return false;
    }
    for (var i = 0; i < text.length; i++) {
      if (bytes[offset + i] != text.codeUnitAt(i)) {
        return false;
      }
    }
    return true;
  }

  bool _looksLikeMp3Frame() {
    if (bytes.length < 2) {
      return false;
    }
    return bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
  }
}
