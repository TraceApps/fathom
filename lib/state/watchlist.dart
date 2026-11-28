import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/base_item.dart';
import '../models/session.dart';
import 'providers.dart';
import 'session_controller.dart';
import '../api/jellyfin_client.dart';
import '../l10n/l10n.dart';

/// A single tap, always-there "want to watch" list for things already in your
/// library, distinct from Favorites (which is for what you love, not what's
/// still on your to-do list). Modelled on Netflix's My List: one list per
/// account, newest addition first, and — deliberately, matching Netflix's own
/// behavior — never auto-removed just because you've watched it. You take it
/// off yourself, on purpose.
///
/// Jellyfin has no native "watchlist" field (only IsFavorite), so this is
/// backed by a single hidden Playlist per account, named [kWatchlistName] and
/// resolved by name each time (never a locally-cached id), so it naturally
/// follows whichever account is signed in — exactly like Favorites and
/// Playlists already do — with no extra local storage to keep in sync across
/// devices or a multi-account switch. It's excluded from the regular Playlists
/// screen so it never shows up twice or invites manual mismanagement there.
class WatchlistController extends AsyncNotifier<List<BaseItemDto>> {
  static const kWatchlistName = 'Fathom Watchlist';

  // Cached once resolved so repeated add/remove calls don't re-list every
  // playlist on the server each time; cleared implicitly on session change
  // since a fresh controller instance is created for a new session.
  String? _playlistId;

  // The playlist's own entries behind each title shown: one for a movie,
  // every episode of a show (see [build]). Replaced whole when a build
  // finishes, so a removal made while the list reloads still finds the
  // entries of the list on screen.
  Map<String, List<String>> _entries = const {};
  // Which build is newest: one still running when another starts mustn't
  // put its older entries in place afterwards.
  int _build = 0;

  /// A show can't sit in a Jellyfin playlist as itself: 10.10 and later put
  /// every one of its episodes in its place, and 10.8 adds nothing. So a
  /// show is kept as one of its episodes, and any episodes in the playlist
  /// (one standing for its show, or the whole run a show was turned into
  /// before) are shown as their show, once, where the newest of them is.
  @override
  Future<List<BaseItemDto>> build() async {
    final build = ++_build;
    final session = ref.watch(sessionControllerProvider).asData?.value;
    if (session == null) {
      _entries = const {};
      return const [];
    }
    final id = await _findPlaylistId(session);
    _playlistId = id;
    if (id == null) {
      if (build == _build) _entries = const {};
      return const [];
    }
    final client = ref.read(jellyfinClientProvider);
    final items = await client.getPlaylistItems(
      baseUrl: session.baseUrl,
      userId: session.userId,
      token: session.accessToken,
      playlistId: id,
    );
    // Newest addition first, matching Netflix's My List ordering (Jellyfin
    // appends new entries to the end).
    final order = <String>[];
    final firstSeen = <String, BaseItemDto>{};
    final showIds = <String>{};
    final entries = <String, List<String>>{};
    for (final e in items.reversed) {
      final show = e.isEpisode ? e.seriesId : null;
      final key = show ?? e.id;
      if (show != null) showIds.add(show);
      if (!entries.containsKey(key)) {
        order.add(key);
        firstSeen[key] = e;
      }
      final entry = e.playlistItemId;
      (entries[key] ??= []).addAll([?entry]);
    }
    final shows = showIds.isEmpty
        ? const <BaseItemDto>[]
        : await client.getItemsByIds(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
            ids: showIds.toList(),
          );
    final showById = {for (final s in shows) s.id: s};
    final shown = <BaseItemDto>[];
    final byShownId = <String, List<String>>{};
    for (final key in order) {
      // A show the server no longer has keeps its episode, so it can still
      // be seen and taken off (its entries go under the id shown).
      final item = showById[key] ?? firstSeen[key]!;
      shown.add(item);
      byShownId[item.id] = entries[key]!;
    }
    if (build == _build) _entries = byShownId;
    return shown;
  }

  Future<String?> _findPlaylistId(Session session) async {
    final client = ref.read(jellyfinClientProvider);
    final playlists = await client.getPlaylists(
      baseUrl: session.baseUrl,
      userId: session.userId,
      token: session.accessToken,
    );
    for (final p in playlists) {
      if (p.name == kWatchlistName) return p.id;
    }
    return null;
  }

  /// Finds the hidden playlist, creating it on first-ever use. Never called
  /// just to check status (only when actually adding something), so opening
  /// the Watchlist screen or checking membership never creates an empty
  /// playlist on the server for someone who's never used the feature.
  Future<String> _ensurePlaylistId(Session session) async {
    final existing = _playlistId;
    if (existing != null) return existing;
    final found = await _findPlaylistId(session);
    if (found != null) {
      _playlistId = found;
      return found;
    }
    final client = ref.read(jellyfinClientProvider);
    final created = await client.createPlaylist(
      baseUrl: session.baseUrl,
      userId: session.userId,
      token: session.accessToken,
      name: kWatchlistName,
    );
    _playlistId = created;
    return created;
  }

  /// The id the Watchlist keeps for [item]: a movie or show itself, an
  /// episode's show (so the Movie Night Wheel only ever lands on something to
  /// sit down and watch), and null for anything else (music, people,
  /// collections), which the Watchlist doesn't take.
  static String? entryIdFor(BaseItemDto item) => switch (item.type) {
        'Movie' || 'Series' => item.id,
        'Episode' => item.seriesId,
        _ => null,
      };

  /// The list once it has loaded (now, when it already has).
  Future<List<BaseItemDto>> loaded() => future;

  bool isInWatchlist(String itemId) =>
      (state.asData?.value ?? const []).any((e) => e.id == itemId);

  /// Adds [item], or for an episode its show. Does nothing for anything the
  /// Watchlist doesn't take, or what's already on it.
  Future<void> add(BaseItemDto item) async {
    final id = entryIdFor(item);
    if (id == null) return;
    // Against the list as it is, not as far as it had loaded: a second
    // entry for something already on it would otherwise slip in.
    await future;
    if (isInWatchlist(id)) return;
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final client = ref.read(jellyfinClientProvider);
    // A show goes in as one episode standing for it (see [build]): the
    // episode itself, or for the show its first one.
    var entry = item.isEpisode ? item.id : id;
    if (item.isSeries) {
      final episodes = await client.getEpisodes(
        baseUrl: session.baseUrl,
        userId: session.userId,
        token: session.accessToken,
        seriesId: item.id,
      );
      if (episodes.isEmpty) throw JellyfinException(tr.errShowNoEpisodes);
      entry = episodes.first.id;
    }
    final playlistId = await _ensurePlaylistId(session);
    await client.addToPlaylist(
      baseUrl: session.baseUrl,
      userId: session.userId,
      token: session.accessToken,
      playlistId: playlistId,
      itemIds: [entry],
    );
    ref.invalidateSelf();
    await future;
  }

  /// Takes [itemId] off: a movie's entry, or every episode of a show.
  Future<void> remove(String itemId) async {
    final session = ref.read(sessionControllerProvider).asData?.value;
    final playlistId = _playlistId;
    if (session == null || playlistId == null) return;
    final entryIds = _entries[itemId] ?? const <String>[];
    if (entryIds.isEmpty) return;
    final client = ref.read(jellyfinClientProvider);
    // In batches, so a show that was turned into hundreds of episodes still
    // fits in a request's address.
    for (var i = 0; i < entryIds.length; i += 100) {
      final end = i + 100 > entryIds.length ? entryIds.length : i + 100;
      await client.removeFromPlaylist(
        baseUrl: session.baseUrl,
        token: session.accessToken,
        playlistId: playlistId,
        entryIds: entryIds.sublist(i, end),
      );
    }
    ref.invalidateSelf();
    await future;
  }
}

final watchlistProvider =
    AsyncNotifierProvider<WatchlistController, List<BaseItemDto>>(
        WatchlistController.new);
