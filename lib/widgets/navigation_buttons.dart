import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';

class NavigationButtons extends ConsumerWidget {
  const NavigationButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(lookupTabManagerProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ArrowNavButton(
          icon: Icons.arrow_back,
          onPressed: tabs.canGoBack ? tabs.goBack : null,
          tooltip: tabs.previousEntry?.word == null
              ? 'Previous word'
              : 'Previous word: ${tabs.previousEntry!.word}',
        ),
        const SizedBox(width: 2),
        _ArrowNavButton(
          icon: Icons.arrow_forward,
          onPressed: tabs.canGoForward ? tabs.goForward : null,
          tooltip: tabs.nextEntry?.word == null
              ? 'Next word'
              : 'Next word: ${tabs.nextEntry!.word}',
        ),
      ],
    );
  }
}

class _ArrowNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  const _ArrowNavButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: isEnabled ? 1.0 : 0.35,
            child: Icon(icon, size: 20),
          ),
        ),
      ),
    );
  }
}
