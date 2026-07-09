import '../models/formatted_text.dart';

class _LingvoStyle {
  final TextSegmentType type;
  final String? color;
  final bool underline;
  final bool strikeThrough;
  final bool superscript;
  final bool subscript;

  const _LingvoStyle({
    this.type = TextSegmentType.plain,
    this.color,
    this.underline = false,
    this.strikeThrough = false,
    this.superscript = false,
    this.subscript = false,
  });

  _LingvoStyle copyWith({
    TextSegmentType? type,
    String? color,
    bool? underline,
    bool? strikeThrough,
    bool? superscript,
    bool? subscript,
  }) {
    return _LingvoStyle(
      type: type ?? this.type,
      color: color ?? this.color,
      underline: underline ?? this.underline,
      strikeThrough: strikeThrough ?? this.strikeThrough,
      superscript: superscript ?? this.superscript,
      subscript: subscript ?? this.subscript,
    );
  }
}

class _TagResolution {
  final bool handled;
  final _LingvoStyle? style;

  const _TagResolution({required this.handled, this.style});
}

List<FormattedText> parseLingvoFormattedText(String text) {
  if (text.isEmpty) {
    return [FormattedText(segments: [const TextSegment(type: TextSegmentType.plain, text: '')])];
  }

  final blocks = _splitIntoBlocks(text);
  final result = <FormattedText>[];

  for (final block in blocks) {
    final segments = _parseBlock(block);
    if (segments.isNotEmpty) {
      result.add(FormattedText(segments: segments));
    }
  }

  if (result.isEmpty) {
    result.add(FormattedText(segments: [const TextSegment(type: TextSegmentType.plain, text: '')]));
  }

  return result;
}

List<String> _splitIntoBlocks(String text) {
  final blocks = <String>[];
  final lines = text.split('\n');
  var current = StringBuffer();

  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('[m1]') || trimmed.startsWith('[m2]')) {
      if (current.isNotEmpty) {
        blocks.add(current.toString().trim());
        current = StringBuffer();
      }
      current.write(line);
      continue;
    }

    if (current.isNotEmpty) {
      current.write('\n');
    }
    current.write(line);
  }

  if (current.isNotEmpty) {
    blocks.add(current.toString().trim());
  }

  return blocks;
}

List<TextSegment> _parseBlock(String text) {
  final segments = <TextSegment>[];
  final styleStack = <_LingvoStyle>[_LingvoStyle()];
  final buffer = StringBuffer();

  void flushBuffer() {
    if (buffer.isEmpty) return;
    final style = styleStack.last;
    segments.add(TextSegment(
      type: style.type,
      text: buffer.toString(),
      color: style.color,
      underline: style.underline,
      strikeThrough: style.strikeThrough,
      superscript: style.superscript,
      subscript: style.subscript,
    ));
    buffer.clear();
  }

  bool consumeEscape(int index) {
    if (index + 1 >= text.length) return false;
    buffer.write(text[index + 1]);
    return true;
  }

  bool isClosingTag(String tag) => tag.startsWith('/');

  String? parseColorTagValue(String tag) {
    final trimmed = tag.trim();
    if (trimmed.length <= 1) {
      return null;
    }

    final payload = trimmed.substring(1).trim();
    if (payload.isEmpty) {
      return null;
    }

    final separatorIndex = payload.indexOf(RegExp(r'[=:]'));
    var value = separatorIndex >= 0 ? payload.substring(separatorIndex + 1).trim() : payload;

    while (value.isNotEmpty && '"\'([{'.contains(value[0])) {
      value = value.substring(1).trimLeft();
    }
    while (value.isNotEmpty && '"\')]}' .contains(value[value.length - 1])) {
      value = value.substring(0, value.length - 1).trimRight();
    }

    return value;
  }

  _TagResolution applyOpenTag(_LingvoStyle current, String tag) {
    final normalized = tag.toLowerCase().trim();
    if (normalized == 'b') {
      return _TagResolution(handled: true, style: current.copyWith(type: TextSegmentType.bold));
    }
    if (normalized == 'i') {
      return _TagResolution(handled: true, style: current.copyWith(type: TextSegmentType.italic));
    }
    if (normalized == 'ref') {
      return _TagResolution(handled: true, style: current.copyWith(type: TextSegmentType.reference));
    }
    if (normalized == 'ex') {
      return _TagResolution(handled: true, style: current.copyWith(type: TextSegmentType.example));
    }
    if (normalized == 'u') {
      return _TagResolution(handled: true, style: current.copyWith(underline: true));
    }
    if (normalized == 's') {
      return _TagResolution(handled: true, style: current.copyWith(strikeThrough: true));
    }
    if (normalized == 'sup') {
      return _TagResolution(handled: true, style: current.copyWith(superscript: true));
    }
    if (normalized == 'sub') {
      return _TagResolution(handled: true, style: current.copyWith(subscript: true));
    }
    if (normalized == 'p' || normalized == 'm' || normalized == 'm1' || normalized == 'm2' || normalized == '*') {
      return const _TagResolution(handled: true);
    }
    if (normalized == 'c' || normalized.startsWith('c ')) {
      final color = parseColorTagValue(tag);
      return _TagResolution(
        handled: true,
        style: current.copyWith(color: color == null || color.isEmpty ? null : color),
      );
    }
    if (normalized.startsWith('lang') || normalized.startsWith('trn') || normalized.startsWith('com')) {
      return const _TagResolution(handled: true);
    }
    return const _TagResolution(handled: false);
  }

  void popStyle() {
    if (styleStack.length > 1) {
      styleStack.removeLast();
    }
  }

  int i = 0;
  while (i < text.length) {
    final ch = text[i];

    if (ch == '\\') {
      if (consumeEscape(i)) {
        i += 2;
        continue;
      }
    }

    if (ch == '[') {
      final close = text.indexOf(']', i);
      if (close == -1) {
        buffer.write(ch);
        i++;
        continue;
      }

      final tag = text.substring(i + 1, close).trim();
      if (tag.isEmpty) {
        buffer.write('[]');
        i = close + 1;
        continue;
      }

      flushBuffer();

      if (isClosingTag(tag)) {
        final closeName = tag.substring(1).toLowerCase().trim();
        if (['b', 'i', 'ref', 'ex', 'u', 's', 'sup', 'sub', 'c'].contains(closeName)) {
          popStyle();
        }
        i = close + 1;
        continue;
      }

      final nextStyle = applyOpenTag(styleStack.last, tag);
      if (nextStyle.handled && nextStyle.style != null) {
        styleStack.add(nextStyle.style!);
        i = close + 1;
        continue;
      }

      if (tag.toLowerCase() == 'br') {
        buffer.write('\n');
        i = close + 1;
        continue;
      }

      if (nextStyle.handled) {
        i = close + 1;
        continue;
      }

      // Unknown Lingvo markup is stripped rather than rendered.
      i = close + 1;
      continue;
    }

    buffer.write(ch);
    i++;
  }

  flushBuffer();
  return segments;
}
