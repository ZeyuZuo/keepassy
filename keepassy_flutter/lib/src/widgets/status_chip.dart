import 'package:flutter/material.dart';

import '../app/theme.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.dirty,
    required this.saving,
    required this.conflict,
    this.error,
  });

  final bool dirty;
  final bool saving;
  final bool conflict;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final vaultColors = Theme.of(context).extension<KeepassYVaultColors>();

    Widget child;
    if (saving) {
      child = _StatusPill(
        key: const ValueKey('saving'),
        label: 'Saving',
        foreground: colorScheme.primary,
        background: colorScheme.primaryContainer.withValues(alpha: 0.58),
        leading: SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        ),
      );
    } else if (conflict) {
      child = _StatusPill(
        key: const ValueKey('conflict'),
        label: 'Conflict',
        icon: Icons.sync_problem_outlined,
        foreground: colorScheme.onErrorContainer,
        background: colorScheme.errorContainer,
      );
    } else if (error != null) {
      child = _StatusPill(
        key: const ValueKey('failed'),
        label: 'Save failed',
        icon: Icons.error_outline,
        foreground: colorScheme.onErrorContainer,
        background: colorScheme.errorContainer,
      );
    } else if (dirty) {
      child = _StatusPill(
        key: const ValueKey('dirty'),
        label: 'Unsaved',
        icon: Icons.edit_outlined,
        foreground:
            vaultColors?.onWarningContainer ?? colorScheme.onPrimaryContainer,
        background:
            vaultColors?.warningContainer ?? colorScheme.primaryContainer,
      );
    } else {
      child = const SizedBox(key: ValueKey('empty'), width: 0, height: 0);
    }

    return AnimatedSwitcher(
      duration: KeepassYMotion.fast,
      switchInCurve: KeepassYMotion.curve,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    this.icon,
    this.leading,
  });

  final String label;
  final Color foreground;
  final Color background;
  final IconData? icon;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) leading!,
          if (leading == null && icon != null)
            Icon(icon, size: 15, color: foreground),
          if (leading != null || icon != null) const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}
