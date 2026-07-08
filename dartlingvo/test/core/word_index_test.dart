import 'package:flutter_test/flutter_test.dart';
import 'package:dartlingvo/core/index/word_index.dart';
import 'package:dartlingvo/core/models/dictionary_entry.dart';

void main() {
  group('WordIndex', () {
    late WordIndex index;

    setUp(() {
      index = WordIndex();
    });

    test('starts empty', () {
      expect(index.isEmpty, true);
      expect(index.size, 0);
    });

    test('adds entries', () {
      index.addEntry(WordIndexEntry(
        word: 'apple', dictionaryId: 'd1', dictionaryName: 'Dict 1'));
      expect(index.isEmpty, false);
      expect(index.size, 1);
    });

    test('searches by exact prefix', () {
      index.addEntry(WordIndexEntry(
        word: 'apple', dictionaryId: 'd1', dictionaryName: 'Dict 1'));
      index.addEntry(WordIndexEntry(
        word: 'application', dictionaryId: 'd1', dictionaryName: 'Dict 1'));
      index.addEntry(WordIndexEntry(
        word: 'banana', dictionaryId: 'd1', dictionaryName: 'Dict 1'));

      final results = index.searchByPrefix('app');
      expect(results.length, 2);
      expect(results.map((e) => e.word), containsAll(['apple', 'application']));
    });

    test('prefix search is case-insensitive', () {
      index.addEntry(WordIndexEntry(
        word: 'Apple', dictionaryId: 'd1', dictionaryName: 'Dict 1'));
      index.addEntry(WordIndexEntry(
        word: 'APPLE', dictionaryId: 'd1', dictionaryName: 'Dict 1'));

      final results = index.searchByPrefix('app');
      expect(results.length, 2);
    });

    test('fuzzy search finds approximate matches', () {
      index.addEntry(WordIndexEntry(
        word: 'apple', dictionaryId: 'd1', dictionaryName: 'Dict 1'));
      index.addEntry(WordIndexEntry(
        word: 'aple', dictionaryId: 'd1', dictionaryName: 'Dict 1'));

      final results = index.fuzzySearch('appl');
      expect(results.isNotEmpty, true);
    });

    test('exact search finds exact match', () {
      index.addEntry(WordIndexEntry(
        word: 'apple', dictionaryId: 'd1', dictionaryName: 'Dict 1'));
      index.addEntry(WordIndexEntry(
        word: 'pineapple', dictionaryId: 'd1', dictionaryName: 'Dict 1'));

      final results = index.exactSearch('apple');
      expect(results.length, 1);
      expect(results[0].word, 'apple');
    });

    test('clears correctly', () {
      index.addEntry(WordIndexEntry(
        word: 'test', dictionaryId: 'd1', dictionaryName: 'Dict 1'));
      expect(index.isEmpty, false);
      index.clear();
      expect(index.isEmpty, true);
    });

    test('getAllWords returns unique sorted words', () {
      index.addEntry(WordIndexEntry(
        word: 'banana', dictionaryId: 'd1', dictionaryName: 'Dict 1'));
      index.addEntry(WordIndexEntry(
        word: 'apple', dictionaryId: 'd1', dictionaryName: 'Dict 1'));
      index.addEntry(WordIndexEntry(
        word: 'apple', dictionaryId: 'd2', dictionaryName: 'Dict 2'));

      final words = index.getAllWords();
      expect(words, ['apple', 'banana']);
    });
  });
}
