enum TextSegmentType { plain, bold, italic, example, reference }

class TextSegment {
  final TextSegmentType type;
  final String text;
      final String? color;
      final bool underline;
      final bool strikeThrough;
      final bool superscript;
      final bool subscript;

      const TextSegment({
            required this.type,
            required this.text,
            this.color,
            this.underline = false,
            this.strikeThrough = false,
            this.superscript = false,
            this.subscript = false,
      });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'text': text,
                        'color': color,
                        'underline': underline,
                        'strikeThrough': strikeThrough,
                        'superscript': superscript,
                        'subscript': subscript,
      };

  factory TextSegment.fromJson(Map<String, dynamic> json) => TextSegment(
        type: TextSegmentType.values.byName(json['type'] as String),
        text: json['text'] as String,
                        color: json['color'] as String?,
                        underline: json['underline'] as bool? ?? false,
                        strikeThrough: json['strikeThrough'] as bool? ?? false,
                        superscript: json['superscript'] as bool? ?? false,
                        subscript: json['subscript'] as bool? ?? false,
      );
}

class FormattedText {
  final List<TextSegment> segments;

  const FormattedText({required this.segments});

  String get plainText => segments.map((s) => s.text).join();

  bool get isEmpty => segments.every((s) => s.text.isEmpty);

  Map<String, dynamic> toJson() => {
        'segments': segments.map((s) => s.toJson()).toList(),
      };

  factory FormattedText.fromJson(Map<String, dynamic> json) => FormattedText(
        segments: (json['segments'] as List)
            .map((s) => TextSegment.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}
