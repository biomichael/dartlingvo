import 'package:flutter/foundation.dart';

class NavigationEntry {
  final String word;
  final String dictionaryId;

  const NavigationEntry({required this.word, required this.dictionaryId});

  String get lookupKey => '$dictionaryId:$word';

  @override
  bool operator ==(Object other) =>
      other is NavigationEntry && other.lookupKey == lookupKey;

  @override
  int get hashCode => lookupKey.hashCode;
}

class NavigationHistory extends ChangeNotifier {
  final List<NavigationEntry> _backStack = [];
  final List<NavigationEntry> _forwardStack = [];
  NavigationEntry? _current;

  NavigationEntry? get current => _current;
  bool get canGoBack => _backStack.isNotEmpty;
  bool get canGoForward => _forwardStack.isNotEmpty;
  List<NavigationEntry> get history => List.unmodifiable(_backStack);
    NavigationEntry? get previousEntry =>
      _backStack.isNotEmpty ? _backStack.last : null;
    NavigationEntry? get nextEntry =>
      _forwardStack.isNotEmpty ? _forwardStack.last : null;

  void navigateTo(String word, String dictionaryId) {
    if (_current != null) {
      _backStack.add(_current!);
    }
    _forwardStack.clear();
    _current = NavigationEntry(word: word, dictionaryId: dictionaryId);
    notifyListeners();
  }

  void goBack() {
    if (!canGoBack) return;
    if (_current != null) {
      _forwardStack.add(_current!);
    }
    _current = _backStack.removeLast();
    notifyListeners();
  }

  void goForward() {
    if (!canGoForward) return;
    if (_current != null) {
      _backStack.add(_current!);
    }
    _current = _forwardStack.removeLast();
    notifyListeners();
  }

  void clear() {
    _backStack.clear();
    _forwardStack.clear();
    _current = null;
    notifyListeners();
  }
}
