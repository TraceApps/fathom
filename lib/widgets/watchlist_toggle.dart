import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/base_item.dart';
import '../state/watchlist.dart';
import 'app_snack.dart';

/// The Watchlist entry [item] stands for, if it's on the list: the item
/// itself (also an episode or song put on before the Watchlist took only
/// movies and shows, so it can still come off), or an episode's show.
String? watchlistEntryOn(List<BaseItemDto> watchlist, BaseItemDto item) {
  if (watchlist.any((e) => e.id == item.id)) return item.id;
  final id = WatchlistController.entryIdFor(item);
  if (id != null && watchlist.any((e) => e.id == id)) return id;
  return null;
}

/// Whether [item] gets a Watchlist toggle: anything the Watchlist takes, and
/// anything already on it.
bool hasWatchlistToggle(List<BaseItemDto> watchlist, BaseItemDto item) =>
    WatchlistController.entryIdFor(item) != null ||
    watchlistEntryOn(watchlist, item) != null;

/// Whether [item] is on the Watchlist (an episode through its show).
bool inWatchlistFor(List<BaseItemDto> watchlist, BaseItemDto item) =>
    watchlistEntryOn(watchlist, item) != null;

/// The Watchlist toggle's name for [item]: an episode says it's the show
/// that goes on or comes off, since that's what the Watchlist keeps.
String watchlistToggleLabel(
  AppLocalizations l,
  List<BaseItemDto> watchlist,
  BaseItemDto item,
) {
  final on = watchlistEntryOn(watchlist, item);
  final viaShow = item.isEpisode && on != item.id;
  if (on != null) {
    return viaShow
        ? l.detailRemoveShowFromWatchlist
        : l.detailRemoveFromWatchlist;
  }
  return item.isEpisode ? l.detailAddShowToWatchlist : l.detailAddToWatchlist;
}

/// Puts [item] on the Watchlist or takes it off, and says which it did.
/// The same everywhere the toggle appears: a title page, a card's menu, the
/// Movie Night Wheel's winner.
Future<void> toggleWatchlist(
  ScaffoldMessengerState messenger,
  AppLocalizations l,
  WatchlistController watchlist,
  List<BaseItemDto> current,
  BaseItemDto item,
) async {
  // What's on the list now: [current] is what the caller had when it drew
  // the button, which can be nothing yet (a menu opened before the list had
  // loaded), and going by that added a second entry for a title already on.
  try {
    current = await watchlist.loaded();
  } catch (_) {
    // The error shows when the change below is tried.
  }
  final on = watchlistEntryOn(current, item);
  final show = item.isEpisode && on != item.id ? item.seriesName : null;
  try {
    if (on != null) {
      await watchlist.remove(on);
      showSnackOn(
        messenger,
        show != null ? l.watchlistShowRemoved(show) : l.watchlistRemoved,
        kind: SnackKind.success,
      );
    } else {
      if (WatchlistController.entryIdFor(item) == null) return;
      await watchlist.add(item);
      showSnackOn(
        messenger,
        show != null ? l.watchlistShowAdded(show) : l.watchlistAdded,
        kind: SnackKind.success,
      );
    }
  } catch (e) {
    showErrorOn(messenger, e);
  }
}
