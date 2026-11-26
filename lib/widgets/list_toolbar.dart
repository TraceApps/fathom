import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import 'tv_focus.dart';

/// Something a library's toolbar offers beside Filter and Sort (Select, List
/// View, Collections): a button on a wide window, a line of the More menu on
/// a phone.
class ListTool {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const ListTool(this.icon, this.label, this.onTap);
}

/// The Filter icon every library uses: plain with nothing filtered, filled
/// and counted with [active] filters on.
class ListFilterIcon extends StatelessWidget {
  final int active;
  const ListFilterIcon({super.key, required this.active});

  @override
  Widget build(BuildContext context) => Badge(
    isLabelVisible: active > 0,
    label: Text('$active'),
    child: Icon(
      active > 0 ? Icons.filter_alt_rounded : Icons.filter_list_rounded,
    ),
  );
}

enum _Order { ascending, descending }

/// The Sort menu every library uses: what to sort by, then which way.
/// Picking another order starts it the way that order usually reads
/// ([startsDescending]); Ascending and Descending turn it round.
class SortMenu<T extends Object> extends StatelessWidget {
  final T value;
  final Map<T, String> options;
  final bool descending;
  final void Function(T value, bool descending) onChanged;

  /// Whether an order starts from its top: newest, largest, best rated.
  final bool Function(T value) startsDescending;

  const SortMenu({
    super.key,
    required this.value,
    required this.options,
    required this.descending,
    required this.onChanged,
    required this.startsDescending,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopupMenuButton<Object>(
      tooltip: l.arrSort,
      icon: const Icon(Icons.sort_rounded),
      onSelected: (v) {
        if (v is _Order) {
          final desc = v == _Order.descending;
          if (desc != descending) onChanged(value, desc);
        } else if (v is T && v != value) {
          onChanged(v, startsDescending(v));
        }
      },
      itemBuilder: (_) => [
        for (final e in options.entries)
          CheckedPopupMenuItem<Object>(
            value: e.key,
            checked: e.key == value,
            child: Text(e.value),
          ),
        const PopupMenuDivider(),
        CheckedPopupMenuItem<Object>(
          value: _Order.ascending,
          checked: !descending,
          child: Text(l.browseAscending),
        ),
        CheckedPopupMenuItem<Object>(
          value: _Order.descending,
          checked: descending,
          child: Text(l.browseDescending),
        ),
      ],
    );
  }
}

/// The row above a library's grid: a search box, the Filter and Sort menus,
/// and whatever else the library offers.
///
/// A window wide enough takes everything on one line, each tool as its own
/// button. A phone gets the search box and the menus on one line, with the
/// tools under More; with a [switcher] the box moves to a line of its own.
class ListToolbar extends StatelessWidget {
  /// A switch between libraries (Movies and Shows), before the search box.
  final Widget? switcher;
  final Widget search;

  /// Filter and Sort: always shown.
  final List<Widget> menus;
  final List<ListTool> tools;

  const ListToolbar({
    super.key,
    required this.search,
    this.switcher,
    this.menus = const [],
    this.tools = const [],
  });

  /// From this width up the tools are buttons of their own.
  static const wideFrom = 720.0;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
    // A TV opens the library on its first poster.
    child: TvChrome(
      child: LayoutBuilder(builder: (context, c) => _bar(context, c.maxWidth)),
    ),
  );

  Widget _bar(BuildContext context, double width) {
    final l = AppLocalizations.of(context);
    if (width >= wideFrom) {
      return Row(
        children: [
          if (switcher != null) ...[switcher!, const SizedBox(width: 12)],
          // The box stops growing: a search field across a whole desktop
          // window reads as a banner, not a field.
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: search,
              ),
            ),
          ),
          ...menus,
          for (final t in tools)
            IconButton(
              tooltip: t.label,
              icon: Icon(t.icon),
              onPressed: t.onTap,
            ),
        ],
      );
    }
    final more = tools.isEmpty
        ? null
        : PopupMenuButton<ListTool>(
            tooltip: l.arrMore,
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (t) => t.onTap(),
            itemBuilder: (_) => [
              for (final t in tools)
                PopupMenuItem(
                  value: t,
                  child: Row(
                    children: [
                      Icon(t.icon, size: 20),
                      const SizedBox(width: 14),
                      Flexible(child: Text(t.label)),
                    ],
                  ),
                ),
            ],
          );
    if (switcher == null) {
      return Row(children: [Expanded(child: search), ...menus, ?more]);
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: switcher!,
              ),
            ),
            ...menus,
            ?more,
          ],
        ),
        const SizedBox(height: 8),
        // The row's own right edge is 8 in, for the icon buttons; the box
        // lines up with the grid instead.
        Padding(padding: const EdgeInsets.only(right: 8), child: search),
      ],
    );
  }
}
