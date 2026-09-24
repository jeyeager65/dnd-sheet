import 'package:flutter/material.dart';

/// Wider than a phone - a desktop window or a tablet in landscape. Screens
/// with a side panel (the character sheet's tabs, Reference's categories)
/// switch to it at this width.
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 700;

/// Keeps a screen's content at a readable width, centered, on a wide
/// window instead of stretching edge to edge. A phone is narrower than
/// [maxWidth], so nothing changes there.
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child, this.maxWidth = 720});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}
