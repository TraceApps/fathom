import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/tv_mode.dart';

/// Makes a whole reorderable row draggable from ANYWHERE on it, the right way
/// for each input:
///  - Desktop (mouse): an immediate press-drag. A quick click still passes
///    through as a tap, and the wheel still scrolls, so nothing is lost.
///  - Touch: a long-press, so a normal swipe still scrolls the list and a tap
///    still activates the row.
///
/// [ReorderableDelayedDragStartListener] (long-press) does not fire for a mouse,
/// which is why a desktop user could previously only drag from the handle.
Widget dragAnywhere({
  Key? key,
  required int index,
  required Widget child,
}) {
  final isTouch = Platform.isAndroid || Platform.isIOS;
  return isTouch
      ? ReorderableDelayedDragStartListener(
          key: key, index: index, child: child)
      : ReorderableDragStartListener(key: key, index: index, child: child);
}

/// The subdued drag-grip colour: visible but greyed back so it reads as a hint,
/// not a control.
Color dragGripColor(BuildContext context) =>
    Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.45);

/// Move Up and Move Down for a row of a reorderable list, on a TV: a remote
/// can't drag. Nothing anywhere else, where the row is dragged.
class TvMoveButtons extends StatelessWidget {
  final int index;
  final int count;

  /// Moves the row at [from] to stand at [to].
  final void Function(int from, int to) onMove;

  const TvMoveButtons({
    super.key,
    required this.index,
    required this.count,
    required this.onMove,
  });

  @override
  Widget build(BuildContext context) {
    if (!isTvDevice) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: l.browseMoveUp,
          icon: const Icon(Icons.arrow_upward_rounded),
          onPressed: index > 0 ? () => onMove(index, index - 1) : null,
        ),
        IconButton(
          tooltip: l.browseMoveDown,
          icon: const Icon(Icons.arrow_downward_rounded),
          onPressed: index < count - 1 ? () => onMove(index, index + 1) : null,
        ),
      ],
    );
  }
}
