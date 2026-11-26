import 'package:flutter/material.dart';

/// Styles the buttons of a top bar that sits over a picture (a title's
/// backdrop, an album's cover, a collection's art): white icons on a soft
/// dark disc.
///
/// The bar took its icon color from the page (dark in the light theme), so
/// over dark artwork Back and the buttons beside it all but vanished, and
/// over a pale picture in the dark theme the white ones did. A disc of their
/// own reads on any picture, in either theme, and still reads once the bar
/// has scrolled onto the page.
///
/// Wrap the SliverAppBar itself, not the page: only the bar's buttons change.
class OverArtBar extends StatelessWidget {
  final Widget child;
  const OverArtBar({super.key, required this.child});

  static const _disc = Color(0x80000000);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        // A menu button takes its icon color from here, not from the
        // icon button style.
        popupMenuTheme: theme.popupMenuTheme.copyWith(iconColor: Colors.white),
        iconButtonTheme: IconButtonThemeData(
          style: const ButtonStyle(
            foregroundColor: WidgetStatePropertyAll(Colors.white),
            backgroundColor: WidgetStatePropertyAll(_disc),
          ),
        ),
      ),
      child: child,
    );
  }
}
