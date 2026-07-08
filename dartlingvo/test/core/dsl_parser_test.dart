import 'package:flutter_test/flutter_test.dart';
import 'package:dartlingvo/core/parsing/dsl_parser.dart';
import 'package:dartlingvo/core/models/formatted_text.dart';

void main() {
  group('DslParser', () {
    late DslParser parser;

    setUp(() {
      parser = DslParser(dictionaryId: 'test', dictionaryName: 'Test Dict');
    });

    test('parses header metadata', () {
      const dsl = '#NAME\t"Test Dictionary"\n#INDEX_LANGUAGE\t"English"\n\nhello\t[m1]world\n\n';
      final entries = parser.parseDsl(dsl);
      expect(entries.length, 1);
      expect(entries[0].word, 'hello');
    });

    test('parses simple word entry', () {
      const dsl = 'apple\t[m1]a fruit\n\n';
      final entries = parser.parseDsl(dsl);
      expect(entries.length, 1);
      expect(entries[0].word, 'apple');
      expect(entries[0].definitions.length, 1);
    });

    test('parses bold tags', () {
      const dsl = 'test\t[m1][b]bold text[/b]\n\n';
      final entries = parser.parseDsl(dsl);
      expect(entries.length, 1);
      final segments = entries[0].definitions[0].segments;
      expect(segments.any((s) => s.type == TextSegmentType.bold), true);
      expect(segments.any((s) => s.text.contains('bold text')), true);
    });

    test('parses italic tags', () {
      const dsl = 'test\t[m1][i]italic text[/i]\n\n';
      final entries = parser.parseDsl(dsl);
      final segments = entries[0].definitions[0].segments;
      expect(segments.any((s) => s.type == TextSegmentType.italic), true);
    });

    test('parses reference tags', () {
      const dsl = 'test\t[m1]see [ref]other word[/ref]\n\n';
      final entries = parser.parseDsl(dsl);
      final segments = entries[0].definitions[0].segments;
      expect(segments.any((s) => s.type == TextSegmentType.reference), true);
    });

    test('parses example tags', () {
      const dsl = 'test\t[m1][ex]example text[/ex]\n\n';
      final entries = parser.parseDsl(dsl);
      final segments = entries[0].definitions[0].segments;
      expect(segments.any((s) => s.type == TextSegmentType.example), true);
    });

    test('parses multiple entries', () {
      const dsl = 'apple\t[m1]fruit\n\nbanana\t[m1]yellow fruit\n\ncherry\t[m1]red fruit\n\n';
      final entries = parser.parseDsl(dsl);
      expect(entries.length, 3);
      expect(entries[0].word, 'apple');
      expect(entries[1].word, 'banana');
      expect(entries[2].word, 'cherry');
    });

    test('extracts name from header', () {
      const dsl = '#NAME\t"English-Russian Dictionary"\n#INDEX_LANGUAGE\t"English"\n\n';
      final name = DslParser.extractNameFromHeader(dsl);
      expect(name, 'English-Russian Dictionary');
    });

    test('returns default name when missing', () {
      const dsl = 'hello\t[m1]world\n\n';
      final name = DslParser.extractNameFromHeader(dsl);
      expect(name, 'Unnamed Dictionary');
    });

    test('handles nested tags', () {
      const dsl = 'test\t[m1][b]bold [i]bold+italic[/i][/b] plain\n\n';
      final entries = parser.parseDsl(dsl);
      final segments = entries[0].definitions[0].segments;
      expect(segments.length, greaterThanOrEqualTo(2));
    });

    test('handles multi-line definitions', () {
      const dsl = 'word\t[m1]first line\n\t[m1]second line\n\n';
      final entries = parser.parseDsl(dsl);
      expect(entries.length, 1);
      expect(entries[0].definitions.length, greaterThanOrEqualTo(1));
    });

    test('handles m1 and m2 markers', () {
      const dsl = 'test\t[m1]main definition\n\t[m2]secondary\n\n';
      final entries = parser.parseDsl(dsl);
      expect(entries.length, 1);
    });
  });
}
