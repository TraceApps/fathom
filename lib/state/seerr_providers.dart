import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/mdblist_client.dart';
import '../api/seerr_client.dart';
import '../models/seerr_detail.dart';
import '../models/seerr_genre.dart';
import '../models/seerr_person.dart';
import '../models/seerr_request.dart';
import '../models/seerr_result.dart';
import 'preferences.dart';

final seerrClientProvider = Provider<SeerrClient?>((ref) {
  final prefs = ref.watch(preferencesProvider).asData?.value;
  if (prefs == null || prefs.seerrUrl.isEmpty) return null;
  final url = prefs.seerrUrl.replaceAll(RegExp(r'/+$'), '');
  // Signed-in (cookie) auth takes precedence over the admin API key.
  if (prefs.seerrAuthMode == 'cookie' && prefs.seerrCookie.isNotEmpty) {
    return SeerrClient(url, '', cookie: prefs.seerrCookie);
  }
  if (prefs.seerrApiKey.isNotEmpty) return SeerrClient(url, prefs.seerrApiKey);
  return null;
});

final seerrConfiguredProvider =
    Provider<bool>((ref) => ref.watch(seerrClientProvider) != null);

// Jellyseerr permission flags used for gating request actions.
const kSeerrAdmin = 2;
const kSeerrManageRequests = 16;

/// True when [permissions] grants [flag] (ADMIN grants everything).
bool seerrCan(int permissions, int flag) =>
    permissions & kSeerrAdmin != 0 || permissions & flag != 0;

/// The signed-in user's permissions. In API-key mode the client is the admin,
/// so it reports ADMIN; in signed-in mode it reads the user's real permissions.
final seerrPermissionsProvider = FutureProvider.autoDispose<int>((ref) async {
  final prefs = ref.watch(preferencesProvider).asData?.value;
  final c = ref.watch(seerrClientProvider);
  if (c == null) return 0;
  if (prefs?.seerrAuthMode != 'cookie') return kSeerrAdmin;
  return await c.myPermissions() ?? 0;
});

/// Quality-profile names for a media type's default server, so request rows can
/// show the profile name. Best-effort: empty if the account can't read it.
final seerrProfileNamesProvider = FutureProvider.autoDispose
    .family<Map<int, String>, String>((ref, mediaType) async {
  final c = ref.watch(seerrClientProvider);
  if (c == null) return const {};
  final servers = await c.servers(mediaType);
  final def = servers.where((s) => !s.is4k).toList();
  if (def.isEmpty) return const {};
  final server = def.firstWhere((s) => s.isDefault, orElse: () => def.first);
  final opts = await c.serverOptions(mediaType, server.id);
  return {for (final p in opts.profiles) p.id: p.name};
});

/// External ratings (RT critics/audience, IMDb) for a Jellyfin item, pulled
/// from Seerr by TMDB id so Jellyfin detail pages can show the same scores as
/// Seerr. Returns null when Seerr isn't configured or the lookup fails.
typedef ExternalRatings = ({int? rtCritic, int? rtAudience, double? imdb});

final jellyfinItemRatingsProvider = FutureProvider.autoDispose
    .family<ExternalRatings?, ({String mediaType, int tmdbId})>((ref, key) async {
  final c = ref.watch(seerrClientProvider);
  if (c == null) return null;
  final r = await c.ratingsFor(mediaType: key.mediaType, tmdbId: key.tmdbId);
  if (r == null) return null;
  return (rtCritic: r.$1, rtAudience: r.$2, imdb: r.$3);
});

/// The MDBList client, or null when no API key is set. Depends only on the key
/// so unrelated preference changes don't rebuild it.
final mdbListClientProvider = Provider<MdbListClient?>((ref) {
  final key = ref.watch(
      preferencesProvider.select((a) => a.asData?.value.mdbListApiKey ?? ''));
  if (key.isEmpty) return null;
  return MdbListClient(key);
});

/// Aggregated MDBList ratings (Letterboxd, Metacritic, Trakt, and gap-fill for
/// RT/IMDb/TMDB) for a title, keyed by TMDB id + type. Null when no key or the
/// lookup fails.
final mdbListRatingsProvider = FutureProvider.autoDispose
    .family<MdbRatings?, ({String mediaType, int tmdbId})>((ref, key) async {
  final c = ref.watch(mdbListClientProvider);
  if (c == null) return null;
  return c.ratings(mediaType: key.mediaType, tmdbId: key.tmdbId);
});

final seerrTrendingProvider =
    FutureProvider.autoDispose<List<SeerrResult>>((ref) async {
  final c = ref.watch(seerrClientProvider);
  return c == null ? const [] : c.trending();
});

final seerrMoviesProvider =
    FutureProvider.autoDispose<List<SeerrResult>>((ref) async {
  final c = ref.watch(seerrClientProvider);
  return c == null ? const [] : c.popularMovies();
});

final seerrTvProvider =
    FutureProvider.autoDispose<List<SeerrResult>>((ref) async {
  final c = ref.watch(seerrClientProvider);
  return c == null ? const [] : c.popularTv();
});

final seerrUpcomingMoviesProvider =
    FutureProvider.autoDispose<List<SeerrResult>>((ref) async {
  final c = ref.watch(seerrClientProvider);
  return c == null ? const [] : c.upcomingMovies();
});

final seerrUpcomingTvProvider =
    FutureProvider.autoDispose<List<SeerrResult>>((ref) async {
  final c = ref.watch(seerrClientProvider);
  return c == null ? const [] : c.upcomingTv();
});

final seerrRecentlyAddedProvider =
    FutureProvider.autoDispose<List<SeerrMediaRef>>((ref) async {
  final c = ref.watch(seerrClientProvider);
  return c == null ? const [] : c.recentlyAdded();
});

final seerrMovieGenresProvider =
    FutureProvider.autoDispose<List<SeerrGenre>>((ref) async {
  final c = ref.watch(seerrClientProvider);
  return c == null ? const [] : c.genreSlider('movie');
});

final seerrTvGenresProvider =
    FutureProvider.autoDispose<List<SeerrGenre>>((ref) async {
  final c = ref.watch(seerrClientProvider);
  return c == null ? const [] : c.genreSlider('tv');
});

/// Titles of one genre, for the category screen opened from a genre tile.
final seerrGenreResultsProvider = FutureProvider.autoDispose
    .family<List<SeerrResult>, ({String mediaType, int genreId, String? sortBy})>(
        (ref, k) async {
  final c = ref.watch(seerrClientProvider);
  return c == null
      ? const []
      : c.discoverByGenre(k.mediaType, k.genreId, sortBy: k.sortBy);
});

/// Titles from one studio (movies) or network (tv), for the screen opened from
/// a company card. [kind] is 'studio' or 'network'.
final seerrCompanyResultsProvider = FutureProvider.autoDispose
    .family<List<SeerrResult>, ({String kind, int id, String? sortBy})>(
        (ref, k) async {
  final c = ref.watch(seerrClientProvider);
  if (c == null) return const [];
  return k.kind == 'network'
      ? c.discoverByNetwork(k.id, sortBy: k.sortBy)
      : c.discoverByStudio(k.id, sortBy: k.sortBy);
});

/// Results for a free-text keyword, for custom Discover sliders.
final seerrKeywordProvider =
    FutureProvider.autoDispose.family<List<SeerrResult>, String>((ref, q) async {
  final c = ref.watch(seerrClientProvider);
  if (c == null || q.trim().isEmpty) return const [];
  return c.search(q).then((r) => r.where((x) => x.mediaType != 'person').toList());
});

/// The Requests view controls, mirroring Jellyseerr: a status filter, a media
/// type, a sort field and a sort direction.
class SeerrRequestFilter extends Notifier<String> {
  @override
  String build() => 'pending'; // Jellyseerr's default
  void set(String v) => state = v;
}

final seerrRequestFilterProvider =
    NotifierProvider<SeerrRequestFilter, String>(SeerrRequestFilter.new);

class SeerrRequestMediaType extends Notifier<String> {
  @override
  String build() => 'all';
  void set(String v) => state = v;
}

final seerrRequestMediaTypeProvider =
    NotifierProvider<SeerrRequestMediaType, String>(SeerrRequestMediaType.new);

class SeerrRequestSort extends Notifier<String> {
  @override
  String build() => 'added';
  void set(String v) => state = v;
}

final seerrRequestSortProvider =
    NotifierProvider<SeerrRequestSort, String>(SeerrRequestSort.new);

class SeerrRequestSortDir extends Notifier<String> {
  @override
  String build() => 'desc';
  void toggle() => state = state == 'asc' ? 'desc' : 'asc';
}

final seerrRequestSortDirProvider =
    NotifierProvider<SeerrRequestSortDir, String>(SeerrRequestSortDir.new);

final seerrRequestsProvider =
    FutureProvider.autoDispose<List<SeerrRequest>>((ref) async {
  final c = ref.watch(seerrClientProvider);
  final filter = ref.watch(seerrRequestFilterProvider);
  final mediaType = ref.watch(seerrRequestMediaTypeProvider);
  final sort = ref.watch(seerrRequestSortProvider);
  final dir = ref.watch(seerrRequestSortDirProvider);
  return c == null
      ? const []
      : c.requests(
          filter: filter, mediaType: mediaType, sort: sort, sortDirection: dir);
});

/// The newest requests, for the Discover "Recent Requests" row. Separate from
/// the Requests tab so its filter chips don't reshape the home row.
final seerrRecentRequestsProvider =
    FutureProvider.autoDispose<List<SeerrRequest>>((ref) async {
  final c = ref.watch(seerrClientProvider);
  return c == null ? const [] : c.requests(take: 20);
});

/// How many waiting requests are asked for at a time.
const seerrPendingPage = 100;

/// How many of the waiting requests are asked for: Load More raises it,
/// and the list puts it back to one page as it goes away. (The section's
/// count keeps the requests, and so this, alive long after the list.)
class SeerrPendingLimit extends Notifier<int> {
  @override
  int build() => seerrPendingPage;
  void more() => state += seerrPendingPage;

  /// Safe once the section itself is gone too.
  void reset() {
    if (ref.mounted) state = seerrPendingPage;
  }
}

final seerrPendingLimitProvider =
    NotifierProvider.autoDispose<SeerrPendingLimit, int>(
        SeerrPendingLimit.new);

/// The requests waiting for a yes or no, with how many wait in all.
typedef SeerrPending = ({List<SeerrRequest> requests, int total});

/// The requests waiting for a yes or no, oldest first (whoever asked first
/// gets an answer first), for the Manage section's Activity tab. A server
/// with more of them than are asked for says how many there are, so the
/// count is the true one and the rest can be asked for.
final seerrPendingRequestsProvider =
    FutureProvider.autoDispose<SeerrPending>((ref) async {
  final c = ref.watch(seerrClientProvider);
  if (c == null) return (requests: const <SeerrRequest>[], total: 0);
  final page = await c.requestsPage(
      take: ref.watch(seerrPendingLimitProvider),
      filter: 'pending',
      sortDirection: 'asc');
  final waiting = page.requests;
  // Seerr is asked for this order; a server too old to take the direction
  // answers newest first, so it's put right here as well.
  DateTime at(SeerrRequest r) =>
      DateTime.tryParse(r.createdAt ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);
  final oldestFirst = waiting.indexed.toList()
    ..sort((a, b) {
      final byAge = at(a.$2).compareTo(at(b.$2));
      // Two of one moment stay as Seerr had them.
      return byAge != 0 ? byAge : a.$1.compareTo(b.$1);
    });
  return (
    requests: [for (final (_, r) in oldestFirst) r],
    total: page.total,
  );
});

/// Whether this account answers requests: Seerr is connected and the account
/// may approve and decline. The last answer stands while the permissions are
/// read again (any saved setting does that), so what hangs on it stays put.
final seerrCanManageRequestsProvider = Provider.autoDispose<bool>((ref) =>
    ref.watch(seerrConfiguredProvider) &&
    seerrCan(ref.watch(seerrPermissionsProvider).value ?? 0,
        kSeerrManageRequests));

/// Live search query for the Discover screen.
class SeerrQuery extends Notifier<String> {
  @override
  String build() => '';
  void set(String v) => state = v;
}

final seerrQueryProvider = NotifierProvider<SeerrQuery, String>(SeerrQuery.new);

final seerrSearchProvider =
    FutureProvider.autoDispose<List<SeerrResult>>((ref) async {
  final c = ref.watch(seerrClientProvider);
  final q = ref.watch(seerrQueryProvider).trim();
  if (c == null || q.isEmpty) return const [];
  return c.search(q);
});

/// Recommendations and similar titles for a detail page, keyed by the title.
final seerrRecommendationsProvider = FutureProvider.autoDispose
    .family<List<SeerrResult>, ({String mediaType, int tmdbId})>(
        (ref, k) async {
  final c = ref.watch(seerrClientProvider);
  return c == null ? const [] : c.recommendations(k.mediaType, k.tmdbId);
});

final seerrSimilarProvider = FutureProvider.autoDispose
    .family<List<SeerrResult>, ({String mediaType, int tmdbId})>(
        (ref, k) async {
  final c = ref.watch(seerrClientProvider);
  return c == null ? const [] : c.similar(k.mediaType, k.tmdbId);
});

/// A movie collection (franchise), keyed by collection id.
final seerrCollectionProvider =
    FutureProvider.autoDispose.family<SeerrCollection, int>((ref, id) async {
  final c = ref.watch(seerrClientProvider);
  if (c == null) throw StateError('Seerr not configured');
  return c.collection(id);
});

/// Episodes of one season, keyed by (tvId, seasonNumber).
final seerrSeasonProvider = FutureProvider.autoDispose
    .family<List<SeerrEpisode>, ({int tvId, int seasonNumber})>(
        (ref, k) async {
  final c = ref.watch(seerrClientProvider);
  return c == null ? const [] : c.season(k.tvId, k.seasonNumber);
});

/// A person and their appearances, keyed by TMDB person id.
final seerrPersonProvider =
    FutureProvider.autoDispose.family<SeerrPerson, int>((ref, id) async {
  final c = ref.watch(seerrClientProvider);
  if (c == null) throw StateError('Seerr not configured');
  return c.person(id);
});

/// Full detail for a title, keyed by (mediaType, tmdbId).
final seerrDetailProvider = FutureProvider.autoDispose
    .family<SeerrDetail, ({String mediaType, int tmdbId})>((ref, key) async {
  final c = ref.watch(seerrClientProvider);
  if (c == null) throw StateError('Seerr not configured');
  return c.detail(mediaType: key.mediaType, tmdbId: key.tmdbId);
});
