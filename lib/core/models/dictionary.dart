import 'dart:io';

class Dictionary {
  final String id;
  final String name;
  final String filePath;
  final String sourcePath;
  final String? cachedFilePath;
  final String? mediaDirectoryPath;
  final int wordCount;
  final DateTime loadedAt;
  final int displayOrder;

  Dictionary({
    required this.id,
    required this.name,
    required this.filePath,
    String? sourcePath,
    this.cachedFilePath,
    this.mediaDirectoryPath,
    this.wordCount = 0,
    DateTime? loadedAt,
    this.displayOrder = 0,
  })  : sourcePath = sourcePath ?? filePath,
        loadedAt = loadedAt ?? DateTime.now();

  String get fileName => File(filePath).uri.pathSegments.last;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'filePath': filePath,
        'sourcePath': sourcePath,
        'cachedFilePath': cachedFilePath,
        'mediaDirectoryPath': mediaDirectoryPath,
        'wordCount': wordCount,
        'loadedAt': loadedAt.toIso8601String(),
        'displayOrder': displayOrder,
      };

  factory Dictionary.fromJson(Map<String, dynamic> json) => Dictionary(
        id: json['id'] as String,
        name: json['name'] as String,
        filePath: json['filePath'] as String,
        sourcePath: json['sourcePath'] as String? ?? json['filePath'] as String,
        cachedFilePath: json['cachedFilePath'] as String?,
        mediaDirectoryPath: json['mediaDirectoryPath'] as String?,
        wordCount: json['wordCount'] as int,
        loadedAt: DateTime.parse(json['loadedAt'] as String),
        displayOrder: json['displayOrder'] as int? ?? 0,
      );

  Dictionary copyWith({
    String? id,
    String? name,
    String? filePath,
    String? sourcePath,
    String? cachedFilePath,
    String? mediaDirectoryPath,
    int? wordCount,
    DateTime? loadedAt,
    int? displayOrder,
  }) =>
      Dictionary(
        id: id ?? this.id,
        name: name ?? this.name,
        filePath: filePath ?? this.filePath,
        sourcePath: sourcePath ?? this.sourcePath,
        cachedFilePath: cachedFilePath ?? this.cachedFilePath,
        mediaDirectoryPath: mediaDirectoryPath ?? this.mediaDirectoryPath,
        wordCount: wordCount ?? this.wordCount,
        loadedAt: loadedAt ?? this.loadedAt,
        displayOrder: displayOrder ?? this.displayOrder,
      );
}
