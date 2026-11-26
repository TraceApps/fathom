import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../routing/nav_destinations.dart';
import '../state/preferences.dart';
import '../widgets/page_width.dart';
import '../widgets/reorder.dart';

/// Reorder the sidebar / bottom-bar destinations and hide the ones you don't
/// use. Mirrors [HomeLayoutScreen]; saved to preferences and applied by the
/// shell. Only destinations available right now are listed (so you can't hide
/// something that isn't there); Home is fixed (always shown).
class NavigationLayoutScreen extends ConsumerWidget {
  const NavigationLayoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = ref.read(preferencesProvider.notifier);
    final p = ref.watch(preferencesProvider).asData?.value ?? const Prefs();

    // The available destinations in the user's current order (so the list here
    // matches the sidebar). Hidden ones still appear (with their switch off) so
    // they can be brought back.
    final available = availableNavDestinations(ref, l);
    final ordered = sortNavDestinations(available, p.navOrder);
    final hidden = p.navHidden.toSet();

    return Scaffold(
      appBar: AppBar(title: Text(l.navLayoutTitle)),
      body: Column(
        children: [
          PageHeader(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(l.navLayoutSubtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          ),
          Expanded(
            child: PageWidth(builder: (_, inset) => ReorderableListView(
              padding: pageInsets(inset, const EdgeInsets.symmetric(vertical: 8)),
              // We draw our own single handle on the LEFT; without this the list
              // also adds default handles on the right (two handles per row).
              buildDefaultDragHandles: false,
              // ignore: deprecated_member_use
              onReorder: (oldIndex, newIndex) {
                final routes = ordered.map((d) => d.route).toList();
                if (newIndex > oldIndex) newIndex -= 1;
                routes.insert(newIndex, routes.removeAt(oldIndex));
                c.edit((x) => x.copyWith(navOrder: routes));
              },
              children: [
                for (final (i, d) in ordered.indexed)
                  // Drag from anywhere on the row (press-drag desktop / long-press
                  // touch); the dots are just a hint.
                  dragAnywhere(
                    key: ValueKey(d.route),
                    index: i,
                    child: ListTile(
                      leading: Icon(Icons.drag_indicator,
                          color: dragGripColor(context)),
                      title: Row(
                        children: [
                          navDestIcon(
                            d,
                            color: IconTheme.of(context).color ??
                                Theme.of(context).colorScheme.onSurface,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(d.label)),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TvMoveButtons(
                            index: i,
                            count: ordered.length,
                            onMove: (from, to) {
                              final routes =
                                  ordered.map((d) => d.route).toList();
                              routes.insert(to, routes.removeAt(from));
                              c.edit((x) => x.copyWith(navOrder: routes));
                            },
                          ),
                          Switch(
                        // Home can't be hidden (nav must always have a home).
                        value: d.fixed || !hidden.contains(d.route),
                        onChanged: d.fixed
                            ? null
                            : (v) {
                                final next = {...hidden};
                                if (v) {
                                  next.remove(d.route);
                                } else {
                                  next.add(d.route);
                                }
                                c.edit((x) =>
                                    x.copyWith(navHidden: next.toList()));
                              },
                      ),
                        ],
                      ),
                    ),
                  ),
              ],
            )),
          ),
        ],
      ),
    );
  }
}
