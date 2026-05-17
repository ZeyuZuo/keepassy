import 'package:flutter/material.dart';

import '../app/theme.dart';

class PaneSurface extends StatelessWidget {
  const PaneSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(KeepassYRadius.panel),
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
