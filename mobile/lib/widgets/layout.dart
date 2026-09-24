import 'package:flutter/material.dart';

/// Wider than a phone - a desktop window or a tablet in landscape. Screens
/// with a side panel (the character sheet's tabs, Reference's categories)
/// switch to it at this width.
bool isWideLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 700;
