import 'package:flutter/foundation.dart';
import '../models/lookup_tab.dart';
import 'navigation_history.dart';

class LookupTabManager extends ChangeNotifier {
  final List<LookupTab> _tabs = [];
  int _tabCounter = 0;
  String? _activeTabId;

  LookupTabManager() {
    _createInitialTab();
  }

  List<LookupTab> get tabs => List.unmodifiable(_tabs);
  bool get hasTabs => _tabs.isNotEmpty;
  String? get activeTabId => _activeTabId;

  LookupTab get activeTab =>
      _tabs.firstWhere((tab) => tab.id == _activeTabId);

  String get activeQuery => activeTab.searchQuery;

  NavigationEntry? get activeNavigationEntry => activeTab.currentEntry;
  bool get canGoBack => activeTab.canGoBack;
  bool get canGoForward => activeTab.canGoForward;
  NavigationEntry? get previousEntry => activeTab.previousEntry;
  NavigationEntry? get nextEntry => activeTab.nextEntry;

  void openTab({String? title}) {
    final entry = activeTab.currentEntry;
    final tab = _createTab(title: title);
    _tabs.add(tab);
    _activeTabId = tab.id;
    if (entry != null) {
      tab.navigateTo(entry.word, entry.dictionaryId);
      tab.setTitleFromSelection(entry.word);
    }
    notifyListeners();
  }

  void closeTab(String id) {
    if (_tabs.length == 1 && _tabs.first.id == id) {
      return;
    }

    final index = _tabs.indexWhere((tab) => tab.id == id);
    if (index == -1) return;

    final wasActive = _activeTabId == id;
    _tabs.removeAt(index);

    if (wasActive) {
      final nextIndex = index < _tabs.length ? index : _tabs.length - 1;
      _activeTabId = _tabs[nextIndex].id;
    }

    notifyListeners();
  }

  void activateTab(String id) {
    if (_activeTabId == id) return;
    if (_tabs.any((tab) => tab.id == id)) {
      _activeTabId = id;
      notifyListeners();
    }
  }

  void setQuery(String value) {
    activeTab.setQuery(value);
    notifyListeners();
  }

  void clearQuery() {
    setQuery('');
  }

  void navigateTo(String word, String dictionaryId) {
    activeTab.navigateTo(word, dictionaryId);
    activeTab.setTitleFromSelection(word);
    notifyListeners();
  }

  void closeOtherTabs() {
    if (_tabs.length <= 1) return;

    final activeId = _activeTabId;
    if (activeId == null) return;

    _tabs.removeWhere((tab) => tab.id != activeId);
    _activeTabId = activeId;
    notifyListeners();
  }

  void goBack() {
    activeTab.goBack();
    notifyListeners();
  }

  void goForward() {
    activeTab.goForward();
    notifyListeners();
  }

  LookupTab _createTab({String? title}) {
    _tabCounter++;
    return LookupTab(
      id: 'tab_$_tabCounter',
      title: title ?? 'New tab',
    );
  }

  LookupTab _createInitialTab() {
    final tab = _createTab();
    _tabs.add(tab);
    _activeTabId = tab.id;
    return tab;
  }
}