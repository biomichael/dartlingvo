import '../managers/navigation_history.dart';

class LookupTab {
  final String id;
  String title;
  String searchQuery;
  bool _titleSetFromSelection = false;
  final List<NavigationEntry> _backStack = [];
  final List<NavigationEntry> _forwardStack = [];
  NavigationEntry? currentEntry;

  LookupTab({
    required this.id,
    required this.title,
    this.searchQuery = '',
    this.currentEntry,
  });

  List<NavigationEntry> get backStack => List.unmodifiable(_backStack);
  List<NavigationEntry> get forwardStack => List.unmodifiable(_forwardStack);
  bool get canGoBack => _backStack.isNotEmpty;
  bool get canGoForward => _forwardStack.isNotEmpty;

  NavigationEntry? get previousEntry => canGoBack ? _backStack.last : null;
  NavigationEntry? get nextEntry => canGoForward ? _forwardStack.last : null;

  void setQuery(String value) {
    searchQuery = value;
  }

  void setTitleFromSelection(String value) {
    if (_titleSetFromSelection) {
      return;
    }

    title = value;
    _titleSetFromSelection = true;
  }

  void navigateTo(String word, String dictionaryId) {
    if (currentEntry != null) {
      _backStack.add(currentEntry!);
    }
    _forwardStack.clear();
    currentEntry = NavigationEntry(word: word, dictionaryId: dictionaryId);
  }

  void goBack() {
    if (!canGoBack) return;
    if (currentEntry != null) {
      _forwardStack.add(currentEntry!);
    }
    currentEntry = _backStack.removeLast();
  }

  void goForward() {
    if (!canGoForward) return;
    if (currentEntry != null) {
      _backStack.add(currentEntry!);
    }
    currentEntry = _forwardStack.removeLast();
  }
}