import 'dart:io';

import 'package:flutter/material.dart';

import '../services/tv_mode.dart';
import 'tv_focus.dart';

/// One action in a shared context menu, the same list a card's overflow
/// button, a right-click, and a long-press all resolve to, so they can never
/// individually drift out of sync with each other.
class ContextMenuAction {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const ContextMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
}

/// True where a mouse is the primary input: where right-click is a real,
/// expected gesture and a small dropdown at the cursor feels native (every
/// desktop OS already behaves this way). Touch (phone and tablet, the input
/// is a finger either way, screen size doesn't change that) and TV (a
/// remote has no pointer, and no long-press equivalent, a D-pad-focusable
/// trigger is the only way in) both get the bottom sheet instead, for the
/// bigger targets that input actually needs.
bool get _mouseDriven => !isTvDevice && !Platform.isAndroid && !Platform.isIOS;

/// Shows [actions] the platform-appropriate way (a small anchored dropdown
/// on a mouse-driven desktop, a bottom sheet on touch/TV) and runs whichever
/// one was picked. [at] anchors the dropdown to where the click/tap
/// happened; ignored on the sheet path, which doesn't need it. [title], when
/// given, heads the sheet with the item's name, so opening it from a dense
/// grid still says what it's acting on; the dropdown skips it, it's already
/// anchored right on the item. Ignored on the dropdown either way.
/// [subtitle] goes under it: what a pointer would read in the item's
/// tooltip, which a finger never sees.
Future<void> showContextMenu(
  BuildContext context, {
  required Offset at,
  required List<ContextMenuAction> actions,
  String? title,
  String? subtitle,
}) async {
  if (actions.isEmpty) return;
  final chosen = _mouseDriven
      ? await _showDropdown(context, at: at, actions: actions)
      : await _showSheet(
          context,
          actions: actions,
          title: title,
          subtitle: subtitle,
        );
  chosen?.call();
}

Future<VoidCallback?> _showDropdown(
  BuildContext context, {
  required Offset at,
  required List<ContextMenuAction> actions,
}) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return Future.value(null);
  // [at] is a real global (screen) position, from the tap/click event itself,
  // while showMenu places the menu in the overlay's own coordinates. Those only
  // match when the overlay sits flush with the window's top-left at 100% size;
  // window chrome, nested routes and the Interface Size setting (which scales
  // everything) all break that. globalToLocal accounts for every one of them.
  final local = overlay.globalToLocal(at);
  return showMenu<VoidCallback>(
    context: context,
    position: RelativeRect.fromRect(
      local & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      for (final a in actions)
        PopupMenuItem<VoidCallback>(
          value: a.onTap,
          child: Row(
            children: [
              Icon(a.icon, size: 20, color: a.color),
              const SizedBox(width: 12),
              // Flexible: the dropdown is capped by the space left between the
              // click and the screen edge, so a long label (or a longer
              // translation of a short one) overflowed the row.
              Flexible(
                child: Text(
                  a.label,
                  style: TextStyle(color: a.color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

Future<VoidCallback?> _showSheet(
  BuildContext context, {
  required List<ContextMenuAction> actions,
  String? title,
  String? subtitle,
}) {
  return showModalBottomSheet<VoidCallback>(
    context: context,
    useRootNavigator: true,
    showDragHandle: !isTvDevice,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isTvDevice) const SizedBox(height: 8),
            if (title != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                child: Column(
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(ctx).textTheme.titleMedium),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
            for (var i = 0; i < actions.length; i++)
              ContextMenuRow(
                action: actions[i],
                autofocus: i == 0,
                onTap: () => Navigator.pop(ctx, actions[i].onTap),
              ),
          ],
        ),
      ),
    ),
  );
}

/// One row of the bottom-sheet form: a plain [ListTile] off TV, wrapped in
/// [TvFocusable] on it so the D-pad can actually reach it, the only way in
/// on a remote, since there's no long-press or right-click there at all.
class ContextMenuRow extends StatelessWidget {
  final ContextMenuAction action;
  final bool autofocus;
  final VoidCallback onTap;
  const ContextMenuRow({
    super.key,
    required this.action,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      leading: Icon(action.icon, color: action.color),
      title: Text(action.label,
          style: action.color != null ? TextStyle(color: action.color) : null),
      onTap: isTvDevice ? null : onTap,
    );
    if (!isTvDevice) return tile;
    return TvFocusable(
      onTap: onTap,
      autofocus: autofocus,
      scale: 1.0,
      borderRadius: BorderRadius.zero,
      child: tile,
    );
  }
}

/// The middle of what [context] draws, on the screen: where a menu opens
/// when the thing itself is pressed rather than right-clicked.
Offset contextMenuAnchor(BuildContext context) {
  final box = context.findRenderObject();
  return box is RenderBox && box.hasSize
      ? box.localToGlobal(box.size.center(Offset.zero))
      : Offset.zero;
}
