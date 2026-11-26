import 'package:flutter/material.dart';

/// A line of a menu that's one of several choices, ticked when it's the one
/// in use.
///
/// Flutter's own checked menu item (the Material one) can't be used: it holds a ListTile,
/// which takes the focus for itself wherever a remote moves it (directional
/// navigation), and pressing Select on that does nothing. Every checked menu
/// was dead on a TV. This one is a plain menu line with the tick drawn in.
class CheckedMenuItem<T> extends PopupMenuItem<T> {
  CheckedMenuItem({
    super.key,
    super.value,
    super.enabled,
    required bool checked,
    required Widget child,
  }) : super(
         child: Row(
           children: [
             SizedBox(
               width: 40,
               child: checked
                   ? const Align(
                       alignment: AlignmentDirectional.centerStart,
                       child: Icon(Icons.check_rounded, size: 20),
                     )
                   : null,
             ),
             Flexible(child: child),
           ],
         ),
       );
}
