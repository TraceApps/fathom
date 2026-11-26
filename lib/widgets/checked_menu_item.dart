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

/// An icon and a name, for a line of a menu: a ListTile that leaves the
/// focus to the menu line around it. A bare ListTile in a menu line has the
/// same fault as above; the remote lands on it and Select does nothing.
class MenuTile extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final bool? dense;
  final EdgeInsetsGeometry? contentPadding;

  const MenuTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.dense,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    child: ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      dense: dense,
      contentPadding: contentPadding,
    ),
  );
}
