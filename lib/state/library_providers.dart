import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/base_item.dart';
import '../models/guide_data.dart';
import '../models/user_dto.dart';
import 'preferences.dart';
import 'providers.dart';
import 'session_controller.dart';
import '../api/jellyfin_client.dart';

/// Whether the active server is reachable. Emits true when no session is
/// active (nothing to be offline from).
///
/// Asked every 30 seconds while it answers, every 5 while it doesn't, and at
/// once when the app comes back to the screen. It used to be every 30 either
/// way: with the network back, the banner stayed up to half a minute and
/// Home kept its "Could not load" rows until pulled. When it's back, the
/// lists that failed are read again. A single miss while it was answering
/// is checked a second time before it counts, so a slow wake-up doesn't
/// flash the banner.
final serverReachableProvider = StreamProvider.autoDispose<bool>((ref) {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return Stream.value(true);
  final client = ref.watch(jellyfinClientProvider);
  final out = StreamController<bool>();
  var disposed = false;
  var busy = false;
  Timer? next;
  bool? last;

  Future<void> probe() async {
    if (disposed || busy) return;
    busy = true;
    next?.cancel();
    var ok = await client.pingServer(session.baseUrl);
    if (!ok && last != false && !disposed) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!disposed) ok = await client.pingServer(session.baseUrl);
    }
    busy = false;
    if (disposed) return;
    if (ok && last == false) {
      ref.invalidate(resumeItemsProvider);
      ref.invalidate(nextUpItemsProvider);
      ref.invalidate(latestItemsProvider);
      ref.invalidate(heroItemsProvider);
      ref.invalidate(userViewsProvider);
    }
    if (ok != last) out.add(ok);
    last = ok;
    next = Timer(Duration(seconds: ok ? 30 : 5), probe);
  }

  final life = AppLifecycleListener(onResume: probe);
  unawaited(probe());
  ref.onDispose(() {
    disposed = true;
    next?.cancel();
    life.dispose();
    out.close();
  });
  return out.stream;
});

/// The signed-in user's live policy (admin / delete rights), fetched fresh so
/// it works even for sessions saved before we captured the flag.
final currentUserProvider = FutureProvider.autoDispose<UserDto?>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return null;
  final client = ref.watch(jellyfinClientProvider);
  try {
    return await client.getCurrentUser(
        baseUrl: session.baseUrl, token: session.accessToken);
  } catch (_) {
    return null;
  }
});

/// Auth headers to attach when loading images with `Image.network`.
final imageHeadersProvider = Provider<Map<String, String>>((ref) {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  final client = ref.watch(jellyfinClientProvider);
  if (session == null) return const {};
  return {'Authorization': client.authHeader(token: session.accessToken)};
});

final userViewsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getUserViews(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
});

final resumeItemsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  final items = await client.getResumeItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
  return collapseResumeBySeries(items);
});

/// Continue Watching the way Netflix and Plex do it: one entry per show,
/// whether you stopped in the middle of an episode or finished one and the
/// next is waiting, ordered by when you actually last watched.
///
/// Built from three server lists because none of them is enough alone, all
/// measured on a real 12.0 server:
/// * the resume list only holds things you stopped part-way through, so a
///   show you finish episode by episode never appears in it;
/// * Next Up has the waiting episodes, but in an order that put the show
///   watched last night ninth of fifteen;
/// * neither a series nor a waiting episode carries a last-watched date, but a
///   finished episode does, so the recently finished list is what ranks shows.
///
/// Watches the resume and Next Up providers, so every place that already
/// refreshes those (playback ending, Mark Watched, pull to refresh) refreshes
/// this row too.
final continueWatchingProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  // Only the dismissals, flattened to a string so the comparison is by value:
  // watching all of Prefs would refetch this row on every volume change.
  final dismissedRaw = ref.watch(preferencesProvider.select((p) {
    final m = p.asData?.value.continueWatchingDismissed ?? const {};
    return (m.entries.map((e) => '${e.key}=${e.value}').toList()..sort())
        .join(';');
  }));
  final prefix = '${session.userId}|';
  final dismissed = <String, DateTime>{
    for (final pair in dismissedRaw.split(';'))
      if (pair.startsWith(prefix) && pair.contains('='))
        pair.substring(prefix.length, pair.indexOf('=')):
            DateTime.tryParse(pair.substring(pair.indexOf('=') + 1)) ??
                DateTime.fromMillisecondsSinceEpoch(0),
  };
  final resume = await ref.watch(resumeItemsProvider.future);
  final nextUp = await ref.watch(nextUpItemsProvider.future);
  final finished = await client.getRecentlyFinishedEpisodes(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
  // The recent history is a count of episodes, so marking a season watched
  // pushes every other show out of it: on a real server one afternoon of Mark
  // Watched dropped Batman, INVINCIBLE and The Twilight Zone off the row. Any
  // show it doesn't cover gets its own last finished episode instead.
  final known = {for (final ep in finished) ep.seriesId};
  final missing = {
    for (final ep in [...resume, ...nextUp])
      if (ep.seriesId != null && !known.contains(ep.seriesId)) ep.seriesId!,
  };
  final older = await Future.wait([
    for (final seriesId in missing)
      client
          .getRecentlyFinishedEpisodes(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
            seriesId: seriesId,
            limit: 1,
          )
          .catchError((_) => const <BaseItemDto>[]),
  ]);
  return mergeContinueWatching(
    resume: resume,
    nextUp: nextUp,
    finished: [...finished, for (final list in older) ...list],
    dismissed: dismissed,
    now: DateTime.now(),
  );
});

/// How long a newly arrived episode counts as new: long enough to cover a
/// show you watch a week or two behind, short enough that a months-old arrival
/// doesn't jump the queue.
const newEpisodeWindow = Duration(days: 30);

/// Whether a waiting episode reached the library recently.
bool isFreshArrival(BaseItemDto episode, DateTime now) {
  final created = episode.dateCreated;
  return created != null && now.difference(created) <= newEpisodeWindow;
}

/// The key a Continue Watching entry is dismissed under: the show for an
/// episode, so removing one episode takes the whole show off the row, and the
/// title itself for a film.
String continueWatchingKey(BaseItemDto item) => item.seriesId ?? item.id;

/// The ordering and choice behind [continueWatchingProvider], kept pure so it
/// can be tested against real data.
List<BaseItemDto> mergeContinueWatching({
  required List<BaseItemDto> resume,
  required List<BaseItemDto> nextUp,
  required List<BaseItemDto> finished,
  Map<String, DateTime> dismissed = const {},
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  // Removed from the row, and not watched since: stay off it.
  bool hidden(String key, DateTime? latest) {
    final at = dismissed[key];
    return at != null && (latest == null || !latest.isAfter(at));
  }

  // The most recent finished episode per show.
  final lastFinished = <String, DateTime>{};
  for (final ep in finished) {
    final id = ep.seriesId;
    final at = ep.userData.lastPlayedDate;
    if (id == null || at == null) continue;
    final seen = lastFinished[id];
    if (seen == null || at.isAfter(seen)) lastFinished[id] = at;
  }

  final resumeBySeries = <String, BaseItemDto>{};
  final standalone = <BaseItemDto>[];
  for (final item in resume) {
    final id = item.seriesId;
    if (id == null) {
      standalone.add(item);
    } else {
      resumeBySeries.putIfAbsent(id, () => item);
    }
  }
  final nextBySeries = <String, BaseItemDto>{};
  for (final item in nextUp) {
    final id = item.seriesId;
    if (id != null) nextBySeries.putIfAbsent(id, () => item);
  }

  final entries = <({BaseItemDto item, DateTime? at, int order})>[];
  var order = 0;
  for (final item in standalone) {
    final at = item.userData.lastPlayedDate;
    if (hidden(item.id, at)) continue;
    entries.add((item: item, at: at, order: order++));
  }
  for (final id in {...resumeBySeries.keys, ...nextBySeries.keys}) {
    final inProgress = resumeBySeries[id];
    final waiting = nextBySeries[id];
    final done = lastFinished[id];
    final started = inProgress?.userData.lastPlayedDate;
    // A show that's only waiting joins this row if your history shows you've
    // actually been watching it. Next Up offers every show you ever finished
    // an episode of; the rest still appear in the Next Up row.
    if (inProgress == null && done == null) continue;
    // Show the half-watched episode only if you touched it after the last one
    // you finished. A real library had a Twilight Zone episode left half-way
    // in September 2025 while Season 3 was being finished in March 2026; the
    // row should say where you are, not where you once stopped.
    final showInProgress = inProgress != null &&
        (waiting == null ||
            done == null ||
            (started != null && started.isAfter(done)));
    final chosen = showInProgress ? inProgress : waiting!;
    DateTime? newest(Iterable<DateTime?> dates) => dates
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final lastSeen = newest([started, done]);
    // A new episode of a show you've been watching ranks by when it arrived,
    // so Season 4 of something you finished in March goes to the front the
    // day it appears. The next episode of a show you drifted away from arrived
    // with the rest of its season, long ago, so it gets no boost.
    final arrived = !showInProgress &&
            waiting != null &&
            lastSeen != null &&
            isFreshArrival(waiting, clock)
        ? waiting.dateCreated
        : null;
    final latest = newest([lastSeen, arrived]);
    // Waiting for more than a year with nothing new: you've moved on. The
    // same cut-off Jellyfin's own Next Up uses by default.
    if (!showInProgress &&
        latest != null &&
        clock.difference(latest) > const Duration(days: 365)) {
      continue;
    }
    if (hidden(id, latest)) continue;
    entries.add((item: chosen, at: latest, order: order++));
  }

  // Newest first. Anything with no known date keeps its place after the dated
  // ones rather than being shuffled by a guess.
  entries.sort((a, b) {
    if (a.at == null && b.at == null) return a.order.compareTo(b.order);
    if (a.at == null) return 1;
    if (b.at == null) return -1;
    return b.at!.compareTo(a.at!);
  });
  return [for (final e in entries) e.item];
}

/// One entry per series in Continue Watching, keeping the most recent.
///
/// Jellyfin lists every part-watched episode, which turns the row into a
/// shelf: a real library produced eleven entries from two cartoon series,
/// each a minute or so into a six-minute short, burying the four other things
/// in there. Films and one-offs are untouched, and the server's order (most
/// recently played first) is preserved, so the kept episode is simply the
/// first one seen for its series.
List<BaseItemDto> collapseResumeBySeries(List<BaseItemDto> items) {
  final seen = <String>{};
  return [
    for (final item in items)
      if (item.seriesId == null || seen.add(item.seriesId!)) item,
  ];
}

/// Full details for a cast/crew member (biography, images).
final personDetailProvider = FutureProvider.autoDispose
    .family<BaseItemDto?, String>((ref, id) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null || id.isEmpty) return null;
  try {
    return await ref.watch(jellyfinClientProvider).getItem(
          baseUrl: session.baseUrl,
          userId: session.userId,
          token: session.accessToken,
          itemId: id,
        );
  } catch (_) {
    return null;
  }
});

/// A title's extras: behind the scenes, deleted scenes, interviews, and any
/// trailer files on the server.
final extrasProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, String>((ref, itemId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  return ref.watch(jellyfinClientProvider).getExtras(
        baseUrl: session.baseUrl,
        userId: session.userId,
        token: session.accessToken,
        itemId: itemId,
      );
});

/// "More Like This" — titles similar to a given item.
final similarItemsProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, String>((ref, itemId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  return ref.watch(jellyfinClientProvider).getSimilar(
        baseUrl: session.baseUrl,
        userId: session.userId,
        token: session.accessToken,
        itemId: itemId,
      );
});

/// Recently added items within a single library (for per-library Home rows).
final latestInLibraryProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, String>((ref, parentId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getLatestItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    parentId: parentId,
    limit: 16,
  );
});

/// The user's global Next Up queue (next episodes across all series).
final nextUpItemsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getNextUpItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    // Continue Watching draws on this list too, and a show with a new episode
    // shouldn't miss the row because Next Up cut off at twenty.
    limit: 50,
  );
});

/// Items for the Home hero, the way Fladder/Moonfin do it: what you're
/// watching first (Continue Watching, then Next Up), filled with Recently
/// Added when you're all caught up. De-duplicated, capped at 8.
final heroItemsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final results = await Future.wait([
    ref.watch(continueWatchingProvider.future),
    ref.watch(latestItemsProvider.future),
  ]);
  return heroMix(watching: results[0], added: results[1]);
});

/// What the Home banner rotates through: the few things you're actually in
/// the middle of, then what's new.
///
/// It used to take eight straight from the resume and Next Up lists, which on
/// a real library meant a film from July and three year-old cartoon shorts led
/// the biggest slot on the screen while the show watched the night before
/// didn't appear at all. It now reads the same merged, recency-ordered list as
/// the Continue Watching row, so the two can never disagree, and it stops
/// after [watchingSlots] of those: past that the banner would only repeat the
/// row sitting directly under it, where fresh additions give the carousel a
/// reason to exist.
List<BaseItemDto> heroMix({
  required List<BaseItemDto> watching,
  required List<BaseItemDto> added,
  int watchingSlots = 3,
  // Matches what the carousel shows: FeaturedHero takes six.
  int total = 6,
}) {
  final seen = <String>{};
  final out = <BaseItemDto>[];
  void take(Iterable<BaseItemDto> from, int upTo) {
    for (final item in from) {
      if (out.length >= upTo) return;
      // A series episode and its show can both surface; one card per show.
      final key = item.seriesId ?? item.id;
      if (seen.add(key)) out.add(item);
    }
  }

  take(watching, watchingSlots);
  take(added, total);
  // A thin library with little new: let what you're watching fill the rest
  // rather than show a half-empty banner.
  take(watching, total);
  return out;
}

final latestItemsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getLatestItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
});

/// Live TV channels with their current program.
final liveTvChannelsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getLiveTvChannels(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
});

/// All genres across the user's libraries.
final genresProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getGenres(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
});

/// All studios/networks across the user's libraries.
final studiosProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getStudios(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
});

/// Movies + series from a given studio/network, newest first.
typedef StudioQuery = ({String studio, String sortBy, String sortOrder});

final studioItemsProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, StudioQuery>((ref, q) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  final res = await client.getItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    studios: q.studio,
    includeItemTypes: 'Movie,Series',
    recursive: true,
    sortBy: q.sortBy,
    sortOrder: q.sortOrder,
    limit: 300,
  );
  return res.items;
});

/// All music artists.
final artistsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getArtists(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
});

/// A given artist's albums, newest first.
final artistAlbumsProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, String>((ref, artistId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  final res = await client.getItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    albumArtistIds: artistId,
    includeItemTypes: 'MusicAlbum',
    recursive: true,
    sortBy: 'PremiereDate,SortName',
    sortOrder: 'Descending',
    limit: 300,
  );
  return res.items;
});

typedef GenreQuery = ({String genre, String sortBy, String sortOrder});

/// Movies + series tagged with a given genre, in the requested sort order.
final genreItemsProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, GenreQuery>((ref, q) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  final res = await client.getItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    genres: q.genre,
    includeItemTypes: 'Movie,Series',
    recursive: true,
    sortBy: q.sortBy,
    sortOrder: q.sortOrder,
    limit: 300,
  );
  return res.items;
});

/// A person's filmography (movies + series they appear in), newest first.
final personItemsProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, String>((ref, personId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  final res = await client.getItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    personIds: personId,
    includeItemTypes: 'Movie,Series',
    recursive: true,
    sortBy: 'PremiereDate,ProductionYear',
    sortOrder: 'Descending',
    limit: 200,
  );
  return res.items;
});

/// The user's favorites (movies, series, albums).
final favoriteItemsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  // Everything favorited, in pages, so a long list is never cut short.
  final items = <BaseItemDto>[];
  const page = 200;
  while (true) {
    final res = await client.getItems(
      baseUrl: session.baseUrl,
      userId: session.userId,
      token: session.accessToken,
      isFavorite: true,
      includeItemTypes: favoriteItemTypes,
      recursive: true,
      sortBy: 'SortName',
      startIndex: items.length,
      limit: page,
    );
    items.addAll(res.items);
    if (res.items.length < page || items.length >= res.totalRecordCount) {
      break;
    }
  }
  final people = await client.getFavoritePeople(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
  final seen = {for (final i in items) i.id};
  return [
    ...items,
    for (final p in people)
      if (seen.add(p.id)) p,
  ];
});

/// What Favorites lists from /Items (people come from /Persons).
const favoriteItemTypes =
    'Movie,Series,Episode,BoxSet,Video,MusicVideo,MusicAlbum,MusicArtist,'
    'Audio,Playlist';

/// The groups Favorites can be narrowed to, each with the item types in it.
enum FavoriteGroup {
  movies({'Movie'}),
  shows({'Series'}),
  episodes({'Episode'}),
  collections({'BoxSet'}),
  videos({'Video', 'MusicVideo'}),
  music({'MusicAlbum', 'MusicArtist', 'Audio'}),
  playlists({'Playlist'}),
  people({'Person'});

  const FavoriteGroup(this.types);
  final Set<String> types;

  static FavoriteGroup? of(BaseItemDto item) {
    for (final g in values) {
      if (g.types.contains(item.type)) return g;
    }
    return null;
  }
}

/// Children of a collection (BoxSet).
final collectionItemsProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, String>((ref, boxSetId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  final res = await client.getItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    parentId: boxSetId,
    sortBy: 'SortName',
    limit: 300,
  );
  return res.items;
});

/// DVR recordings.
final recordingsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getRecordings(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
  );
});

/// EPG guide: channels + their programs. The window starts short (so it loads
/// fast) and grows in chunks via [GuideController.loadMore] as the user scrolls
/// right, until the server has no more EPG data.
class GuideController extends AsyncNotifier<GuideData> {
  // Initial span, then how much each scroll-triggered fetch adds. Kept modest so
  // the first paint is quick and later chunks stay light.
  static const _initialHours = 12;
  static const _chunkHours = 12;
  // A hard ceiling so a provider with unbounded EPG can't grow the grid forever.
  static const _maxHours = 14 * 24;

  @override
  Future<GuideData> build() async {
    final channels = await ref.watch(liveTvChannelsProvider.future);
    final session = ref.watch(sessionControllerProvider).asData?.value;
    // Window: floor to the previous half hour so tiles align to the ruler.
    final now = DateTime.now();
    final start = DateTime(
        now.year, now.month, now.day, now.hour, now.minute >= 30 ? 30 : 0);
    final end = start.add(const Duration(hours: _initialHours));
    if (channels.isEmpty || session == null) {
      return GuideData(
        channels: channels,
        programsByChannel: const {},
        windowStart: start,
        windowEnd: end,
        atEnd: true,
      );
    }
    final byChannel = await _fetch(session, channels, start, end);
    return GuideData(
      channels: channels,
      programsByChannel: byChannel,
      windowStart: start,
      windowEnd: end,
    );
  }

  /// Extend the window by another chunk, fetching only the new segment and
  /// merging it in. No-op while a fetch is in flight, once the end of the EPG is
  /// reached, or at the safety ceiling.
  Future<void> loadMore() async {
    final data = state.asData?.value;
    if (data == null || data.loadingMore || data.atEnd) return;
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null || data.channels.isEmpty) return;

    final segStart = data.windowEnd;
    final segEnd = segStart.add(const Duration(hours: _chunkHours));
    state = AsyncData(data.copyWith(loadingMore: true));
    try {
      final seg = await _fetch(session, data.channels, segStart, segEnd);
      final added = seg.values.fold<int>(0, (n, l) => n + l.length);
      // No programs in the new segment means the provider's EPG stops here.
      final reachedCeiling =
          segEnd.difference(data.windowStart).inHours >= _maxHours;
      final merged = <String, List<BaseItemDto>>{
        for (final e in data.programsByChannel.entries) e.key: List.of(e.value),
      };
      for (final e in seg.entries) {
        (merged[e.key] ??= <BaseItemDto>[]).addAll(e.value);
      }
      state = AsyncData(data.copyWith(
        programsByChannel: merged,
        windowEnd: segEnd,
        loadingMore: false,
        atEnd: added == 0 || reachedCeiling,
      ));
    } catch (_) {
      // A failed chunk shouldn't wipe the grid; just stop extending.
      state = AsyncData(data.copyWith(loadingMore: false, atEnd: true));
    }
  }

  Future<Map<String, List<BaseItemDto>>> _fetch(dynamic session,
      List<BaseItemDto> channels, DateTime start, DateTime end) async {
    final client = ref.read(jellyfinClientProvider);
    final programs = await client.getGuidePrograms(
      baseUrl: session.baseUrl,
      userId: session.userId,
      token: session.accessToken,
      channelIds: channels.map((c) => c.id).toList(),
      start: start,
      end: end,
    );
    final byChannel = <String, List<BaseItemDto>>{};
    for (final p in programs) {
      (byChannel[p.channelId ?? ''] ??= []).add(p);
    }
    return byChannel;
  }
}

final guideProvider =
    AsyncNotifierProvider.autoDispose<GuideController, GuideData>(
        GuideController.new);

/// Full detail for a single item, by id.
final itemDetailProvider =
    FutureProvider.autoDispose.family<BaseItemDto, String>((ref, itemId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) throw StateError('Not signed in');
  final client = ref.watch(jellyfinClientProvider);
  return client.getItem(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    itemId: itemId,
  );
});

/// Tracks of a music album, in disc/track order.
final albumTracksProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, String>((ref, albumId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  final res = await client.getItems(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    parentId: albumId,
    includeItemTypes: 'Audio',
    sortBy: 'ParentIndexNumber,IndexNumber',
    limit: 500,
  );
  return res.items;
});

/// The next episode to watch for a series (null if none).
final nextUpProvider =
    FutureProvider.autoDispose.family<BaseItemDto?, String>((ref, seriesId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return null;
  final client = ref.watch(jellyfinClientProvider);
  return client.getNextUp(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    seriesId: seriesId,
  );
});

/// What Play starts for [item]: itself, or for a show its Next Up, falling
/// back to the first episode when there's no Next Up (all watched, or a
/// recorded series). Null while a show's episodes are still loading, or when
/// it has none. A show itself can't be played: the server refuses it.
BaseItemDto? playTargetFor(WidgetRef ref, BaseItemDto item) {
  if (!item.isSeries) return item;
  final nextUp = ref.watch(nextUpProvider(item.id)).asData?.value;
  if (nextUp != null) return nextUp;
  final episodes = ref.watch(episodesProvider(item.id)).asData?.value;
  return (episodes == null || episodes.isEmpty) ? null : episodes.first;
}

/// All episodes of a series, in order.
final episodesProvider = FutureProvider.autoDispose
    .family<List<BaseItemDto>, String>((ref, seriesId) async {
  final session = ref.watch(sessionControllerProvider).asData?.value;
  if (session == null) return const [];
  final client = ref.watch(jellyfinClientProvider);
  return client.getEpisodes(
    baseUrl: session.baseUrl,
    userId: session.userId,
    token: session.accessToken,
    seriesId: seriesId,
  );
});
