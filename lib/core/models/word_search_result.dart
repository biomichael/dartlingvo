import '../search/search_engine.dart';

class WordSearchResult {
  final String word;
  final List<SearchResult> matches;

  const WordSearchResult({required this.word, required this.matches});

  SearchResult get primary => matches.first;
}