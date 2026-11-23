import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/arr_client.dart';
import '../api/bazarr_client.dart';
import '../api/jellyfin_client.dart';
import '../models/arr.dart';
import 'download_providers.dart';
import 'preferences.dart';
import 'providers.dart';
import 'session_controller.dart';

/// The Sonarr server, when one is connected (an address and an API key).
final sonarrClientProvider = Provider<SonarrClient?>((ref) {
  final c = ref.watch(
    preferencesProvider.select((p) {
      final v = p.asData?.value;
      return (v?.sonarrUrl ?? '', v?.sonarrApiKey ?? '');
    }),
  );
  if (c.$1.isEmpty || c.$2.isEmpty) return null;
  return SonarrClient(c.$1, c.$2);
});

/// The Radarr server, when one is connected.
final radarrClientProvider = Provider<RadarrClient?>((ref) {
  final c = ref.watch(
    preferencesProvider.select((p) {
      final v = p.asData?.value;
      return (v?.radarrUrl ?? '', v?.radarrApiKey ?? '');
    }),
  );
  if (c.$1.isEmpty || c.$2.isEmpty) return null;
  return RadarrClient(c.$1, c.$2);
});

/// The Lidarr server, when one is connected.
final lidarrClientProvider = Provider<LidarrClient?>((ref) {
  final c = ref.watch(
    preferencesProvider.select((p) {
      final v = p.asData?.value;
      return (v?.lidarrUrl ?? '', v?.lidarrApiKey ?? '');
    }),
  );
  if (c.$1.isEmpty || c.$2.isEmpty) return null;
  return LidarrClient(c.$1, c.$2);
});

/// The Prowlarr server, when one is connected.
final prowlarrClientProvider = Provider<ProwlarrClient?>((ref) {
  final c = ref.watch(
    preferencesProvider.select((p) {
      final v = p.asData?.value;
      return (v?.prowlarrUrl ?? '', v?.prowlarrApiKey ?? '');
    }),
  );
  if (c.$1.isEmpty || c.$2.isEmpty) return null;
  return ProwlarrClient(c.$1, c.$2);
});

/// The Bazarr server, when one is connected.
final bazarrClientProvider = Provider<BazarrClient?>((ref) {
  final c = ref.watch(
    preferencesProvider.select((p) {
      final v = p.asData?.value;
      return (v?.bazarrUrl ?? '', v?.bazarrApiKey ?? '');
    }),
  );
  if (c.$1.isEmpty || c.$2.isEmpty) return null;
  return BazarrClient(c.$1, c.$2);
});

/// What's missing subtitles: the first [length] episodes and movies, and
/// how many in all.
final bazarrWantedProvider = FutureProvider.autoDispose
    .family<({List<BazarrWanted> items, int total}), int>((ref, length) async {
      final c = ref.watch(bazarrClientProvider);
      if (c == null) return (items: const <BazarrWanted>[], total: 0);
      return c.wanted(length: length);
    });

/// What Bazarr did lately.
final bazarrHistoryProvider = FutureProvider.autoDispose
    .family<({List<BazarrHistoryItem> items, int total}), int>((
      ref,
      length,
    ) async {
      final c = ref.watch(bazarrClientProvider);
      if (c == null) return (items: const <BazarrHistoryItem>[], total: 0);
      return c.history(length: length);
    });

/// Bazarr's subtitle providers and how each is doing.
final bazarrProvidersProvider =
    FutureProvider.autoDispose<List<BazarrProvider>>((ref) async {
      final c = ref.watch(bazarrClientProvider);
      if (c == null) return const [];
      return c.providers();
    });

/// An indexer with what Prowlarr says of its health: held back after
/// failures, until when.
typedef ProwlarrIndexerRow = ({
  ProwlarrIndexer indexer,
  ProwlarrIndexerStatus? status,
});

/// Prowlarr's indexers by priority then name, as its own page lists them,
/// each with its status.
final prowlarrIndexersProvider =
    FutureProvider.autoDispose<List<ProwlarrIndexerRow>>((ref) async {
      final c = ref.watch(prowlarrClientProvider);
      if (c == null) return const [];
      final r = await Future.wait([c.indexers(), c.statuses()]);
      final statuses = {
        for (final s in r[1] as List<ProwlarrIndexerStatus>) s.indexerId: s,
      };
      final list = [...r[0] as List<ProwlarrIndexer>]
        ..sort((a, b) {
          final p = a.priority.compareTo(b.priority);
          return p != 0
              ? p
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      return [
        for (final i in list) (indexer: i, status: statuses[i.id]),
      ];
    });

/// Prowlarr's counts per indexer, the busiest first.
final prowlarrStatsProvider =
    FutureProvider.autoDispose<List<ProwlarrIndexerStats>>((ref) async {
      final c = ref.watch(prowlarrClientProvider);
      if (c == null) return const [];
      final list = await c.stats();
      return arrStableSorted(list, (a, b) => b.queries.compareTo(a.queries));
    });

/// What Prowlarr did lately, the newest [limit].
final prowlarrHistoryProvider = FutureProvider.autoDispose
    .family<ArrPage<ProwlarrHistoryItem>, int>((ref, limit) async {
      final c = ref.watch(prowlarrClientProvider);
      if (c == null) return const ArrPage([], 0);
      return c.history(pageSize: limit);
    });

/// [items] sorted by [compare], those alike keeping the order they came in.
List<T> arrStableSorted<T>(List<T> items, int Function(T, T) compare) {
  final sorted = [...items];
  mergeSort<T>(sorted, compare: compare);
  return sorted;
}

/// Whether the Arr section shows: Sonarr, Radarr, Lidarr, Prowlarr or a
/// download client connected.
final arrConfiguredProvider = Provider<bool>(
  (ref) =>
      ref.watch(sonarrClientProvider) != null ||
      ref.watch(radarrClientProvider) != null ||
      ref.watch(lidarrClientProvider) != null ||
      ref.watch(prowlarrClientProvider) != null ||
      ref.watch(bazarrClientProvider) != null ||
      ref.watch(downloadClientsProvider).isNotEmpty,
);

/// The libraries the Library tab can show, in its switch's order: Movies,
/// Shows, Music, each where its app is connected.
final arrLibraryKindsProvider = Provider<List<ArrKind>>(
  (ref) => [
    if (ref.watch(radarrClientProvider) != null) ArrKind.radarr,
    if (ref.watch(sonarrClientProvider) != null) ArrKind.sonarr,
    if (ref.watch(lidarrClientProvider) != null) ArrKind.lidarr,
  ],
);

/// The library on show: the one picked, while its app is connected;
/// otherwise the first that is. Null with none connected.
ArrKind? arrShownLibrary(List<ArrKind> kinds, ArrKind picked) =>
    kinds.contains(picked) ? picked : kinds.firstOrNull;

/// Results gathered from both apps. One app being unreachable doesn't hide
/// the other's: its error is kept beside what did arrive.
class ArrMerged<T> {
  final List<T> items;
  final Map<ArrKind, String> errors;

  /// For paged lists: how many there are in all, across both apps.
  final int total;
  const ArrMerged(this.items, this.errors, {this.total = 0});

  /// Whether a bigger page would show more.
  bool get hasMore => items.length < total;
}

/// The connected apps, always in one order: Sonarr, Radarr, Lidarr.
List<ArrClient> _arrClients(Ref ref) => [
  ?ref.watch(sonarrClientProvider),
  ?ref.watch(radarrClientProvider),
  ?ref.watch(lidarrClientProvider),
];

Future<ArrMerged<T>> _both<T>(
  List<ArrClient> clients,
  Future<List<T>> Function(ArrClient c) load,
) async {
  final errors = <ArrKind, String>{};
  // Sonarr's, then Radarr's, then Lidarr's, whichever answers first: what's
  // alike in a list sorted after keeps its place from one asking to the next.
  final lists = await Future.wait([
    for (final c in clients)
      load(c).catchError((Object e) {
        errors[c.kind] = e.toString();
        return <T>[];
      }),
  ]);
  return ArrMerged([for (final l in lists) ...l], errors);
}

/// What each app last said, for a Home row that mustn't blink when one
/// answer goes missing. An app that didn't answer keeps what it had for
/// [patience] answers in a row; after that it has nothing to show.
class ArrLastKnown<T> {
  final ArrKind Function(T) kindOf;
  final int patience;

  /// The order the answers come in, to put what's kept back in its place.
  final Comparator<T>? order;
  ArrLastKnown({required this.kindOf, required this.patience, this.order});

  final _last = <ArrKind, List<T>>{};
  final _missed = <ArrKind, int>{};
  ArrMerged<T>? _seen;
  List<T> _shown = const [];

  /// What [of] gave last: it stands while the next answer is on its way.
  List<T> get shown => _shown;

  /// [answer], with what's kept for an app that gave none. The same answer
  /// coming by again (a build for another reason) counts once.
  List<T> of(ArrMerged<T> answer) {
    if (identical(answer, _seen)) return _shown;
    _seen = answer;
    final kept = <T>[];
    for (final kind in ArrKind.values) {
      if (!answer.errors.containsKey(kind)) {
        _missed.remove(kind);
        _last[kind] = [
          for (final i in answer.items)
            if (kindOf(i) == kind) i,
        ];
        continue;
      }
      final missed = _missed[kind] = (_missed[kind] ?? 0) + 1;
      if (missed > patience) _last.remove(kind);
      kept.addAll(_last[kind] ?? const []);
    }
    if (kept.isEmpty) return _shown = answer.items;
    final all = [...answer.items, ...kept];
    if (order != null) all.sort(order);
    return _shown = all;
  }
}

/// A stretch of days on the Calendar: from [start], up to but not [end].
typedef ArrDays = ({DateTime start, DateTime end});

/// The calendar window: from the start of yesterday, four weeks ahead.
ArrDays arrCalendarWindow(DateTime now) {
  // By the calendar, not in hours: a day the clocks change isn't 24 long.
  return (
    start: DateTime(now.year, now.month, now.day - 1),
    end: DateTime(now.year, now.month, now.day + 29),
  );
}

/// The days a month's grid shows: whole weeks, from the week its first day
/// falls in to the week its last does. [firstWeekday] is the day a week
/// starts on where the app is used, 0 for Sunday.
({DateTime start, int weeks}) arrMonthGrid(DateTime month, int firstWeekday) {
  final lead = (DateTime(month.year, month.month).weekday - firstWeekday) % 7;
  final days = DateTime(month.year, month.month + 1, 0).day;
  return (
    // By the calendar, not by adding hours: a day isn't 24 of them when the
    // clocks change.
    start: DateTime(month.year, month.month, 1 - lead),
    weeks: ((lead + days) / 7).ceil(),
  );
}

/// How the Calendar is laid out: the days one under another, or a month's
/// grid.
enum ArrCalendarView { agenda, month }

/// The layout picked for the Calendar; null until one is, and the Calendar
/// then shows the month where there's room for it. Kept for the session.
class ArrCalendarViewChoice extends Notifier<ArrCalendarView?> {
  @override
  ArrCalendarView? build() => null;
  void set(ArrCalendarView v) => state = v;
}

final arrCalendarViewProvider =
    NotifierProvider<ArrCalendarViewChoice, ArrCalendarView?>(
      ArrCalendarViewChoice.new,
    );

/// The month the Calendar's grid is turned to, by its first day; null for
/// the month it is now, which then moves on with the date.
class ArrCalendarMonth extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void set(DateTime? month) {
    final now = DateTime.now();
    state = month == null || (month.year == now.year && month.month == now.month)
        ? null
        : DateTime(month.year, month.month);
  }
}

final arrCalendarMonthProvider =
    NotifierProvider<ArrCalendarMonth, DateTime?>(ArrCalendarMonth.new);

/// Whether the Calendar shows unmonitored titles too (Show Unmonitored).
class ArrCalendarUnmonitored extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final arrCalendarUnmonitoredProvider =
    NotifierProvider<ArrCalendarUnmonitored, bool>(ArrCalendarUnmonitored.new);

/// Which library the Manage section's Library tab shows: Radarr's movies or
/// Sonarr's shows. Kept for the session, so coming back lands where you were.
class ArrLibraryKind extends Notifier<ArrKind> {
  @override
  ArrKind build() => ArrKind.radarr;
  void set(ArrKind v) => state = v;
}

final arrLibraryKindProvider = NotifierProvider<ArrLibraryKind, ArrKind>(
  ArrLibraryKind.new,
);

/// The lists under the Activity tab, as under the apps' own Activity.
/// Forgotten on leaving the tab, so its count always opens the queue.
enum ArrActivityView { queue, history, blocklist, requests }

class ArrActivityViewChoice extends Notifier<ArrActivityView> {
  @override
  ArrActivityView build() => ArrActivityView.queue;
  void set(ArrActivityView v) => state = v;
}

final arrActivityViewProvider =
    NotifierProvider.autoDispose<ArrActivityViewChoice, ArrActivityView>(
      ArrActivityViewChoice.new,
    );

/// What's released over a stretch of days: the agenda's four weeks, or the
/// weeks of a month's grid. Invalidated as a whole, every stretch on show
/// reloads.
final arrCalendarProvider = FutureProvider.autoDispose
    .family<ArrMerged<ArrCalendarEntry>, ArrDays>((ref, w) async {
      final unmonitored = ref.watch(arrCalendarUnmonitoredProvider);
      final merged = await _both<ArrCalendarEntry>(
        _arrClients(ref),
        (c) => c.calendar(w.start, w.end, unmonitored: unmonitored),
      );
      merged.items.sort(arrCalendarOrder);
      return merged;
    });

final arrQueueProvider = FutureProvider.autoDispose<ArrMerged<ArrQueueItem>>((
  ref,
) async {
  final merged = await _both<ArrQueueItem>(
    _arrClients(ref),
    (c) => c.queue(),
  );
  merged.items.sort(arrQueueOrder);
  return merged;
});

/// The Calendar's order: the soonest first, and releases at the same time
/// in one order every time (Sonarr's, by show and episode, then Radarr's).
int arrCalendarOrder(ArrCalendarEntry a, ArrCalendarEntry b) {
  final when = a.date.compareTo(b.date);
  if (when != 0) return when;
  final kind = a.kind.index.compareTo(b.kind.index);
  if (kind != 0) return kind;
  final title = a.title.compareTo(b.title);
  if (title != 0) return title;
  return (a.episodeId ?? a.movieId ?? a.albumId ?? 0).compareTo(
    b.episodeId ?? b.movieId ?? b.albumId ?? 0,
  );
}

/// The queue's order: what's stuck first (the same ones a card says so of,
/// in its color), then the closest to finishing.
///
/// Downloads alike keep one order (Sonarr's first, then by id), however the
/// answers come in: a row mustn't swap places with each refresh.
int arrQueueOrder(ArrQueueItem a, ArrQueueItem b) {
  final stuck = a.state.needsHelp;
  if (stuck != b.state.needsHelp) return stuck ? -1 : 1;
  final along = b.progress.compareTo(a.progress);
  if (along != 0) return along;
  final kind = a.kind.index.compareTo(b.kind.index);
  return kind != 0 ? kind : a.id.compareTo(b.id);
}

/// A movie or a show on Home's Downloading Now row, with everything of it
/// that's in the queue.
class ArrHomeDownload {
  final ArrKind kind;
  final int titleId;
  final String title;
  final List<ArrImage> images;

  /// The queue's entries for the title, in the queue's order: one that needs
  /// a look first, then the closest to finishing.
  final List<ArrQueueItem> items;

  const ArrHomeDownload({
    required this.kind,
    required this.titleId,
    required this.title,
    required this.images,
    required this.items,
  });

  /// The entry that says how the title is doing.
  ArrQueueItem get lead => items.first;

  /// The downloads behind the entries. A season pack is one download, and
  /// the queue lists it once for each episode in it, each time at the whole
  /// pack's size: counted like that, three episodes would be three packs.
  List<ArrQueueItem> get downloads {
    final seen = <String>{};
    return [
      for (final i in items)
        if (i.downloadId == null || seen.add(i.downloadId!)) i,
    ];
  }

  /// How much of all of it has arrived, 0 to 1.
  double get progress {
    var size = 0.0, left = 0.0;
    for (final d in downloads) {
      size += d.size;
      left += d.sizeleft;
    }
    return size <= 0 ? 0 : ((size - left) / size).clamp(0, 1).toDouble();
  }

  /// When the last of what's downloading is due to finish. Null when nothing
  /// is, or the download client doesn't say.
  DateTime? get finishes {
    DateTime? last;
    for (final d in downloads) {
      final at = d.estimatedCompletion;
      if (d.status != 'downloading' || at == null) continue;
      if (last == null || at.isAfter(last)) last = at;
    }
    return last;
  }
}

/// The queue as Home shows it: one card for a movie or a show, however many
/// of its episodes are downloading. A download the app couldn't match to a
/// title is left to the Activity tab, which can fix it.
List<ArrHomeDownload> arrHomeDownloads(List<ArrQueueItem> queue) {
  final byTitle = <(ArrKind, int), List<ArrQueueItem>>{};
  for (final i in queue) {
    final id = i.titleId;
    if (id == null || i.mediaTitle == null) continue;
    (byTitle[(i.kind, id)] ??= []).add(i);
  }
  return [
    for (final e in byTitle.entries)
      ArrHomeDownload(
        kind: e.key.$1,
        titleId: e.key.$2,
        title: e.value.first.mediaTitle!,
        images: e.value.first.images,
        items: e.value,
      ),
  ];
}

/// A movie or a show on Home's Coming This Week row: the first of its
/// releases due, and for a show how many more episodes follow in the week.
typedef ArrHomeRelease = ({ArrCalendarEntry first, int more});

/// The days Home's Coming This Week row covers: today and the six after it.
ArrDays arrHomeWeek(DateTime now) => (
  // By the calendar, not in hours: a day the clocks change isn't 24 long.
  start: DateTime(now.year, now.month, now.day),
  end: DateTime(now.year, now.month, now.day + 7),
);

/// What's due in [week] that the apps will go and get: monitored, and not
/// here yet. One card for a title, at its first release in the week, the
/// soonest first. A movie's later releases in the same week (cinemas, then
/// digital) aren't counted as more of it.
List<ArrHomeRelease> arrHomeComingUp(
  List<ArrCalendarEntry> entries,
  ArrDays week,
) {
  final due = [
    for (final e in entries)
      if (e.monitored &&
          !e.hasFile &&
          e.titleId != null &&
          !e.date.isBefore(week.start) &&
          e.date.isBefore(week.end))
        e,
  ]..sort(arrCalendarOrder);
  final first = <(ArrKind, int), ArrCalendarEntry>{};
  final count = <(ArrKind, int), int>{};
  for (final e in due) {
    final key = (e.kind, e.titleId!);
    first.putIfAbsent(key, () => e);
    count[key] = (count[key] ?? 0) + 1;
  }
  return [
    for (final e in first.entries)
      (
        first: e.value,
        // A show's later episodes, an artist's later albums; a movie's later
        // releases are the same movie.
        more: e.key.$1 == ArrKind.radarr ? 0 : count[e.key]! - 1,
      ),
  ];
}

/// Whether a download in [before] is gone from [after]: imported, most
/// often, so what was due may be on disk now. An app in [unanswered] gave
/// no queue this time, which says nothing about its downloads.
bool arrQueueItemLeft(
  List<ArrQueueItem> before,
  List<ArrQueueItem> after, {
  Set<ArrKind> unanswered = const {},
}) {
  final still = {for (final q in after) (q.kind, q.id)};
  return before.any(
    (q) => !unanswered.contains(q.kind) && !still.contains((q.kind, q.id)),
  );
}

/// What Home's Coming This Week row is made from: the week's releases, and
/// which app didn't answer. Asked for apart from the Calendar tab, whose
/// answer changes with its Show Unmonitored switch.
final arrHomeComingUpProvider = FutureProvider.autoDispose
    .family<ArrMerged<ArrCalendarEntry>, ArrDays>((ref, week) {
      // A download that finished takes its title off the row. Weak: this
      // row mustn't be what makes the queue load.
      ref.listen(arrQueueProvider, weak: true, (prev, next) {
        final before = prev?.value;
        if (before == null || !next.hasValue || next.isLoading) return;
        final after = next.requireValue;
        if (arrQueueItemLeft(
          before.items,
          after.items,
          unanswered: after.errors.keys.toSet(),
        )) {
          ref.invalidateSelf();
        }
      });
      return _both<ArrCalendarEntry>(
        _arrClients(ref),
        (c) => c.calendar(week.start, week.end),
      );
    });

final radarrMoviesProvider = FutureProvider.autoDispose<List<ArrMovie>>((
  ref,
) async {
  final c = ref.watch(radarrClientProvider);
  if (c == null) return const [];
  return c.movies();
});

final sonarrSeriesListProvider = FutureProvider.autoDispose<List<ArrSeries>>((
  ref,
) async {
  final c = ref.watch(sonarrClientProvider);
  if (c == null) return const [];
  return c.series();
});

/// Quality profile names by id, for one app.
final arrQualityProfilesProvider = FutureProvider.autoDispose
    .family<Map<int, String>, ArrKind>((ref, kind) async {
      final c = arrClientOf(ref, kind);
      if (c == null) return const {};
      try {
        return {for (final p in await c.qualityProfiles()) p.id: p.name};
      } catch (_) {
        return const {};
      }
    });

final radarrMovieProvider = FutureProvider.autoDispose.family<ArrMovie, int>((
  ref,
  id,
) async {
  final c = ref.watch(radarrClientProvider);
  if (c == null) throw ArrException('Radarr is not connected.');
  return c.movie(id);
});

final radarrMovieHistoryProvider = FutureProvider.autoDispose
    .family<List<ArrHistoryItem>, int>((ref, id) async {
      final c = ref.watch(radarrClientProvider);
      if (c == null) return const [];
      return c.history(id);
    });

final sonarrSeriesProvider = FutureProvider.autoDispose.family<ArrSeries, int>((
  ref,
  id,
) async {
  final c = ref.watch(sonarrClientProvider);
  if (c == null) throw ArrException('Sonarr is not connected.');
  return c.seriesById(id);
});

final sonarrEpisodesProvider = FutureProvider.autoDispose
    .family<List<ArrEpisode>, int>((ref, seriesId) async {
      final c = ref.watch(sonarrClientProvider);
      if (c == null) return const [];
      return c.episodes(seriesId);
    });

final sonarrEpisodeFilesProvider = FutureProvider.autoDispose
    .family<Map<int, ArrFile>, int>((ref, seriesId) async {
      final c = ref.watch(sonarrClientProvider);
      if (c == null) return const {};
      return {for (final f in await c.episodeFiles(seriesId)) f.id: f};
    });

final sonarrSeriesHistoryProvider = FutureProvider.autoDispose
    .family<List<ArrHistoryItem>, int>((ref, seriesId) async {
      final c = ref.watch(sonarrClientProvider);
      if (c == null) return const [];
      return c.history(seriesId);
    });

ArrClient? arrClientOf(Ref ref, ArrKind kind) => switch (kind) {
  ArrKind.sonarr => ref.watch(sonarrClientProvider),
  ArrKind.radarr => ref.watch(radarrClientProvider),
  ArrKind.lidarr => ref.watch(lidarrClientProvider),
};

/// The client for [kind], watched (a widget that shows its pictures).
ArrClient? arrWatchClient(WidgetRef ref, ArrKind kind) => switch (kind) {
  ArrKind.sonarr => ref.watch(sonarrClientProvider),
  ArrKind.radarr => ref.watch(radarrClientProvider),
  ArrKind.lidarr => ref.watch(lidarrClientProvider),
};

/// The client for [kind], read once (for actions, not for rebuilding).
ArrClient? arrClient(WidgetRef ref, ArrKind kind) => switch (kind) {
  ArrKind.sonarr => ref.read(sonarrClientProvider),
  ArrKind.radarr => ref.read(radarrClientProvider),
  ArrKind.lidarr => ref.read(lidarrClientProvider),
};

final lidarrArtistsProvider = FutureProvider.autoDispose<List<ArrArtist>>((
  ref,
) async {
  final c = ref.watch(lidarrClientProvider);
  if (c == null) return const [];
  return c.artists();
});

final lidarrArtistProvider = FutureProvider.autoDispose.family<ArrArtist, int>((
  ref,
  id,
) async {
  final c = ref.watch(lidarrClientProvider);
  if (c == null) throw ArrException('Lidarr is not connected.');
  return c.artist(id);
});

final lidarrAlbumsProvider = FutureProvider.autoDispose
    .family<List<ArrAlbum>, int>((ref, artistId) async {
      final c = ref.watch(lidarrClientProvider);
      if (c == null) return const [];
      return c.albums(artistId);
    });

final lidarrAlbumProvider = FutureProvider.autoDispose.family<ArrAlbum, int>((
  ref,
  id,
) async {
  final c = ref.watch(lidarrClientProvider);
  if (c == null) throw ArrException('Lidarr is not connected.');
  return c.album(id);
});

/// An album's tracks: asked for when the album is opened.
final lidarrTracksProvider = FutureProvider.autoDispose
    .family<List<ArrTrack>, int>((ref, albumId) async {
      final c = ref.watch(lidarrClientProvider);
      if (c == null) return const [];
      return c.tracks(albumId);
    });

/// One edition's tracks, for Manual Import when Lidarr matched a file to it.
final lidarrReleaseTracksProvider = FutureProvider.autoDispose
    .family<List<ArrTrack>, int>((ref, releaseId) async {
      final c = ref.watch(lidarrClientProvider);
      if (c == null) return const [];
      return c.releaseTracks(releaseId);
    });

/// An artist's track files, by id.
final lidarrTrackFilesProvider = FutureProvider.autoDispose
    .family<Map<int, ArrFile>, int>((ref, artistId) async {
      final c = ref.watch(lidarrClientProvider);
      if (c == null) return const {};
      return {for (final f in await c.trackFiles(artistId)) f.id: f};
    });

final lidarrArtistHistoryProvider = FutureProvider.autoDispose
    .family<List<ArrHistoryItem>, int>((ref, artistId) async {
      final c = ref.watch(lidarrClientProvider);
      if (c == null) return const [];
      return c.history(artistId);
    });

/// Lidarr's metadata profiles, in its order.
final lidarrMetadataProfilesProvider =
    FutureProvider.autoDispose<List<ArrMetadataProfile>>((ref) async {
      final c = ref.watch(lidarrClientProvider);
      if (c == null) return const [];
      try {
        return await c.metadataProfiles();
      } catch (_) {
        return const [];
      }
    });

/// After a change to an artist: everything that shows it reloads. Its
/// albums' tracks too, which an album search or a deleted file changes.
void arrArtistChanged(WidgetRef ref, int id) {
  ref.invalidate(lidarrArtistProvider(id));
  ref.invalidate(lidarrAlbumsProvider(id));
  ref.invalidate(lidarrTrackFilesProvider(id));
  ref.invalidate(lidarrTracksProvider);
  ref.invalidate(lidarrArtistHistoryProvider(id));
  ref.invalidate(lidarrArtistsProvider);
}

/// Radarr's collections, by title.
final radarrCollectionsProvider =
    FutureProvider.autoDispose<List<ArrCollection>>((ref) async {
      final c = ref.watch(radarrClientProvider);
      return c == null ? const [] : c.collections();
    });

/// One app's tags, sorted by name.
final arrTagsProvider = FutureProvider.autoDispose
    .family<List<ArrTag>, ArrKind>((ref, kind) async {
      final c = arrClientOf(ref, kind);
      return c == null ? const [] : c.tags();
    });

/// Root folders for one app, for adding a title.
final arrRootFoldersProvider = FutureProvider.autoDispose
    .family<List<ArrRootFolder>, ArrKind>((ref, kind) async {
      final c = arrClientOf(ref, kind);
      if (c == null) return const [];
      return c.rootFolders();
    });

/// Quality profiles for one app, in the app's order, for pickers.
final arrQualityProfileListProvider = FutureProvider.autoDispose
    .family<List<ArrQualityProfile>, ArrKind>((ref, kind) async {
      final c = arrClientOf(ref, kind);
      if (c == null) return const [];
      return c.qualityProfiles();
    });

/// The languages a file can be marked with in one app, by name, without
/// the profile-only Any and Original.
final arrLanguagesProvider = FutureProvider.autoDispose
    .family<List<ArrLanguage>, ArrKind>((ref, kind) async {
      final c = arrClientOf(ref, kind);
      if (c == null) return const [];
      final list = await c.languages();
      return [for (final l in list) if (l.id >= 0) l]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    });

/// Every quality a file can be in one app, worst to best.
final arrQualitiesProvider = FutureProvider.autoDispose
    .family<List<ArrQualityChoice>, ArrKind>((ref, kind) async {
      final c = arrClientOf(ref, kind);
      if (c == null) return const [];
      return c.qualities();
    });

/// Manual Import's recent folders in [kind], newest first.
List<String> arrImportRecent(Prefs p, ArrKind kind) => [
  for (final f in (p.arrImport[kind.name] as List?) ?? const [])
    if (f is String && f.isNotEmpty) f,
];

/// Puts [path] first in [kind]'s recent folders (five kept).
Future<void> rememberArrImportFolder(
  WidgetRef ref,
  ArrKind kind,
  String path,
) => ref.read(preferencesProvider.notifier).edit((p) {
  final recent = [
    path,
    for (final f in arrImportRecent(p, kind))
      if (f != path) f,
  ].take(5).toList();
  return p.copyWith(arrImport: {...p.arrImport, kind.name: recent});
});

/// Manual Import's last Move or Copy choice for folders, if any.
String? arrImportMode(Prefs p) => switch (p.arrImport['mode']) {
  'move' => 'move',
  'copy' => 'copy',
  _ => null,
};

Future<void> saveArrImportMode(WidgetRef ref, String mode) => ref
    .read(preferencesProvider.notifier)
    .edit((p) => p.copyWith(arrImport: {...p.arrImport, 'mode': mode}));

/// The saved starting choices for Add in one app.
ArrAddDefaults arrSavedDefaults(Prefs p, ArrKind kind) =>
    ArrAddDefaults.fromJson(switch (kind) {
      ArrKind.sonarr => p.sonarrAddDefaults,
      ArrKind.radarr => p.radarrAddDefaults,
      ArrKind.lidarr => p.lidarrAddDefaults,
    });

/// Saves what Add starts with next time in [kind].
Future<void> saveArrAddDefaults(
  WidgetRef ref,
  ArrKind kind,
  ArrAddDefaults d,
) => ref
    .read(preferencesProvider.notifier)
    .edit(
      (p) => switch (kind) {
        ArrKind.sonarr => p.copyWith(sonarrAddDefaults: d.toJson()),
        ArrKind.radarr => p.copyWith(radarrAddDefaults: d.toJson()),
        ArrKind.lidarr => p.copyWith(lidarrAddDefaults: d.toJson()),
      },
    );

/// Everything Add needs from one app before it can show its form: the root
/// folders (with what's already on disk), the quality profiles (and
/// Lidarr's metadata profiles), and the choices to start on.
typedef ArrAddSetup = ({
  List<ArrRootFolder> roots,
  List<ArrQualityProfile> profiles,
  List<ArrMetadataProfile> metadataProfiles,
  ArrAddChoice choice,
});

final arrAddSetupProvider = FutureProvider.autoDispose
    .family<ArrAddSetup, ArrKind>((ref, kind) async {
      final saved = ref.watch(
        preferencesProvider.select(
          (p) => arrSavedDefaults(p.asData?.value ?? const Prefs(), kind),
        ),
      );
      final rootsF = ref.watch(arrRootFoldersProvider(kind).future);
      final profilesF = ref.watch(arrQualityProfileListProvider(kind).future);
      final metadataF = kind == ArrKind.lidarr
          ? ref.watch(lidarrMetadataProfilesProvider.future)
          : Future.value(const <ArrMetadataProfile>[]);
      // The library only tells us the usual choices; when it can't load,
      // Add still works from the saved ones or the app's first.
      Future<List<ArrAddedWith>> library() async {
        try {
          if (kind == ArrKind.lidarr) {
            return [
              for (final a in await ref.watch(lidarrArtistsProvider.future))
                (
                  path: a.path,
                  qualityProfileId: a.qualityProfileId,
                  minimumAvailability: null,
                  seriesType: null,
                  seasonFolder: null,
                  metadataProfileId: a.metadataProfileId,
                ),
            ];
          }
          if (kind == ArrKind.sonarr) {
            return [
              for (final s in await ref.watch(sonarrSeriesListProvider.future))
                (
                  path: s.path,
                  qualityProfileId: s.qualityProfileId,
                  minimumAvailability: null,
                  seriesType: s.seriesType,
                  seasonFolder: s.seasonFolder,
                  metadataProfileId: null,
                ),
            ];
          }
          return [
            for (final m in await ref.watch(radarrMoviesProvider.future))
              (
                path: m.path,
                qualityProfileId: m.qualityProfileId,
                minimumAvailability: m.minimumAvailability,
                seriesType: null,
                seasonFolder: null,
                metadataProfileId: null,
              ),
          ];
        } catch (_) {
          return const [];
        }
      }

      final lib = await library();
      final roots = await rootsF;
      final profiles = await profilesF;
      final metadata = await metadataF;
      return (
        roots: roots,
        profiles: profiles,
        metadataProfiles: metadata,
        choice: arrStartingChoice(
          kind: kind,
          saved: saved,
          roots: [for (final r in roots) r.path],
          profiles: [for (final p in profiles) p.id],
          library: lib,
          metadataProfiles: [for (final p in metadata) p.id],
          rootDefaults: {
            for (final r in roots)
              if (r.defaults case final d?) r.path: d,
          },
        ),
      );
    });

/// After a change to a movie: everything that shows it reloads.
void arrMovieChanged(WidgetRef ref, int id) {
  ref.invalidate(radarrMovieProvider(id));
  ref.invalidate(radarrMovieHistoryProvider(id));
  ref.invalidate(radarrMoviesProvider);
  ref.invalidate(arrCalendarProvider);
  ref.invalidate(arrHomeComingUpProvider);
}

/// After a change to a show: everything that shows it reloads.
void arrSeriesChanged(WidgetRef ref, int id) {
  ref.invalidate(sonarrSeriesProvider(id));
  ref.invalidate(sonarrEpisodesProvider(id));
  ref.invalidate(sonarrEpisodeFilesProvider(id));
  ref.invalidate(sonarrSeriesHistoryProvider(id));
  ref.invalidate(sonarrSeriesListProvider);
  ref.invalidate(arrCalendarProvider);
  ref.invalidate(arrHomeComingUpProvider);
}

/// Wanted: missing, or below the cutoff.
enum ArrWantedList { missing, cutoffUnmet }

/// Both apps' paged lists, merged newest first. Each app is asked for its
/// newest [limit], so the merged list is right up to [limit] items; Load
/// More asks for a bigger [limit].
Future<ArrMerged<T>> _bothPaged<T>(
  Ref ref,
  Future<ArrPage<T>> Function(ArrClient c) load,
  DateTime? Function(T item) date,
  int limit,
) async {
  final errors = <ArrKind, String>{};
  var total = 0;
  // In the apps' one order, whichever answers first (see [_both]).
  final pages = await Future.wait([
    for (final c in _arrClients(ref))
        load(c)
            .then((p) {
              total += p.total;
              return p.items;
            })
            .catchError((Object e) {
              errors[c.kind] = e.toString();
              return <T>[];
            }),
  ]);
  final items = arrNewestFirst([for (final p in pages) ...p], date);
  final shown = items.take(limit).toList();
  return ArrMerged(shown, errors, total: total);
}

/// [items] newest first, those without a date last; those alike keep the
/// order they came in, so a list doesn't reshuffle with each refresh.
List<T> arrNewestFirst<T>(List<T> items, DateTime? Function(T item) date) {
  final far = DateTime(0);
  final sorted = [...items];
  mergeSort<T>(
    sorted,
    compare: (a, b) => (date(b) ?? far).compareTo(date(a) ?? far),
  );
  return sorted;
}

/// How many Wanted or History items to show; Load More raises it.
const arrPageSize = 50;

/// Wanted: which list, how many, and monitored (true) or unmonitored titles.
final arrWantedProvider = FutureProvider.autoDispose
    .family<ArrMerged<ArrWantedItem>, (ArrWantedList, int, bool)>((ref, arg) {
      final (list, limit, monitored) = arg;
      return _bothPaged<ArrWantedItem>(
        ref,
        (c) => list == ArrWantedList.missing
            ? c.missing(pageSize: limit, monitored: monitored)
            : c.cutoffUnmet(pageSize: limit, monitored: monitored),
        // What isn't out yet goes last, not first as the newest.
        (w) => w.available ? w.date : null,
        limit,
      );
    });

final arrRecentHistoryProvider = FutureProvider.autoDispose
    .family<ArrMerged<ArrHistoryItem>, (int, ArrHistoryFilter)>(
      (ref, arg) => _bothPaged<ArrHistoryItem>(
        ref,
        (c) => c.recentHistory(pageSize: arg.$1, only: arg.$2),
        (h) => h.date,
        arg.$1,
      ),
    );

/// Both apps' blocklists, newest first.
final arrBlocklistProvider = FutureProvider.autoDispose
    .family<ArrMerged<ArrBlocklistItem>, int>(
      (ref, limit) => _bothPaged<ArrBlocklistItem>(
        ref,
        (c) => c.blocklist(pageSize: limit),
        (b) => b.date,
        limit,
      ),
    );

/// Each connected app's health check, and its version.
class ArrAppHealth {
  /// The app's kind; null for Prowlarr, which isn't one.
  final ArrKind? kind;

  /// The app's name.
  final String name;
  final String? version;
  final List<ArrHealth> issues;
  final String? error; // the app couldn't be reached
  ArrAppHealth(
    ArrKind this.kind, {
    this.version,
    this.issues = const [],
    this.error,
  }) : name = kind.appName;

  const ArrAppHealth.prowlarr({
    this.version,
    this.issues = const [],
    this.error,
  }) : kind = null,
       name = ProwlarrClient.appName;

  const ArrAppHealth.bazarr({
    this.version,
    this.issues = const [],
    this.error,
  }) : kind = null,
       name = BazarrClient.appName;

  int get problems => issues.where((i) => i.isProblem).length;
}

final arrHealthProvider = FutureProvider.autoDispose<List<ArrAppHealth>>((
  ref,
) async {
  Future<ArrAppHealth> one(ArrClient c) async {
    try {
      final r = await Future.wait([c.status(), c.health()]);
      return ArrAppHealth(
        c.kind,
        version: (r[0] as ArrStatus).version,
        issues: r[1] as List<ArrHealth>,
      );
    } catch (e) {
      return ArrAppHealth(c.kind, error: e.toString());
    }
  }

  Future<ArrAppHealth> prowlarr(ProwlarrClient c) async {
    try {
      final r = await Future.wait([c.status(), c.health()]);
      return ArrAppHealth.prowlarr(
        version: (r[0] as ArrStatus).version,
        issues: r[1] as List<ArrHealth>,
      );
    } catch (e) {
      return ArrAppHealth.prowlarr(error: e.toString());
    }
  }

  Future<ArrAppHealth> bazarr(BazarrClient c) async {
    try {
      final r = await Future.wait([c.version(), c.health()]);
      return ArrAppHealth.bazarr(
        version: r[0] as String,
        issues: r[1] as List<ArrHealth>,
      );
    } catch (e) {
      return ArrAppHealth.bazarr(error: e.toString());
    }
  }

  final p = ref.watch(prowlarrClientProvider);
  final b = ref.watch(bazarrClientProvider);
  return Future.wait([
    for (final c in _arrClients(ref)) one(c),
    // After the apps they serve.
    ?(p == null ? null : prowlarr(p)),
    ?(b == null ? null : bazarr(b)),
  ]);
});

/// How many warnings and errors both apps report, for the badge on the
/// Health button. Zero while loading or when the apps can't be reached
/// (their tabs already say so).
final arrHealthProblemsProvider = Provider.autoDispose<int>((ref) {
  final list = ref.watch(arrHealthProvider).asData?.value ?? const [];
  return list.fold(0, (n, a) => n + a.problems + (a.error != null ? 1 : 0));
});

/// A Jellyfin movie or show, found in Radarr or Sonarr by its TMDB or TVDB
/// id. [id] is null when the app doesn't have it yet.
typedef ArrMatch = ({ArrKind kind, int? id});

/// Looks a Jellyfin title up in the app that manages its kind. Null when
/// that app isn't connected, the title has no usable id, or the app can't
/// be reached (the shortcut simply doesn't show).
final arrMatchProvider = FutureProvider.autoDispose
    .family<ArrMatch?, ({ArrKind kind, int providerId})>((ref, arg) async {
      try {
        if (arg.kind == ArrKind.radarr) {
          final c = ref.watch(radarrClientProvider);
          if (c == null) return null;
          final m = await c.movieByTmdb(arg.providerId);
          return (kind: ArrKind.radarr, id: m?.id);
        }
        final c = ref.watch(sonarrClientProvider);
        if (c == null) return null;
        final s = await c.seriesByTvdb(arg.providerId);
        return (kind: ArrKind.sonarr, id: s?.id);
      } catch (_) {
        return null;
      }
    });

/// A Jellyfin music artist in Lidarr, by its MusicBrainz id: its id there,
/// or null in the match when Lidarr hasn't got it. Null when Lidarr isn't
/// connected or can't be reached (the link simply doesn't show).
final lidarrMatchProvider = FutureProvider.autoDispose
    .family<ArrMatch?, String>((ref, mbId) async {
      final c = ref.watch(lidarrClientProvider);
      if (c == null || mbId.isEmpty) return null;
      try {
        final a = await c.artistByMbId(mbId);
        return (kind: ArrKind.lidarr, id: a?.id);
      } catch (_) {
        return null;
      }
    });

/// Where a title Seerr knows is looked up in Fathom's own Radarr (a movie,
/// by its TMDB id) or Sonarr (a show, by its TVDB id), for [arrMatchProvider].
/// Null without the id.
({ArrKind kind, int providerId})? arrKeyOfSeerr({
  required String mediaType,
  required int tmdbId,
  int? tvdbId,
}) {
  if (mediaType == 'tv') {
    return tvdbId == null || tvdbId <= 0
        ? null
        : (kind: ArrKind.sonarr, providerId: tvdbId);
  }
  return tmdbId <= 0 ? null : (kind: ArrKind.radarr, providerId: tmdbId);
}

/// A Radarr movie, a Sonarr show or a Lidarr artist, as the Jellyfin
/// library is asked for it.
typedef ArrLibraryKey = ({
  ArrKind kind,
  String title,
  int? year,
  int? tmdbId,
  int? tvdbId,
  String? imdbId,

  /// An artist's MusicBrainz id, which Jellyfin reads from the files' tags.
  String? mbId,

  /// The app has files of it, so it's worth a longer look.
  bool onDisk,
});

ArrLibraryKey arrLibraryKeyOfMovie(ArrMovie m) => (
  kind: ArrKind.radarr,
  title: m.title,
  year: m.year,
  tmdbId: m.tmdbId,
  tvdbId: null,
  imdbId: m.imdbId,
  mbId: null,
  onDisk: m.hasFile,
);

ArrLibraryKey arrLibraryKeyOfSeries(ArrSeries s) => (
  kind: ArrKind.sonarr,
  title: s.title,
  year: s.year,
  tmdbId: s.tmdbId,
  tvdbId: s.tvdbId,
  imdbId: s.imdbId,
  mbId: null,
  onDisk: s.episodeFileCount > 0,
);

ArrLibraryKey arrLibraryKeyOfArtist(ArrArtist a) => (
  kind: ArrKind.lidarr,
  title: a.name,
  year: null,
  tmdbId: null,
  tvdbId: null,
  imdbId: null,
  mbId: a.foreignArtistId,
  onDisk: a.trackFileCount > 0,
);

/// When the library is asked again for a title that's on disk and wasn't
/// found: a new download isn't there until the server has scanned it in.
/// After the last of these it's left to a refresh of the page.
@visibleForTesting
const arrLibraryLookAgain = [
  Duration(seconds: 20),
  Duration(seconds: 60),
  Duration(seconds: 120),
];

/// The Jellyfin item of a Radarr movie, a Sonarr show or a Lidarr artist, by
/// the ids they share: what Watch (Play, for an artist) opens. Null when the library hasn't got it, and when
/// the server can't be asked, where the button simply doesn't show.
final arrLibraryItemProvider = StreamProvider.autoDispose
    .family<String?, ArrLibraryKey>((ref, k) async* {
      final signedIn = ref.watch(sessionControllerProvider);
      final session = signedIn.value;
      if (session == null) {
        // Who's signed in isn't known yet: no answer until it is, when this
        // is asked afresh.
        if (signedIn.isLoading) {
          final known = Completer<void>();
          ref.onDispose(known.complete);
          await known.future;
          return;
        }
        yield null;
        return;
      }
      final client = ref.watch(jellyfinClientProvider);
      String? id(int? n) => n == null || n <= 0 ? null : '$n';
      Future<String?> look() async {
        try {
          return await client.findItemIdByProviderIds(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
            itemType: switch (k.kind) {
              ArrKind.radarr => 'Movie',
              ArrKind.sonarr => 'Series',
              ArrKind.lidarr => 'MusicArtist',
            },
            title: k.title,
            year: k.year,
            byYear: k.onDisk,
            providerIds: {
              'Tmdb': ?id(k.tmdbId),
              'Tvdb': ?id(k.tvdbId),
              'Imdb': ?k.imdbId,
              'MusicBrainzArtist': ?k.mbId,
            },
          );
        } catch (_) {
          return null;
        }
      }

      // The page closed while waiting: nothing more is asked.
      var closed = false;
      Timer? timer;
      Completer<void>? wait;
      ref.onDispose(() {
        closed = true;
        timer?.cancel();
        final waiting = wait;
        if (waiting != null && !waiting.isCompleted) waiting.complete();
      });
      var found = await look();
      yield found;
      if (!k.onDisk) return;
      for (final after in arrLibraryLookAgain) {
        if (found != null) return;
        final waiting = wait = Completer<void>();
        timer = Timer(after, waiting.complete);
        await waiting.future;
        if (closed) return;
        found = await look();
        if (found != null) yield found;
      }
    });

/// What the Activity tab's count shows.
class ArrQueueStatus {
  /// Downloads in both queues.
  final int count;

  /// One of them needs a look.
  final bool problem;

  /// An app didn't answer, so its downloads aren't counted.
  final bool unreachable;
  const ArrQueueStatus({
    required this.count,
    required this.problem,
    required this.unreachable,
  });
}

/// The queue's count, from the apps' small status answer. It asks again
/// whenever the full queue has just reloaded, so the two never disagree for
/// long.
final arrQueueStatusProvider = FutureProvider.autoDispose<ArrQueueStatus>((
  ref,
) async {
  // Weak: watching for a reload mustn't be what makes the full queue load.
  ref.listen(arrQueueProvider, weak: true, (_, next) {
    if (next.hasValue && !next.isLoading) ref.invalidateSelf();
  });
  var count = 0;
  var problem = false;
  var unreachable = false;
  await Future.wait([
    for (final c in _arrClients(ref))
        c
            .queueStatus()
            .then((s) {
              count += s.count;
              problem = problem || s.problem;
            })
            .catchError((Object _) {
              unreachable = true;
            }),
  ]);
  return ArrQueueStatus(
    count: count,
    problem: problem,
    unreachable: unreachable,
  );
});

/// After a search, grab or failure: the lists that show them reload.
void arrListsChanged(WidgetRef ref) {
  ref.invalidate(arrWantedProvider);
  ref.invalidate(arrRecentHistoryProvider);
  ref.invalidate(arrQueueProvider);
}
