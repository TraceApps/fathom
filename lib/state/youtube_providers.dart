import 'dart:async';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../api/error_text.dart';
import '../l10n/l10n.dart';
import '../models/youtube_channel.dart';
import '../models/youtube_history.dart';
import '../models/youtube_video.dart';
import '../models/youtube_watch.dart';
import '../models/youtube_comment.dart';
import '../models/youtube_playlist.dart';
import '../models/youtube_local_playlist.dart';
import '../models/youtube_feed_group.dart';
import '../services/youtube_innertube.dart';
import '../services/youtube_search_params.dart';
import '../models/youtube_download.dart';
import '../services/youtube_download.dart';
import '../services/diagnostics.dart';
import '../services/shared_files.dart';
import '../services/sponsorblock.dart';
import '../models/app_notification.dart';
import 'notifications_controller.dart';
import 'preferences.dart';
import 'providers.dart';

/// True when the user has switched the YouTube section on.
final youtubeEnabledProvider = Provider<bool>((ref) =>
    ref.watch(preferencesProvider).asData?.value.youtubeEnabled ?? false);

/// [YoutubeScreen]'s Downloads tab index (Search, Subscriptions, What's New,
/// Playlists, Downloads, History) — the one place anything deep-linking to it
/// (the floating pill, the download-complete notification) needs to agree on.
const kYoutubeDownloadsTabIndex = 4;

/// A shared extractor client, closed with the provider. Used only for
/// search-suggestion lookups now; the What's New feed and channel listings go
/// through InnerTube directly (see [YoutubeInnerTube]).
final youtubeClientProvider = Provider<YoutubeExplode>((ref) {
  final yt = YoutubeExplode();
  ref.onDispose(yt.close);
  return yt;
});

/// Search and the watch page go through InnerTube directly (see
/// [YoutubeInnerTube]); the library's own search parser crashes on any result
/// set containing a channel.
/// Watches the language/country prefs, so changing either rebuilds the client
/// and every dependent search refetches on its own.
final youtubeInnerTubeProvider = Provider<YoutubeInnerTube>((ref) {
  // Depend ONLY on the three fields this client uses. Watching the whole Prefs
  // rebuilt the client on any pref change (e.g. saving the volume), which
  // invalidated the watch-page data provider and refetched the whole page,
  // flashing a reload every time the volume changed.
  final (language, country, restricted) =
      ref.watch(preferencesProvider.select((async) {
    final p = async.asData?.value;
    return (
      p?.youtubeContentLanguage ?? 'en',
      p?.youtubeContentCountry ?? 'US',
      p?.youtubeRestrictedMode ?? false,
    );
  }));
  return YoutubeInnerTube(
    language: language,
    country: country,
    restrictedMode: restricted,
  );
});

/// Accumulated search results for a query, with paging.
class YoutubeSearchResults {
  final List<YoutubeVideo> videos;
  final List<YoutubeChannel> channels;
  final List<YoutubePlaylist> playlists;
  final bool loadingMore;
  final bool hasMore;
  const YoutubeSearchResults({
    this.videos = const [],
    this.channels = const [],
    this.playlists = const [],
    this.loadingMore = false,
    this.hasMore = false,
  });

  bool get isEmpty => videos.isEmpty && channels.isEmpty && playlists.isEmpty;

  YoutubeSearchResults copyWith({
    List<YoutubeVideo>? videos,
    List<YoutubeChannel>? channels,
    List<YoutubePlaylist>? playlists,
    bool? loadingMore,
    bool? hasMore,
  }) =>
      YoutubeSearchResults(
        videos: videos ?? this.videos,
        channels: channels ?? this.channels,
        playlists: playlists ?? this.playlists,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
      );
}

/// Everything the Search tab is asking for: what kind, in what order, and
/// narrowed how.
class YoutubeSearchQuery {
  final YtSearchFilter filter;
  final YtSearchSort sort;
  final YtUploadDate uploadDate;
  final YtDuration duration;

  const YoutubeSearchQuery({
    this.filter = YtSearchFilter.videos,
    this.sort = YtSearchSort.relevance,
    this.uploadDate = YtUploadDate.any,
    this.duration = YtDuration.any,
  });

  /// Sort/date/duration only apply to videos, so they don't count as active
  /// narrowing when browsing channels or playlists.
  int get activeCount =>
      filter != YtSearchFilter.videos
          ? 0
          : [
              sort != YtSearchSort.relevance,
              uploadDate != YtUploadDate.any,
              duration != YtDuration.any,
            ].where((e) => e).length;

  YoutubeSearchQuery copyWith({
    YtSearchFilter? filter,
    YtSearchSort? sort,
    YtUploadDate? uploadDate,
    YtDuration? duration,
  }) =>
      YoutubeSearchQuery(
        filter: filter ?? this.filter,
        sort: sort ?? this.sort,
        uploadDate: uploadDate ?? this.uploadDate,
        duration: duration ?? this.duration,
      );
}

class YoutubeSearchFilterNotifier extends Notifier<YoutubeSearchQuery> {
  @override
  YoutubeSearchQuery build() => const YoutubeSearchQuery();

  void set(YtSearchFilter f) => state = state.copyWith(filter: f);
  void setSort(YtSearchSort s) => state = state.copyWith(sort: s);
  void setUploadDate(YtUploadDate d) => state = state.copyWith(uploadDate: d);
  void setDuration(YtDuration d) => state = state.copyWith(duration: d);
  void reset() => state = YoutubeSearchQuery(filter: state.filter);
}

final youtubeSearchFilterProvider =
    NotifierProvider<YoutubeSearchFilterNotifier, YoutubeSearchQuery>(
        YoutubeSearchFilterNotifier.new);

/// Results for the active query, appending further pages on demand. Tracks
/// [youtubeQueryProvider], so a new search simply rebuilds it. There's only one
/// search box, so this doesn't need to be a family.
class YoutubeSearch extends AsyncNotifier<YoutubeSearchResults> {
  String? _continuation;

  @override
  Future<YoutubeSearchResults> build() async {
    final q = ref.watch(youtubeQueryProvider).trim();
    // Watched, so changing any filter re-runs the search on its own.
    final f = ref.watch(youtubeSearchFilterProvider);
    _continuation = null;
    if (q.isEmpty) return const YoutubeSearchResults();
    final page = await ref.watch(youtubeInnerTubeProvider).search(
          q,
          filter: f.filter,
          sort: f.sort,
          uploadDate: f.uploadDate,
          duration: f.duration,
        );
    _continuation = page.continuation;
    return YoutubeSearchResults(
      videos: page.videos,
      channels: page.channels,
      playlists: page.playlists,
      hasMore: page.continuation != null,
    );
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    final token = _continuation;
    if (current == null || token == null || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref.read(youtubeInnerTubeProvider).searchMore(token);
      _continuation = page.continuation;
      state = AsyncData(YoutubeSearchResults(
        videos: [...current.videos, ...page.videos],
        channels: [...current.channels, ...page.channels],
        playlists: [...current.playlists, ...page.playlists],
        hasMore: page.continuation != null && !page.isEmpty,
      ));
    } catch (_) {
      // Keep what we have; just stop the spinner.
      state = AsyncData(current.copyWith(loadingMore: false));
    }
  }
}

final youtubeSearchProvider =
    AsyncNotifierProvider<YoutubeSearch, YoutubeSearchResults>(
        YoutubeSearch.new);

/// Metadata + related videos for the watch page.
/// Keeps an autoDispose provider's result cached for [ttl] after its last
/// listener goes away, then releases it. Returning to a watch page you just
/// minimized then reopened is instant instead of refetching the title, related
/// videos and comments every time; genuinely stale pages still fall away.
void _cacheFor(Ref ref, Duration ttl) {
  final link = ref.keepAlive();
  Timer? evict;
  ref.onDispose(() => evict?.cancel());
  ref.onCancel(() => evict = Timer(ttl, link.close));
  ref.onResume(() => evict?.cancel());
}

final youtubeWatchProvider = FutureProvider.autoDispose
    .family<YoutubeWatchDetails, String>((ref, videoId) async {
  _cacheFor(ref, const Duration(minutes: 5));
  return ref.watch(youtubeInnerTubeProvider).watch(videoId);
});

/// Top-level comments for a token taken from the watch page.
/// Comments, accumulated page by page.
///
/// Each response carries a continuation token for the next page, so the state
/// keeps every comment loaded so far alongside the token to ask for more.
class YoutubeCommentsState {
  final List<YoutubeComment> comments;
  final String countLabel;
  final bool hasMore;
  final bool loadingMore;

  const YoutubeCommentsState({
    this.comments = const [],
    this.countLabel = '',
    this.hasMore = false,
    this.loadingMore = false,
  });

  YoutubeCommentsState copyWith({
    List<YoutubeComment>? comments,
    String? countLabel,
    bool? hasMore,
    bool? loadingMore,
  }) =>
      YoutubeCommentsState(
        comments: comments ?? this.comments,
        countLabel: countLabel ?? this.countLabel,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

class YoutubeComments extends AsyncNotifier<YoutubeCommentsState> {
  YoutubeComments(this.token);
  final String token;

  String? _next;

  @override
  Future<YoutubeCommentsState> build() async {
    // Cached briefly so reopening a just-minimized watch page keeps its loaded
    // comments (and how far you'd paged in) instead of reloading from scratch.
    _cacheFor(ref, const Duration(minutes: 5));
    final page = await ref.watch(youtubeInnerTubeProvider).comments(token);
    _next = page.continuation;
    return YoutubeCommentsState(
      comments: page.comments,
      countLabel: page.countLabel,
      hasMore: _next != null,
    );
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    final next = _next;
    if (current == null || current.loadingMore || next == null) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref.read(youtubeInnerTubeProvider).comments(next);
      _next = page.continuation;
      state = AsyncData(current.copyWith(
        comments: [...current.comments, ...page.comments],
        hasMore: _next != null,
        loadingMore: false,
      ));
    } catch (_) {
      // A failed page shouldn't discard the comments already on screen.
      state = AsyncData(current.copyWith(hasMore: false, loadingMore: false));
    }
  }
}

final youtubeCommentsProvider = AsyncNotifierProvider.autoDispose
    .family<YoutubeComments, YoutubeCommentsState, String>(YoutubeComments.new);

/// A comment's replies, fetched on demand when the user expands them. Keyed on
/// the comment's reply continuation token; follows pagination so all replies
/// load (capped for safety).
final youtubeCommentRepliesProvider = FutureProvider.autoDispose
    .family<List<YoutubeComment>, String>((ref, token) async {
  final client = ref.watch(youtubeInnerTubeProvider);
  final all = <YoutubeComment>[];
  String? tok = token;
  var guard = 0;
  while (tok != null && guard < 20) {
    final page = await client.commentReplies(tok);
    all.addAll(page.comments);
    tok = page.continuation;
    guard++;
  }
  return all;
});

/// Likes and dislikes from Return YouTube Dislike (likes are YouTube's real
/// count; dislikes are crowd-estimated). Null when the setting is off or the
/// lookup fails. Best-effort third-party call.
final returnYtDislikesProvider = FutureProvider.autoDispose
    .family<({int likes, int dislikes})?, String>((ref, videoId) async {
  final on = ref.watch(preferencesProvider
      .select((a) => a.asData?.value.youtubeReturnDislikes ?? true));
  if (!on) return null;
  try {
    final res = await Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    )).get<Map<String, dynamic>>(
      'https://returnyoutubedislikeapi.com/votes',
      queryParameters: {'videoId': videoId},
    );
    final d = res.data;
    final likes = (d?['likes'] as num?)?.toInt();
    final dislikes = (d?['dislikes'] as num?)?.toInt();
    if (likes == null && dislikes == null) return null;
    return (likes: likes ?? 0, dislikes: dislikes ?? 0);
  } catch (_) {
    return null;
  }
});

/// A crowd-sourced, non-clickbait title from DeArrow, or null when off / none.
/// Prefers a locked title, else the most-upvoted non-original one.
final deArrowTitleProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, videoId) async {
  final on = ref.watch(
      preferencesProvider.select((a) => a.asData?.value.youtubeDeArrow ?? false));
  if (!on) return null;
  try {
    final res = await Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    )).get<Map<String, dynamic>>(
      'https://sponsor.ajay.app/api/branding',
      queryParameters: {'videoID': videoId},
    );
    final titles = res.data?['titles'];
    if (titles is! List) return null;
    Map? best;
    for (final t in titles) {
      if (t is! Map || t['original'] == true) continue;
      final title = t['title'];
      if (title is! String || title.isEmpty) continue;
      if (t['locked'] == true) return title;
      final votes = (t['votes'] as num?)?.toInt() ?? 0;
      if (votes < 0) continue;
      if (best == null || votes > ((best['votes'] as num?)?.toInt() ?? 0)) {
        best = t;
      }
    }
    return best?['title'] as String?;
  } catch (_) {
    return null;
  }
});

/// Search-as-you-type suggestions from YouTube.
final youtubeSuggestionsProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, query) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final yt = ref.watch(youtubeClientProvider);
  try {
    return await yt.search.getQuerySuggestions(q);
  } catch (_) {
    return const [];
  }
});

/// The active YouTube search query.
class YoutubeQuery extends Notifier<String> {
  @override
  String build() => '';
  void set(String q) => state = q;
}

final youtubeQueryProvider =
    NotifierProvider<YoutubeQuery, String>(YoutubeQuery.new);


/// A paged list of videos (channel uploads), with more available on demand.
class YoutubeUploads {
  final List<YoutubeVideo> videos;
  final bool loadingMore;
  final bool hasMore;
  const YoutubeUploads({
    this.videos = const [],
    this.loadingMore = false,
    this.hasMore = false,
  });

  YoutubeUploads copyWith({
    List<YoutubeVideo>? videos,
    bool? loadingMore,
    bool? hasMore,
  }) =>
      YoutubeUploads(
        videos: videos ?? this.videos,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
      );
}

/// A channel's uploads, newest first.
///
/// Listings arrive as ids with no metadata, and each video costs a request to
/// fill in, so ids are buffered and hydrated a chunk at a time rather than all
/// at once. When the buffer runs dry the next listing page is fetched.
class YoutubeChannelUploads extends AsyncNotifier<YoutubeUploads> {
  YoutubeChannelUploads(this.channelId);
  final String channelId;

  // Paged through the InnerTube browse endpoint, not youtube_explode. Browse
  // returns full video metadata (title, duration, views, date) per page in a
  // single request, so a channel costs one request per page instead of the
  // dozen-per-page that the youtube_explode path needed (list items there are
  // partial, so each had to be re-fetched, which tripped YouTube's rate limit
  // and broke both paging and playback).
  String? _continuation;

  @override
  Future<YoutubeUploads> build() async {
    final yt = ref.watch(youtubeInnerTubeProvider);
    final tab = await yt.channelTab(channelId, YtChannelTabKind.videos);
    var videos = tab.videos;
    var token = tab.continuation;
    // Some channels (mostly-Shorts or made-for-kids ones) hand back a tiny first
    // page plus a continuation that then returns nothing. Pull a few more pages
    // up front so the tab doesn't strand a couple of videos under an endless
    // "loading more" spinner — the short list can never scroll to trigger the
    // page that would resolve it.
    var guard = 0;
    while (videos.length < 10 && token != null && guard < 3) {
      guard++;
      final more = await yt.channelTabMore(token);
      if (more.videos.isEmpty) {
        token = null;
        break;
      }
      videos = [...videos, ...more.videos];
      token = more.continuation;
    }
    _continuation = token;
    return YoutubeUploads(videos: videos, hasMore: token != null);
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    final token = _continuation;
    if (current == null ||
        current.loadingMore ||
        !current.hasMore ||
        token == null) {
      return;
    }
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page =
          await ref.read(youtubeInnerTubeProvider).channelTabMore(token);
      _continuation = page.continuation;
      state = AsyncData(YoutubeUploads(
        videos: [...current.videos, ...page.videos],
        hasMore: page.continuation != null && page.videos.isNotEmpty,
      ));
    } catch (_) {
      // A transient continuation error shouldn't end paging for good; keep
      // hasMore true so the next scroll retries instead of stalling.
      state = AsyncData(current.copyWith(loadingMore: false));
    }
  }
}

final youtubeChannelUploadsProvider = AsyncNotifierProvider.autoDispose
    .family<YoutubeChannelUploads, YoutubeUploads, String>(
        YoutubeChannelUploads.new);

/// Locally-stored channel subscriptions. No Google account involved: this is
/// just a list of channels kept on this device.
class YoutubeSubscriptions extends AsyncNotifier<List<YoutubeChannel>> {
  static const _key = 'fathom_youtube_subs';

  @override
  Future<List<YoutubeChannel>> build() async {
    final raw = await ref.read(secureStorageProvider).read(key: _key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list.whereType<Map>())
          YoutubeChannel.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist(List<YoutubeChannel> next) async {
    await ref.read(secureStorageProvider).write(
        key: _key, value: jsonEncode([for (final c in next) c.toJson()]));
    state = AsyncData(next);
  }

  bool isSubscribed(String channelId) =>
      (state.asData?.value ?? const []).any((c) => c.id == channelId);

  Future<void> subscribe(YoutubeChannel channel) async {    // build() reads storage and can land after this, overwriting
    // anything set in the meantime. Callers reach these through
    // ref.read(...notifier), which does not wait for it.
    await future;

    final current = state.asData?.value ?? const <YoutubeChannel>[];
    if (current.any((c) => c.id == channel.id)) return;
    await _persist([...current, channel]
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())));
  }

  Future<void> unsubscribe(String channelId) async {    // build() reads storage and can land after this, overwriting
    // anything set in the meantime. Callers reach these through
    // ref.read(...notifier), which does not wait for it.
    await future;

    // Drop it from any feed groups too, or the id lingers and quietly filters
    // that group's feed against a channel that isn't there any more.
    unawaited(ref.read(youtubeFeedGroupsProvider.notifier)
        .forgetChannel(channelId));
    final current = state.asData?.value ?? const <YoutubeChannel>[];
    await _persist([
      for (final c in current)
        if (c.id != channelId) c,
    ]);
  }

  Future<void> toggle(YoutubeChannel channel) => isSubscribed(channel.id)
      ? unsubscribe(channel.id)
      : subscribe(channel);

  /// Merges imported channels in, keeping what's already here.
  ///
  /// Existing entries win: they may carry an avatar and subscriber count that
  /// an import file doesn't have, and overwriting them would strip the list
  /// back to bare names. Returns how many were actually new.
  Future<int> importAll(List<YoutubeChannel> channels) async {    // build() reads storage and can land after this, overwriting
    // anything set in the meantime. Callers reach these through
    // ref.read(...notifier), which does not wait for it.
    await future;

    final current = state.asData?.value ?? const <YoutubeChannel>[];
    final byId = {for (final c in current) c.id: c};
    var added = 0;
    for (final c in channels) {
      if (byId.containsKey(c.id)) continue;
      byId[c.id] = c;
      added++;
    }
    if (added == 0) return 0;
    final next = byId.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    await _persist(next);
    return added;
  }
}

final youtubeSubscriptionsProvider =
    AsyncNotifierProvider<YoutubeSubscriptions, List<YoutubeChannel>>(
        YoutubeSubscriptions.new);

/// Locally-stored watch history and resume positions. Nothing leaves the
/// device, and nothing is reported back to YouTube.
class YoutubeHistory extends AsyncNotifier<List<YoutubeHistoryEntry>> {
  static const _key = 'fathom_youtube_history';
  static const _max = 200; // keep the list (and the stored blob) bounded

  @override
  Future<List<YoutubeHistoryEntry>> build() async {
    final raw = await ref.read(secureStorageProvider).read(key: _key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list.whereType<Map>())
          YoutubeHistoryEntry.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist(List<YoutubeHistoryEntry> next) async {
    final trimmed = next.take(_max).toList();
    await ref.read(secureStorageProvider).write(
        key: _key, value: jsonEncode([for (final e in trimmed) e.toJson()]));
    state = AsyncData(trimmed);
  }

  YoutubeHistoryEntry? entryFor(String videoId) {
    for (final e in state.asData?.value ?? const <YoutubeHistoryEntry>[]) {
      if (e.id == videoId) return e;
    }
    return null;
  }

  /// Records progress, moving the video to the front of the history.
  /// Records a view. A no-op when watch history is off — off means it isn't
  /// written, not that it's written and hidden.
  Future<void> record({
    required String videoId,
    required String title,
    required String author,
    String? channelId,
    required Duration position,
    required Duration duration,
    required DateTime now,
  }) async {
    // build() reads storage and can land after this, overwriting
    // anything set in the meantime. Callers reach these through
    // ref.read(...notifier), which does not wait for it.
    await future;
    final prefs = ref.read(preferencesProvider).asData?.value;
    if (prefs != null && !prefs.youtubeKeepWatchHistory) return;
    final current = state.asData?.value ?? const <YoutubeHistoryEntry>[];
    final existing = entryFor(videoId);
    final entry = YoutubeHistoryEntry(
      id: videoId,
      // Keep whatever we already knew if the caller has nothing better.
      title: title.isNotEmpty ? title : (existing?.title ?? ''),
      author: author.isNotEmpty ? author : (existing?.author ?? ''),
      channelId: channelId ?? existing?.channelId,
      positionSeconds: position.inSeconds,
      durationSeconds:
          duration.inSeconds > 0 ? duration.inSeconds : (existing?.durationSeconds ?? 0),
      watchedAtMs: now.millisecondsSinceEpoch,
    );
    await _persist([
      entry,
      for (final e in current)
        if (e.id != videoId) e,
    ]);
  }

  Future<void> remove(String videoId) async {    // build() reads storage and can land after this, overwriting
    // anything set in the meantime. Callers reach these through
    // ref.read(...notifier), which does not wait for it.
    await future;

    final current = state.asData?.value ?? const <YoutubeHistoryEntry>[];
    await _persist([
      for (final e in current)
        if (e.id != videoId) e,
    ]);
  }

  Future<void> clear() async {
    await future;
    await _persist(const []);
  }
}

final youtubeHistoryProvider =
    AsyncNotifierProvider<YoutubeHistory, List<YoutubeHistoryEntry>>(
        YoutubeHistory.new);

/// Newest uploads across every subscribed channel, most recent first.
/// What every subscribed channel has posted, newest first.
class YoutubeFeedState {
  final List<YoutubeVideo> videos;
  final bool hasMore;
  final bool loadingMore;

  const YoutubeFeedState({
    this.videos = const [],
    this.hasMore = false,
    this.loadingMore = false,
  });

  YoutubeFeedState copyWith({
    List<YoutubeVideo>? videos,
    bool? hasMore,
    bool? loadingMore,
  }) =>
      YoutubeFeedState(
        videos: videos ?? this.videos,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

class YoutubeFeed extends AsyncNotifier<YoutubeFeedState> {
  static const _perChannel = 8;

  /// Each channel's continuation token for the next page. A channel drops out of
  /// the map once it runs out, so later pages only ask the channels with more.
  final Map<String, String> _pages = {};

  @override
  Future<YoutubeFeedState> build() async {
    final all = ref.watch(youtubeSubscriptionsProvider).asData?.value ??
        const <YoutubeChannel>[];
    // Watched, so switching group refetches on its own.
    final groupId = ref.watch(youtubeActiveFeedGroupProvider);
    final groups =
        ref.watch(youtubeFeedGroupsProvider).asData?.value ??
            const <YoutubeFeedGroup>[];
    final group = groupId == null
        ? null
        : groups.where((g) => g.id == groupId).firstOrNull;
    // An unknown or emptied group falls back to everything rather than showing
    // a blank feed with no explanation.
    final subs = (group == null || group.channelIds.isEmpty)
        ? all
        : [for (final c in all) if (group.contains(c.id)) c];

    _pages.clear();
    if (subs.isEmpty) return const YoutubeFeedState();
    final inner = ref.watch(youtubeInnerTubeProvider);

    // Each channel's recent uploads via one small InnerTube browse request (the
    // same fast path the channel screen uses), instead of youtube_explode's
    // getUploadsFromPage, which scraped the whole multi-megabyte channel page
    // once per subscription. One failing channel shouldn't empty the feed.
    final results = await Future.wait([
      for (final c in subs)
        inner
            .channelTab(c.id, YtChannelTabKind.videos)
            .then<(String, YtChannelTab?)>((t) => (c.id, t))
            .catchError((_) => (c.id, null)),
    ]);
    final videos = <YoutubeVideo>[];
    for (final (channelId, tab) in results) {
      if (tab == null) continue;
      final token = tab.continuation;
      if (token != null) _pages[channelId] = token;
      videos.addAll(tab.videos.take(_perChannel));
    }
    // The merged order needs a real date to sort by, but the listing only
    // carries a relative label ("2 days ago"); previously that meant fetching
    // every single video individually (yt.videos.get) just for its exact
    // timestamp. With enough subscriptions that was hundreds of requests,
    // which is what made the feed take minutes and sometimes return empty
    // when YouTube's rate limiter stalled them (issue #38). Approximating the
    // date from the label itself, with no network call, is the fix: sort
    // order is close enough for a merged feed, and the feed now loads exactly
    // as fast as the channel listing calls above.
    return YoutubeFeedState(
      videos: _sorted(_withApproximateDates(videos)),
      hasMore: _pages.isNotEmpty,
    );
  }

  List<YoutubeVideo> _withApproximateDates(List<YoutubeVideo> videos) {
    final now = DateTime.now();
    return [
      for (final v in videos)
        v.uploadDate != null
            ? v
            : _copyWithDate(
                v, YoutubeVideo.approximateUploadDate(v.uploadedLabel, now)),
    ];
  }

  YoutubeVideo _copyWithDate(YoutubeVideo v, DateTime? date) => YoutubeVideo(
        id: v.id,
        title: v.title,
        author: v.author,
        channelId: v.channelId,
        url: v.url,
        thumbnailUrl: v.thumbnailUrl,
        duration: v.duration,
        viewCount: v.viewCount,
        uploadDate: date,
        uploadedLabel: v.uploadedLabel,
        isShort: v.isShort,
      );

  /// Newest first; undated uploads (live streams, mostly) sink to the bottom
  /// rather than claiming the top.
  List<YoutubeVideo> _sorted(List<YoutubeVideo> list) {
    final out = [...list];
    out.sort((a, b) {
      final x = a.uploadDate, y = b.uploadDate;
      if (x == null && y == null) return 0;
      if (x == null) return 1;
      if (y == null) return -1;
      return y.compareTo(x);
    });
    return out;
  }

  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || current.loadingMore || !current.hasMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    final inner = ref.read(youtubeInnerTubeProvider);
    try {
      // Advance every channel that still has a continuation. Uploads come back
      // newest-first per channel, so taking the next page from each and
      // re-sorting keeps the merged order right.
      final next = await Future.wait([
        for (final entry in _pages.entries)
          inner
              .channelTabMore(entry.value)
              .then<(String, YtChannelTab?)>((t) => (entry.key, t))
              .catchError((_) => (entry.key, null)),
      ]);
      final videos = <YoutubeVideo>[];
      for (final (channelId, tab) in next) {
        if (tab == null || tab.videos.isEmpty) {
          _pages.remove(channelId);
          continue;
        }
        final token = tab.continuation;
        if (token != null) {
          _pages[channelId] = token;
        } else {
          _pages.remove(channelId);
        }
        videos.addAll(tab.videos.take(_perChannel));
      }
      final more = _withApproximateDates(videos);
      // Guard against a channel handing back a page it already gave us.
      final seen = {for (final v in current.videos) v.id};
      state = AsyncData(YoutubeFeedState(
        videos: _sorted(
            [...current.videos, ...more.where((v) => !seen.contains(v.id))]),
        hasMore: _pages.isNotEmpty,
      ));
    } catch (_) {
      state = AsyncData(current.copyWith(hasMore: false, loadingMore: false));
    }
  }
}

final youtubeFeedProvider =
    AsyncNotifierProvider.autoDispose<YoutubeFeed, YoutubeFeedState>(
        YoutubeFeed.new);

/// A playlist's videos, in playlist order.
///
/// youtube_explode hands these back fully populated, so unlike channel uploads
/// there's no id-only listing to hydrate afterwards.
final youtubePlaylistProvider = FutureProvider.autoDispose
    .family<List<YoutubeVideo>, String>((ref, playlistId) async {
  // Fetch via InnerTube (browse VL<id>), not youtube_explode: the library
  // returns empty for auto-generated album / mix / "Greatest Hits" playlists,
  // which is exactly what search surfaces.
  return ref.watch(youtubeInnerTubeProvider).playlist(playlistId);
});

/// Playlists you make, stored on this device.
///
/// Same storage approach as subscriptions and history: nothing leaves the
/// machine and no account is involved. Videos are stored whole rather than as
/// ids, so a saved playlist renders instantly and still reads correctly if a
/// video later goes private.
class YoutubeLocalPlaylists extends AsyncNotifier<List<YoutubeLocalPlaylist>> {
  static const _key = 'fathom_youtube_playlists';

  @override
  Future<List<YoutubeLocalPlaylist>> build() async {
    final raw = await ref.read(secureStorageProvider).read(key: _key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list.whereType<Map>())
          YoutubeLocalPlaylist.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist(List<YoutubeLocalPlaylist> next) async {
    await ref.read(secureStorageProvider).write(
        key: _key, value: jsonEncode([for (final p in next) p.toJson()]));
    state = AsyncData(next);
  }

  List<YoutubeLocalPlaylist> get _current => state.asData?.value ?? const [];

  /// Ids are derived from the clock, which is enough for a local list and
  /// avoids a uuid dependency here.
  Future<YoutubeLocalPlaylist> create(String name) async {    // build() reads storage and can land after this, overwriting
    // anything set in the meantime. Callers reach these through
    // ref.read(...notifier), which does not wait for it.
    await future;

    final playlist = YoutubeLocalPlaylist(
      id: 'pl_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Untitled' : name.trim(),
    );
    await _persist([..._current, playlist]);
    return playlist;
  }

  Future<void> rename(String id, String name) async {    // build() reads storage and can land after this, overwriting
    // anything set in the meantime. Callers reach these through
    // ref.read(...notifier), which does not wait for it.
    await future;

    await _persist([
      for (final p in _current)
        if (p.id == id) p.copyWith(name: name.trim()) else p,
    ]);
  }

  Future<void> delete(String id) async {    // build() reads storage and can land after this, overwriting
    // anything set in the meantime. Callers reach these through
    // ref.read(...notifier), which does not wait for it.
    await future;

    await _persist([
      for (final p in _current)
        if (p.id != id) p,
    ]);
  }

  /// Adding a video already in the playlist is a no-op rather than a duplicate.
  Future<void> addVideo(String playlistId, YoutubeVideo video) async {    // build() reads storage and can land after this, overwriting
    // anything set in the meantime. Callers reach these through
    // ref.read(...notifier), which does not wait for it.
    await future;

    await _persist([
      for (final p in _current)
        if (p.id == playlistId && !p.contains(video.id))
          p.copyWith(videos: [...p.videos, video])
        else
          p,
    ]);
  }

  Future<void> removeVideo(String playlistId, String videoId) async {    // build() reads storage and can land after this, overwriting
    // anything set in the meantime. Callers reach these through
    // ref.read(...notifier), which does not wait for it.
    await future;

    await _persist([
      for (final p in _current)
        if (p.id == playlistId)
          p.copyWith(videos: [
            for (final v in p.videos)
              if (v.id != videoId) v,
          ])
        else
          p,
    ]);
  }

  Future<void> reorder(String playlistId, int oldIndex, int newIndex) async {    // build() reads storage and can land after this, overwriting
    // anything set in the meantime. Callers reach these through
    // ref.read(...notifier), which does not wait for it.
    await future;

    await _persist([
      for (final p in _current)
        if (p.id == playlistId)
          p.copyWith(videos: () {
            final vids = [...p.videos];
            if (oldIndex < 0 || oldIndex >= vids.length) return vids;
            final v = vids.removeAt(oldIndex);
            vids.insert(newIndex.clamp(0, vids.length), v);
            return vids;
          }())
        else
          p,
    ]);
  }
}

final youtubeLocalPlaylistsProvider =
    AsyncNotifierProvider<YoutubeLocalPlaylists, List<YoutubeLocalPlaylist>>(
        YoutubeLocalPlaylists.new);

/// The play queue: what to watch after this, in order.
///
/// Deliberately in memory only, unlike subscriptions/history/playlists. A queue
/// is a statement about this sitting, not a library; NewPipe treats it the same
/// way. Playlists are the thing that persists.
class YoutubeQueue extends Notifier<List<YoutubeVideo>> {
  @override
  List<YoutubeVideo> build() => const [];

  // The last full list handed to [playAll], kept so the audio layer can
  // un-shuffle (restore original order) and repeat-all (reload the list).
  List<YoutubeVideo> _source = const [];
  List<YoutubeVideo> get source => _source;

  /// Appended to the end. Adding one that's already queued is a no-op rather
  /// than a duplicate.
  void add(YoutubeVideo video) {
    if (state.any((v) => v.id == video.id)) return;
    state = [...state, video];
  }

  /// Replaces the whole queue — used when starting a playlist from one of its
  /// items, so Next/autoplay then walk the rest of the playlist in order.
  void playAll(List<YoutubeVideo> videos) {
    _source = List.of(videos);
    state = List.of(videos);
  }

  /// Shuffle the remaining up-next (audio Shuffle toggle).
  void shuffleRemaining() => state = [...state]..shuffle();

  /// Restore the remaining up-next to its original [source] order (Shuffle off).
  void restoreOrder() {
    final remaining = state.map((v) => v.id).toSet();
    state = [for (final v in _source) if (remaining.contains(v.id)) v];
  }

  /// Reload the whole source list (audio Repeat-all when the queue runs out).
  void reloadSource() => state = List.of(_source);

  /// Jumps the queue: the next thing to play.
  void playNext(YoutubeVideo video) {
    state = [video, ...state.where((v) => v.id != video.id)];
  }

  void remove(String videoId) =>
      state = [for (final v in state) if (v.id != videoId) v];

  void clear() => state = const [];

  void reorder(int oldIndex, int newIndex) {
    final next = [...state];
    if (oldIndex < 0 || oldIndex >= next.length) return;
    final v = next.removeAt(oldIndex);
    next.insert(newIndex.clamp(0, next.length), v);
    state = next;
  }

  /// Pops the next video off, or null when the queue is empty.
  YoutubeVideo? takeNext() {
    if (state.isEmpty) return null;
    final next = state.first;
    state = state.sublist(1);
    return next;
  }
}

final youtubeQueueProvider =
    NotifierProvider<YoutubeQueue, List<YoutubeVideo>>(YoutubeQueue.new);

/// Recent searches, kept on this device.
///
/// Distinct from the suggestions provider, which asks YouTube what other people
/// search for. This is what YOU searched, and it's the faster route back to a
/// query you ran yesterday.
class YoutubeSearchHistory extends AsyncNotifier<List<String>> {
  static const _key = 'fathom_youtube_search_history';
  static const _max = 30;

  @override
  Future<List<String>> build() async {
    final raw = await ref.read(secureStorageProvider).read(key: _key);
    if (raw == null) return const [];
    try {
      return [...(jsonDecode(raw) as List).whereType<String>()];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist(List<String> next) async {
    await ref
        .read(secureStorageProvider)
        .write(key: _key, value: jsonEncode(next));
    state = AsyncData(next);
  }

  /// Most recent first. Re-running an old search moves it up rather than
  /// adding a duplicate. A no-op when search history is off.
  Future<void> record(String query) async {    // build() reads storage and can land after this, overwriting
    // anything set in the meantime. Callers reach these through
    // ref.read(...notifier), which does not wait for it.
    await future;

    final prefs = ref.read(preferencesProvider).asData?.value;
    if (prefs != null && !prefs.youtubeKeepSearchHistory) return;
    final q = query.trim();
    if (q.isEmpty) return;
    final current = state.asData?.value ?? const <String>[];
    final next = [
      q,
      for (final e in current)
        if (e.toLowerCase() != q.toLowerCase()) e,
    ];
    await _persist(next.take(_max).toList());
  }

  Future<void> remove(String query) async {    // build() reads storage and can land after this, overwriting
    // anything set in the meantime. Callers reach these through
    // ref.read(...notifier), which does not wait for it.
    await future;

    final current = state.asData?.value ?? const <String>[];
    await _persist([
      for (final e in current)
        if (e != query) e,
    ]);
  }

  Future<void> clear() async {
    await future;
    await _persist(const []);
  }
}

final youtubeSearchHistoryProvider =
    AsyncNotifierProvider<YoutubeSearchHistory, List<String>>(
        YoutubeSearchHistory.new);

/// Playlists saved from search: someone else's, kept for later.
///
/// Only the reference is stored, not the contents — the playlist belongs to its
/// owner and keeps changing, so it's fetched fresh when opened. That's the
/// difference between these and local playlists, which are yours and stored
/// whole.
class YoutubeSavedPlaylists extends AsyncNotifier<List<YoutubePlaylist>> {
  static const _key = 'fathom_youtube_saved_playlists';

  @override
  Future<List<YoutubePlaylist>> build() async {
    final raw = await ref.read(secureStorageProvider).read(key: _key);
    if (raw == null) return const [];
    try {
      return [
        for (final e in (jsonDecode(raw) as List).whereType<Map>())
          YoutubePlaylist(
            id: e['id'] as String? ?? '',
            title: e['title'] as String? ?? '',
            thumbnailUrl: e['thumbnailUrl'] as String? ?? '',
            author: e['author'] as String? ?? '',
            videoCountLabel: e['videoCountLabel'] as String? ?? '',
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist(List<YoutubePlaylist> next) async {
    await ref.read(secureStorageProvider).write(
        key: _key,
        value: jsonEncode([
          for (final p in next)
            {
              'id': p.id,
              'title': p.title,
              'thumbnailUrl': p.thumbnailUrl,
              'author': p.author,
              'videoCountLabel': p.videoCountLabel,
            },
        ]));
    state = AsyncData(next);
  }

  bool isSaved(String id) =>
      (state.asData?.value ?? const []).any((p) => p.id == id);

  Future<void> toggle(YoutubePlaylist playlist) async {    // build() reads storage and can land after this, overwriting
    // anything set in the meantime. Callers reach these through
    // ref.read(...notifier), which does not wait for it.
    await future;

    final current = state.asData?.value ?? const <YoutubePlaylist>[];
    if (current.any((p) => p.id == playlist.id)) {
      await _persist([
        for (final p in current)
          if (p.id != playlist.id) p,
      ]);
    } else {
      await _persist([...current, playlist]);
    }
  }
}

final youtubeSavedPlaylistsProvider =
    AsyncNotifierProvider<YoutubeSavedPlaylists, List<YoutubePlaylist>>(
        YoutubeSavedPlaylists.new);

/// One tab of a channel.
///
/// Keyed by channel + tab, so switching tabs doesn't refetch what's already
/// loaded and each tab keeps its own error state.
typedef YtChannelTabKey = ({String channelId, YtChannelTabKind kind});

final youtubeChannelTabProvider = FutureProvider.autoDispose
    .family<YtChannelTab, YtChannelTabKey>((ref, key) async =>
        ref.watch(youtubeInnerTubeProvider).channelTab(key.channelId, key.kind));

/// Named subsets of your subscriptions.
class YoutubeFeedGroups extends AsyncNotifier<List<YoutubeFeedGroup>> {
  static const _key = 'fathom_youtube_feed_groups';

  @override
  Future<List<YoutubeFeedGroup>> build() async {
    final raw = await ref.read(secureStorageProvider).read(key: _key);
    if (raw == null) return const [];
    try {
      return [
        for (final e in (jsonDecode(raw) as List).whereType<Map>())
          YoutubeFeedGroup.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persist(List<YoutubeFeedGroup> next) async {
    await ref.read(secureStorageProvider).write(
        key: _key, value: jsonEncode([for (final g in next) g.toJson()]));
    state = AsyncData(next);
  }

  List<YoutubeFeedGroup> get _current => state.asData?.value ?? const [];

  Future<YoutubeFeedGroup> create(String name) async {    // build() reads storage and can land after this, overwriting
    // anything set in the meantime. Callers reach these through
    // ref.read(...notifier), which does not wait for it.
    await future;

    final group = YoutubeFeedGroup(
      id: 'fg_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Untitled' : name.trim(),
    );
    await _persist([..._current, group]);
    return group;
  }

  Future<void> rename(String id, String name) async {
    await future;
    await _persist([
      for (final g in _current)
        if (g.id == id) g.copyWith(name: name.trim()) else g,
    ]);
  }

  Future<void> delete(String id) async {
    await future;
    await _persist([
      for (final g in _current)
        if (g.id != id) g,
    ]);
  }

  Future<void> toggleChannel(String groupId, String channelId) async {
    await future;
    await _persist([
      for (final g in _current)
        if (g.id == groupId)
          g.copyWith(channelIds: g.contains(channelId)
              ? [
                  for (final c in g.channelIds)
                    if (c != channelId) c,
                ]
              : [...g.channelIds, channelId])
        else
          g,
    ]);
  }

  /// Unsubscribing must not leave a channel id stranded in a group, where it
  /// would silently filter the feed to nothing.
  Future<void> forgetChannel(String channelId) async {    // build() reads storage and can land after this, overwriting
    // anything set in the meantime. Callers reach these through
    // ref.read(...notifier), which does not wait for it.
    await future;

    if (!_current.any((g) => g.contains(channelId))) return;
    await _persist([
      for (final g in _current)
        g.copyWith(channelIds: [
          for (final c in g.channelIds)
            if (c != channelId) c,
        ]),
    ]);
  }
}

final youtubeFeedGroupsProvider =
    AsyncNotifierProvider<YoutubeFeedGroups, List<YoutubeFeedGroup>>(
        YoutubeFeedGroups.new);

/// The group the What's New tab is filtered to, or null for everything.
class YoutubeActiveFeedGroup extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? id) => state = id;
}

final youtubeActiveFeedGroupProvider =
    NotifierProvider<YoutubeActiveFeedGroup, String?>(
        YoutubeActiveFeedGroup.new);

/// Where downloads are written, by kind.
///
/// Defaults to the user's real Downloads folder, not app-private storage: a
/// downloaded video is theirs, and burying it somewhere only this app can reach
/// defeats the point of having a file. Video and audio are separate, as in
/// NewPipe — audio downloads are usually music, and music belongs with music.
final youtubeDownloadDirProvider =
    FutureProvider.family<Directory, YtDownloadKind>((ref, kind) async {
  final p = ref.watch(preferencesProvider).asData?.value;
  final custom = kind == YtDownloadKind.audio
      ? (p?.youtubeAudioDownloadPath ?? '')
      : (p?.youtubeVideoDownloadPath ?? '');
  // Android 11+ downloads into Fathom's own folder and publishes the finished
  // file to the chosen (or default public) folder afterwards: writing straight
  // into shared storage by path is refused for scratch files and anywhere
  // outside the standard folders. See [YoutubeDownloads._publish].
  if (custom.isNotEmpty && !await SharedFiles.canPublish()) {
    return Directory(custom);
  }
  final downloads = await getDownloadsDirectory();
  final base = downloads ?? await getApplicationSupportDirectory();
  return Directory('${base.path}/Fathom');
});

/// Whether finished downloads are published to shared storage (Android 11+).
final sharedFilesPublishProvider =
    FutureProvider<bool>((ref) => SharedFiles.canPublish());

/// The folder downloads end up in, as shown to people: on Android 11+ the
/// public folder they're published to (see [SharedFiles]), elsewhere the
/// download folder itself.
final youtubeDownloadFolderLabelProvider =
    FutureProvider.family<String, YtDownloadKind>((ref, kind) async {
  final audio = kind == YtDownloadKind.audio;
  if (await SharedFiles.canPublish()) {
    final p = ref.watch(preferencesProvider).asData?.value;
    final picked = audio
        ? (p?.youtubeAudioDownloadPath ?? '')
        : (p?.youtubeVideoDownloadPath ?? '');
    return (picked.isEmpty ? null : SharedFiles.relativeDir(picked)) ??
        SharedFiles.defaultDir(audio: audio);
  }
  return (await ref.watch(youtubeDownloadDirProvider(kind).future)).path;
});

final youtubeDownloaderProvider =
    Provider<YoutubeDownloader>((ref) => YoutubeDownloader());

/// Whether ffmpeg is available. Without it nothing above 360p can be merged,
/// and the UI says so rather than failing at the end of a long download.
final ffmpegAvailableProvider =
    FutureProvider<bool>((ref) => YoutubeDownloader.hasFfmpeg());

/// Downloads, live and finished.
///
/// Only completed ones persist: an interrupted download leaves no resumable
/// file, so restoring it would be a row that can only be deleted.
class YoutubeDownloads extends AsyncNotifier<List<YoutubeDownload>> {
  static const _key = 'fathom_youtube_downloads';

  final Map<String, CancelToken> _cancels = {};

  @override
  Future<List<YoutubeDownload>> build() async {
    final raw = await ref.read(secureStorageProvider).read(key: _key);
    if (raw == null) return const [];
    try {
      final list = [
        for (final e in (jsonDecode(raw) as List).whereType<Map>())
          YoutubeDownload.fromJson(Map<String, dynamic>.from(e)),
      ];
      // Drop any whose file has since been moved or deleted from outside the
      // app, rather than listing downloads that aren't there.
      final kept = [
        for (final d in list)
          if (d.filePath != null && File(d.filePath!).existsSync()) d,
      ];
      unawaited(_publishHidden());
      return kept;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persistCompleted(List<YoutubeDownload> all) async {
    final done = [
      for (final d in all)
        if (d.status == YtDownloadStatus.done) d,
    ];
    await ref.read(secureStorageProvider).write(
        key: _key, value: jsonEncode([for (final d in done) d.toJson()]));
  }

  void _set(List<YoutubeDownload> next) {
    state = AsyncData(next);
    unawaited(_persistCompleted(next));
  }

  List<YoutubeDownload> get _current => state.asData?.value ?? const [];

  YoutubeDownload? entryFor(String videoId) =>
      _current.where((d) => d.id == videoId).firstOrNull;

  /// Moves a finished download out of Fathom's own folder into shared storage
  /// (Android 11+), so the Files app and the gallery see it: into the folder
  /// picked in settings when that's in shared storage and MediaStore accepts
  /// it, else Movies/Fathom or Music/Fathom. Null when it stays where it is.
  Future<String?> _publish(File file) async {
    if (!await SharedFiles.canPublish()) return null;
    final prefs = ref.read(preferencesProvider).asData?.value;
    final audio = SharedFiles.mimeFor(file.path).startsWith('audio/');
    final picked = audio
        ? (prefs?.youtubeAudioDownloadPath ?? '')
        : (prefs?.youtubeVideoDownloadPath ?? '');
    final pickedDir = picked.isEmpty ? null : SharedFiles.relativeDir(picked);
    for (final dir in [
      ?pickedDir,
      SharedFiles.defaultDir(audio: audio),
    ]) {
      try {
        return await SharedFiles.publish(file, dir);
      } catch (e) {
        Diagnostics.instance.add('downloads', 'publishing to $dir failed: $e');
      }
    }
    return null;
  }

  /// Where a download of this kind lands when [custom] is the folder setting:
  /// on Android 11+ the public folder it's published to, elsewhere the folder
  /// itself, or Downloads/Fathom when none is set.
  Future<String> _folderFor({required bool audio, required String custom}) async {
    if (await SharedFiles.canPublish()) {
      final rel = (custom.isEmpty ? null : SharedFiles.relativeDir(custom)) ??
          SharedFiles.defaultDir(audio: audio);
      return SharedFiles.absoluteDir(rel);
    }
    if (custom.isNotEmpty) return custom;
    final downloads = await getDownloadsDirectory();
    final base = downloads ?? await getApplicationSupportDirectory();
    return '${base.path}/Fathom';
  }

  static bool _isAudio(String path) =>
      SharedFiles.mimeFor(path).startsWith('audio/');

  /// Finished downloads of one kind that aren't in the folder [custom] points
  /// to: what changing the folder setting would leave behind.
  Future<List<YoutubeDownload>> leftBehind(
      {required bool audio, required String custom}) async {
    final folder = YoutubeDownloader.comparableFolder(
        await _folderFor(audio: audio, custom: custom));
    return [
      for (final d in _current)
        if (d.status == YtDownloadStatus.done &&
            d.filePath != null &&
            _isAudio(d.filePath!) == audio &&
            YoutubeDownloader.comparableFolder(File(d.filePath!).parent.path) !=
                folder &&
            File(d.filePath!).existsSync())
          d,
    ];
  }

  /// Moves [downloads] into the folder [custom] points to, and returns how
  /// many moved. Any that can't be moved stay where they were, and the
  /// reason goes to Diagnostics.
  Future<int> moveTo(List<YoutubeDownload> downloads,
      {required bool audio, required String custom}) async {
    final folder = await _folderFor(audio: audio, custom: custom);
    final publishes = await SharedFiles.canPublish();
    var moved = 0;
    for (final d in downloads) {
      final from = d.filePath;
      if (from == null) continue;
      try {
        final to = publishes
            ? await SharedFiles.move(
                from, folder.substring(SharedFiles.absoluteDir('').length))
            : await YoutubeDownloader.moveInto(File(from), Directory(folder));
        _update(d.id, (x) => x.copyWith(filePath: to));
        moved++;
      } catch (e) {
        Diagnostics.instance.add('downloads', 'moving ${d.title} failed: $e');
      }
    }
    return moved;
  }

  /// Downloads from before publishing existed sit in Fathom's own folder,
  /// hidden from every other app. Moves them out once, after the list loads.
  Future<void> _publishHidden() async {
    await future;
    if (!await SharedFiles.canPublish()) return;
    for (final d in _current) {
      final path = d.filePath;
      if (d.status != YtDownloadStatus.done ||
          path == null ||
          !path.contains('/Android/data/')) {
        continue;
      }
      final published = await _publish(File(path));
      if (published != null) {
        _update(d.id, (x) => x.copyWith(filePath: published));
      }
    }
  }

  void _update(String id, YoutubeDownload Function(YoutubeDownload) f) {
    _set([
      for (final d in _current)
        if (d.id == id) f(d) else d,
    ]);
  }

  Future<void> start(
    YoutubeVideo video, {
    YtDownloadOptions options = const YtDownloadOptions(),
  }) async {
    // Wait for build() before touching state.
    //
    // The download sheet only ever reads the notifier, so if the Downloads tab
    // hasn't been opened, build() is still reading storage when this runs.
    // Riverpod then lands build()'s result on top of whatever was set in the
    // meantime — the new download disappears while it's actually downloading,
    // and the tab reads "No downloads".
    await future;

    // Already here, or already running: don't start a second copy.
    final existing = entryFor(video.id);
    if (existing != null && (existing.isActive || existing.status == YtDownloadStatus.done)) {
      return;
    }

    // Beyond the limit it waits its turn. Several at once mostly divides the
    // same bandwidth, and the merge is CPU work that doesn't parallelise well.
    final limit = ref.read(preferencesProvider).asData?.value
            .youtubeMaxConcurrentDownloads ??
        2;
    final running = _current.where((d) => d.isActive).length;
    final queued = running >= limit;

    final entry = YoutubeDownload(
      id: video.id,
      title: video.title,
      author: video.author,
      thumbnailUrl: video.thumbnailUrl,
      status: queued ? YtDownloadStatus.queued : YtDownloadStatus.downloading,
      stage: queued ? '' : 'video',
    );
    _set([entry, ..._current.where((d) => d.id != video.id)]);

    if (queued) {
      _pending.add((video, options));
      return;
    }

    await _run(video, options);
  }

  /// Videos waiting for a slot.
  final List<(YoutubeVideo, YtDownloadOptions)> _pending = [];

  Future<void> _run(YoutubeVideo video, YtDownloadOptions options) async {
    _update(
        video.id,
        (d) => d.copyWith(
            status: YtDownloadStatus.downloading, stage: 'video'));
    final cancel = CancelToken();
    _cancels[video.id] = cancel;
    var finished = false;
    try {
      final prefs = ref.read(preferencesProvider).asData?.value;
      final dir =
          await ref.read(youtubeDownloadDirProvider(options.kind).future);
      final file = await ref.read(youtubeDownloaderProvider).download(
            videoUrl: video.url,
            title: video.title,
            into: dir,
            kind: options.kind,
            preferredHeight: options.preferredHeight,
            audioFormat: options.audioFormat,
            audioBitrate: options.audioBitrate,
            container: options.container,
            retries: prefs?.youtubeDownloadRetries ?? 3,
            cancelToken: cancel,
            onProgress: (p) => _update(
              video.id,
              (d) => d.copyWith(
                status: p.stage == 'merging'
                    ? YtDownloadStatus.merging
                    : YtDownloadStatus.downloading,
                stage: p.stage,
                progress: p.fraction,
                clearProgress: p.fraction == null,
                bytes: p.received > 0 ? p.received : d.bytes,
              ),
            ),
          );
      final published = await _publish(file);
      final saved = published == null ? file : File(published);
      _update(
          video.id,
          (d) => d.copyWith(
                status: YtDownloadStatus.done,
                filePath: saved.path,
                progress: 1,
                stage: '',
                bytes: saved.existsSync() ? saved.lengthSync() : d.bytes,
              ));
      finished = true;
    } on DioException catch (e) {
      _update(
          video.id,
          (d) => d.copyWith(
                status: e.type == DioExceptionType.cancel
                    ? YtDownloadStatus.cancelled
                    : YtDownloadStatus.failed,
                error: e.type == DioExceptionType.cancel ? null : e.message,
              ));
    } catch (e) {
      _update(video.id,
          (d) => d.copyWith(status: YtDownloadStatus.failed, error: errorText(e)));
    } finally {
      _cancels.remove(video.id);
      // Saying so comes after, and apart: the file is saved whatever happens
      // to the message about it. Inside the download's own error handling, a
      // failure here turned a finished download into a failed one.
      if (finished) {
        try {
          await pushAppNotification(ref,
              kind: AppNotifKind.downloadComplete,
              title: tr.notifDownloadComplete,
              body: video.title,
              enabled: ref
                      .read(preferencesProvider)
                      .asData
                      ?.value
                      .notifDownloads ??
                  true,
              // '/downloads' is the Jellyfin library: this download is a
              // YouTube one, so the tap belongs on its own Downloads tab.
              route: '/youtube',
              routeExtra: kYoutubeDownloadsTabIndex);
        } catch (e) {
          Diagnostics.instance.add('downloads', 'could not notify: $e');
        }
      }
      // Hand the slot to whoever's next.
      if (_pending.isNotEmpty) {
        final next = _pending.removeAt(0);
        unawaited(_run(next.$1, next.$2));
      }
    }
  }

  void cancel(String videoId) {
    // A queued download has no request to abort, so drop it from the waiting
    // list or it would start later despite being cancelled.
    _pending.removeWhere((p) => p.$1.id == videoId);
    _cancels[videoId]?.cancel('cancelled');
    _cancels.remove(videoId);
  }

  /// Removes the row. [deleteFile] also removes what was downloaded — kept
  /// separate because "clear this list" and "delete my video" are different
  /// intentions.
  Future<void> remove(String videoId, {bool deleteFile = false}) async {
    final entry = entryFor(videoId);
    cancel(videoId);
    if (deleteFile && entry?.filePath != null) {
      try {
        final f = File(entry!.filePath!);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
    _set([
      for (final d in _current)
        if (d.id != videoId) d,
    ]);
  }

  /// Records how far into a downloaded video playback got, so reopening it
  /// resumes there. Local only — never touches the online watch-history
  /// system, which points at a streaming URL a downloaded file has no use for.
  Future<void> updateProgress(
      String videoId, Duration position, Duration duration) async {
    await future;
    if (position <= Duration.zero || duration <= Duration.zero) return;
    if (entryFor(videoId) == null) return;
    _update(
      videoId,
      (d) => d.copyWith(
        watchPositionSeconds: position.inSeconds,
        watchDurationSeconds: duration.inSeconds,
      ),
    );
  }
}

final youtubeDownloadsProvider =
    AsyncNotifierProvider<YoutubeDownloads, List<YoutubeDownload>>(
        YoutubeDownloads.new);

final sponsorBlockProvider = Provider<SponsorBlock>((ref) => SponsorBlock());

/// SponsorBlock segments for a video, honouring the settings.
///
/// Returns nothing when the feature is off, so the player can ask
/// unconditionally and no request is made unless it's been enabled.
final youtubeSponsorSegmentsProvider = FutureProvider.autoDispose
    .family<List<SponsorSegment>, String>((ref, videoId) async {
  final p = ref.watch(preferencesProvider).asData?.value;
  if (p == null || !p.youtubeSponsorBlock) return const [];
  final categories = {
    for (final id in p.youtubeSponsorBlockCategories)
      if (SponsorCategory.fromId(id) != null) SponsorCategory.fromId(id)!,
  };
  if (categories.isEmpty) return const [];
  return ref.watch(sponsorBlockProvider).segments(videoId, categories: categories);
});
