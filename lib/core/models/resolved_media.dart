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
    switch (extension) {
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

  bool get isImage => const {'.bmp', '.gif', '.jpeg', '.jpg', '.png', '.webp'}.contains(extension);
  bool get isAudio => const {'.wav', '.mp3', '.m4a', '.aac', '.ogg', '.flac'}.contains(extension);
  bool get isVideo => const {'.mp4', '.mov', '.mkv', '.webm', '.avi'}.contains(extension);
}
