import 'package:flutter/material.dart';

import '../app/theme.dart';

class FieldLine extends StatelessWidget {
  const FieldLine({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final empty = value.isEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(KeepassYRadius.control),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(KeepassYRadius.compact),
                ),
                child: Icon(icon, size: 19, color: colorScheme.primary),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 112,
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  empty ? 'Not set' : value,
                  style: TextStyle(
                    color: empty
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurface,
                    fontWeight: empty ? FontWeight.w500 : FontWeight.w600,
                  ),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
