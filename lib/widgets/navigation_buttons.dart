import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';

class NavigationButtons extends ConsumerWidget {
  const NavigationButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = ref.watch(lookupTabManagerProvider);
    final isCompact = MediaQuery.sizeOf(context).height < 500 ||
        MediaQuery.viewInsetsOf(context).bottom > 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ArrowNavButton(
          icon: Icons.arrow_back,
          onPressed: tabs.canGoBack ? tabs.goBack : null,
          tooltip: tabs.previousEntry?.word == null
              ? 'Previous word'
              : 'Previous word: ${tabs.previousEntry!.word}',
          isCompact: isCompact,
        ),
        const SizedBox(width: 2),
        _ArrowNavButton(
          icon: Icons.arrow_forward,
          onPressed: tabs.canGoForward ? tabs.goForward : null,
          tooltip: tabs.nextEntry?.word == null
              ? 'Next word'
              : 'Next word: ${tabs.nextEntry!.word}',
          isCompact: isCompact,
        ),
      ],
    );
  }
}

class _ArrowNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool isCompact;

  const _ArrowNavButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    required this.isCompact,
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
          padding: EdgeInsets.all(isCompact ? 6 : 8),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: isEnabled ? 1.0 : 0.35,
            child: Icon(icon, size: isCompact ? 18 : 20),
          ),
        ),
      ),
    );
  }
}
