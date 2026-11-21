import 'package:flutter/widgets.dart';

import '../models/arr.dart';

/// A show or movie, by the app that manages it and its id there.
typedef ArrTitleRef = ({ArrKind kind, int id});

/// How wide the pane beside the lists is in a Manage section [width] wide;
/// null when the section is too narrow for one. The lists keep more than
/// 620: what a phone's layout needs, with room to spare.
double? arrPaneWidth(double width) =>
    width < 1040 ? null : (width * 0.4).clamp(400.0, 520.0);

/// The Manage section, for the lists inside it: on a wide window a title
/// opens in a pane beside the list instead of on a page of its own.
class ArrPaneScope extends InheritedWidget {
  /// The title in the pane; null with the pane closed.
  final ArrTitleRef? shown;

  /// Opens a title in the pane; null when the window is too narrow for one,
  /// and titles open as pages.
  final void Function(ArrKind kind, int id)? open;

  /// Told when a title opens as a page because there's no room for the
  /// pane: the title kept for a wider window is no longer the last one
  /// looked at.
  final VoidCallback? onPage;

  const ArrPaneScope({
    super.key,
    required this.shown,
    required this.open,
    this.onPage,
    required super.child,
  });

  /// The scope around [context], without listening to it: for opening.
  static ArrPaneScope? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ArrPaneScope>();

  /// Whether the pane is showing this title, so its row or poster can say
  /// so. Listens: the answer changes as titles open and close.
  static bool shows(BuildContext context, ArrKind kind, int? id) {
    if (id == null) return false;
    final shown = context
        .dependOnInheritedWidgetOfExactType<ArrPaneScope>()
        ?.shown;
    return shown != null && shown.kind == kind && shown.id == id;
  }

  /// Whether Back closes the pane here. It then does only that, as Escape
  /// does: whatever else Back would end (picking) waits for the next one.
  static bool takesBack(BuildContext context) => read(context)?.shown != null;

  @override
  bool updateShouldNotify(ArrPaneScope old) =>
      shown != old.shown || (open == null) != (old.open == null);
}

/// Around a title's page while it's shown in the pane, so the page can offer
/// to close the pane, or to open itself full size, where it would have a
/// back button.
class ArrPaneHost extends InheritedWidget {
  final VoidCallback close;
  final VoidCallback openPage;

  const ArrPaneHost({
    super.key,
    required this.close,
    required this.openPage,
    required super.child,
  });

  static ArrPaneHost? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ArrPaneHost>();

  @override
  bool updateShouldNotify(ArrPaneHost old) => false;
}
