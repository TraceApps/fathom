import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../state/arr_providers.dart';
import '../state/preferences.dart';
import '../widgets/page_width.dart';
import '../widgets/reorder.dart';

/// Reorder and toggle the Home screen rows (Continue Watching / Recently Added
/// / My Media), Moonfin-style. Saved to preferences. Sonarr's and Radarr's
/// rows are listed only where Home can show them.
class HomeLayoutScreen extends ConsumerWidget {
  const HomeLayoutScreen({super.key});

  static Map<String, String> _titles(AppLocalizations l) => {
        'continueWatching': l.homeLayoutContinueWatching,
        'nextUp': l.homeLayoutNextUp,
        'recentlyAdded': l.homeLayoutRecentlyAdded,
        'myMedia': l.homeLayoutMyMedia,
        'arrDownloading': l.arrHomeDownloading,
        'arrComingUp': l.arrHomeComingUp,
      };

  bool _visible(Prefs p, String id) => switch (id) {
        'continueWatching' => p.showContinueWatching,
        'nextUp' => p.showNextUp,
        'recentlyAdded' => p.showRecentlyAdded,
        'myMedia' => p.showMyMedia,
        'arrDownloading' => p.showArrDownloading,
        'arrComingUp' => p.showArrComingUp,
        _ => true,
      };

  Prefs _toggle(Prefs p, String id, bool v) => switch (id) {
        'continueWatching' => p.copyWith(showContinueWatching: v),
        'nextUp' => p.copyWith(showNextUp: v),
        'recentlyAdded' => p.copyWith(showRecentlyAdded: v),
        'myMedia' => p.copyWith(showMyMedia: v),
        'arrDownloading' => p.copyWith(showArrDownloading: v),
        'arrComingUp' => p.copyWith(showArrComingUp: v),
        _ => p,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(preferencesProvider).asData?.value ?? const Prefs();
    final c = ref.read(preferencesProvider.notifier);
    final l = AppLocalizations.of(context);
    final titles = _titles(l);
    final arrRows = ref.watch(arrConfiguredProvider);
    // Every row, in the order Home shows them, and the ones listed here.
    // Moving one of these keeps the rest (a row that isn't listed) in place.
    final all = homeRowsInOrder(p.homeRowOrder);
    final rows = [
      for (final id in all)
        if (arrRows || !id.startsWith('arr')) id,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l.homeLayoutTitle)),
      body: Column(
        children: [
          Expanded(
            child: PageWidth(builder: (_, inset) => ReorderableListView(
              padding: pageInsets(inset, const EdgeInsets.symmetric(vertical: 8)),
              // Single left-side grip (below); no default right-side handles.
              buildDefaultDragHandles: false,
              // ignore: deprecated_member_use
              onReorder: (oldIndex, newIndex) {
                final list = [...rows];
                if (newIndex > oldIndex) newIndex -= 1;
                list.insert(newIndex, list.removeAt(oldIndex));
                c.edit((x) => x.copyWith(
                    homeRowOrder: homeRowsMoved(all, shown: list)));
              },
              children: [
                for (final (i, id) in rows.indexed)
                  // Drag from anywhere on the row (press-drag desktop / long-press
                  // touch); the dots are just a hint.
                  dragAnywhere(
                    key: ValueKey(id),
                    index: i,
                    child: ListTile(
                      leading: Icon(Icons.drag_indicator,
                          color: dragGripColor(context)),
                      title: Text(titles[id] ?? id),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TvMoveButtons(
                            index: i,
                            count: rows.length,
                            onMove: (from, to) {
                              final list = [...rows];
                              list.insert(to, list.removeAt(from));
                              c.edit((x) => x.copyWith(
                                  homeRowOrder:
                                      homeRowsMoved(all, shown: list)));
                            },
                          ),
                          Switch(
                            value: _visible(p, id),
                            onChanged: (v) => c.edit((x) => _toggle(x, id, v)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            )),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.video_library_outlined),
            title: Text(l.homeLayoutLatestByLibrary),
            subtitle: Text(l.homeLayoutLatestByLibrarySubtitle),
            value: p.showLibraryLatest,
            onChanged: (v) =>
                c.edit((x) => x.copyWith(showLibraryLatest: v)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.theater_comedy_outlined),
            title: Text(l.homeLayoutGenreRows),
            subtitle: Text(l.homeLayoutGenreRowsSubtitle),
            value: p.showGenreRows,
            onChanged: (v) => c.edit((x) => x.copyWith(showGenreRows: v)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
