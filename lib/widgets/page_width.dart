import 'package:flutter/widgets.dart';

/// How wide a page of settings or plain rows gets on a big window: past this
/// a row's name and its switch drift too far apart to read as one line.
const pageMaxWidth = 840.0;

/// A list's padding with [inset] added each side (see [PageWidth]).
EdgeInsets pageInsets(double inset, [EdgeInsets base = EdgeInsets.zero]) =>
    base + EdgeInsets.symmetric(horizontal: inset);

/// Keeps a page's list a readable width on a wide window. The list still
/// spans the window, so the wheel and the scrollbar work anywhere on it; its
/// rows stay in a centered column, by the [inset] the builder adds to the
/// list's own padding. Zero on a phone.
class PageWidth extends StatelessWidget {
  final Widget Function(BuildContext context, double inset) builder;
  final double maxWidth;
  const PageWidth({
    super.key,
    required this.builder,
    this.maxWidth = pageMaxWidth,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => builder(
      context,
      c.maxWidth > maxWidth ? (c.maxWidth - maxWidth) / 2 : 0,
    ),
  );
}

/// What sits above such a list without scrolling (a search box, a line of
/// help): kept to the same column, so it lines up with the rows under it.
class PageHeader extends StatelessWidget {
  final Widget child;
  const PageHeader({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: pageMaxWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}
