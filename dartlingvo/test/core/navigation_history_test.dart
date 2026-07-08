import 'package:flutter_test/flutter_test.dart';
import 'package:dartlingvo/core/managers/navigation_history.dart';

void main() {
  group('NavigationHistory', () {
    late NavigationHistory history;

    setUp(() {
      history = NavigationHistory();
    });

    test('starts with no current entry', () {
      expect(history.current, isNull);
      expect(history.canGoBack, false);
      expect(history.canGoForward, false);
    });

    test('navigates to first entry', () {
      history.navigateTo('apple', 'd1');
      expect(history.current?.word, 'apple');
      expect(history.canGoBack, false);
      expect(history.canGoForward, false);
    });

    test('maintains back stack', () {
      history.navigateTo('apple', 'd1');
      history.navigateTo('banana', 'd1');
      expect(history.current?.word, 'banana');
      expect(history.canGoBack, true);
    });

    test('goBack navigates to previous entry', () {
      history.navigateTo('apple', 'd1');
      history.navigateTo('banana', 'd1');
      history.goBack();
      expect(history.current?.word, 'apple');
      expect(history.canGoForward, true);
    });

    test('goForward navigates forward', () {
      history.navigateTo('apple', 'd1');
      history.navigateTo('banana', 'd1');
      history.goBack();
      history.goForward();
      expect(history.current?.word, 'banana');
    });

    test('clears forward stack on new navigation', () {
      history.navigateTo('apple', 'd1');
      history.navigateTo('banana', 'd1');
      history.goBack();
      history.navigateTo('cherry', 'd1');
      expect(history.canGoForward, false);
    });

    test('clear resets everything', () {
      history.navigateTo('apple', 'd1');
      history.navigateTo('banana', 'd1');
      history.clear();
      expect(history.current, isNull);
      expect(history.canGoBack, false);
      expect(history.canGoForward, false);
    });
  });
}
