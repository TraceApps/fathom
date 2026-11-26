import 'package:flutter/material.dart';

/// How well two colors read against each other (WCAG contrast, 1 to 21).
double contrastOf(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

const _darkInk = Color(0xFF10151C);

/// The text color for a solid status pill. White is the house look and stays
/// wherever it reads; on the green and the amber it didn't (about 2:1), so
/// those get dark text.
Color onStatus(Color fill) =>
    contrastOf(Colors.white, fill) >= 3 ? Colors.white : _darkInk;

/// A status color as text or a small icon on the page itself. The bright
/// green and amber are made for a dark page; on a light one they wash out,
/// so they are deepened there until they read (4.5:1). Unchanged in the dark.
Color statusInk(BuildContext context, Color color) {
  final theme = Theme.of(context);
  if (theme.brightness == Brightness.dark) return color;
  final page = theme.colorScheme.surface;
  var hsl = HSLColor.fromColor(color);
  var ink = color;
  while (contrastOf(ink, page) < 4.5 && hsl.lightness > 0.05) {
    hsl = hsl.withLightness(hsl.lightness - 0.03);
    ink = hsl.toColor();
  }
  return ink;
}
