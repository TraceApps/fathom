import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/api/jellyfin_client.dart';
import 'package:fathom/models/base_item.dart';
import 'package:fathom/models/play_queue.dart';
import 'package:fathom/state/playlist_providers.dart';
import 'package:fathom/state/playlist_run.dart';
import 'package:fathom/models/session.dart';
import 'package:fathom/state/session_controller.dart';
import 'package:fathom/routing/item_page.dart';
import 'package:fathom/screens/artists_screen.dart';
import 'package:fathom/screens/detail_screen.dart';
import 'package:fathom/screens/favorites_screen.dart';
import 'package:fathom/screens/movie_wheel_screen.dart';
import 'package:fathom/screens/person_screen.dart';
import 'package:fathom/screens/playlist_detail_screen.dart';
import 'package:fathom/screens/search_screen.dart';
import 'package:fathom/screens/watchlist_screen.dart';
import 'package:fathom/state/seerr_providers.dart';
import 'package:fathom/state/library_providers.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/providers.dart';
import 'package:fathom/state/watchlist.dart';
import 'package:fathom/widgets/item_actions.dart';
import 'package:fathom/widgets/media_image.dart';
import 'package:fathom/widgets/watchlist_toggle.dart';

// Watchlist, Favorites and Playlists each have one meaning and one home:
// the Watchlist is movies and shows to watch (the Movie Night Wheel starts
// from it), Favorites is anything loved, a playlist is played in order.
// These pin down that each opens on its own page, takes only what it's for,
// and that the Wheel's winner can always be played.

class _FakeWatchlist extends WatchlistController {
  _FakeWatchlist(this.items, {this.fail = false, this.hang = false});
  final List<BaseItemDto> items;
  final bool fail;
  final bool hang;

  @override
  Future<List<BaseItemDto>> build() async {
    if (hang) return Completer<List<BaseItemDto>>().future;
    if (fail) throw Exception('The server could not be reached.');
    return items;
  }
}

class _FakePrefs extends PreferencesController {
  @override
  Future<Prefs> build() async => const Prefs(movieWheelSound: false);

  @override
  Future<void> edit(Prefs Function(Prefs) change) async {
    state = AsyncData(change(state.asData?.value ?? const Prefs()));
  }
}

BaseItemDto _it(String id, String type,
        {String? name, String? seriesId, String? seriesName}) =>
    BaseItemDto(
      id: id,
      name: name ?? id,
      type: type,
      seriesId: seriesId,
      seriesName: seriesName,
    );

final _movie = _it('m1', 'Movie', name: 'Rig Movie');
final _show = _it('s1', 'Series', name: 'Rig Show');
final _episode =
    _it('e1', 'Episode', seriesId: 's1', seriesName: 'Rig Show');
final _song = _it('a1', 'Audio', name: 'Rig Song');
final _person = _it('p1', 'Person', name: 'Rig Actor');
final _artist = _it('ar1', 'MusicArtist', name: 'Rig Artist');
final _playlist = _it('pl1', 'Playlist', name: 'Road Trip');
final _watchlistPlaylist =
    _it('wl', 'Playlist', name: WatchlistController.kWatchlistName);


/// A Jellyfin server's playlist, behaving as 10.10 and later do: a show put
/// on a playlist becomes all of its episodes (checked against 10.10.7 and
/// 12.4 on the rig).
class _PlaylistServer implements HttpClientAdapter {
  _PlaylistServer({List<Map<String, Object?>> entries = const []})
      : entries = [...entries];
  final List<Map<String, Object?>> entries;
  final List<String> added = [];
  final List<List<String>> removed = [];
  final Set<String> missingShows = {};
  var _next = 0;

  static Map<String, Object?> episode(String id, String show) =>
      {'Id': id, 'Name': id, 'Type': 'Episode', 'SeriesId': show};
  static Map<String, Object?> movie(String id) =>
      {'Id': id, 'Name': id, 'Type': 'Movie'};

  Map<String, Object?> _entry(Map<String, Object?> item) =>
      {...item, 'PlaylistItemId': 'entry-${_next++}'};

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final path = o.uri.path;
    final q = o.uri.queryParameters;
    Object? json;
    if (path == '/Items' && q['IncludeItemTypes'] == 'Playlist') {
      json = {
        'Items': [
          {'Id': 'wl', 'Name': WatchlistController.kWatchlistName, 'Type': 'Playlist'}
        ]
      };
    } else if (path == '/Playlists/wl/Items' && o.method == 'GET') {
      json = {'Items': [for (final e in entries) e]};
    } else if (path == '/Playlists/wl/Items' && o.method == 'POST') {
      for (final id in q['Ids']!.split(',')) {
        added.add(id);
        if (id.contains('-e')) {
          entries.add(_entry(episode(id, id.split('-e').first)));
        } else if (id.startsWith('show')) {
          for (var i = 1; i <= 3; i++) {
            entries.add(_entry(episode('$id-e$i', id)));
          }
        } else {
          entries.add(_entry(movie(id)));
        }
      }
      json = '';
    } else if (path == '/Playlists/wl/Items' && o.method == 'DELETE') {
      final gone = q['EntryIds']!.split(',');
      removed.add(gone);
      entries.removeWhere((e) => gone.contains(e['PlaylistItemId']));
      json = '';
    } else if (path.startsWith('/Shows/') && path.endsWith('/Episodes')) {
      final show = path.split('/')[2];
      json = {
        'Items': [
          for (var i = 1; i <= 3; i++) episode('$show-e$i', show)
        ]
      };
    } else if (path == '/Items' && q['Ids'] != null) {
      json = {
        'Items': [
          for (final id in q['Ids']!.split(','))
            if (!missingShows.contains(id))
              {'Id': id, 'Name': 'Show $id', 'Type': 'Series'}
        ]
      };
    } else {
      json = {'Items': []};
    }
    return ResponseBody.fromString(
      json is String ? json : jsonEncode(json),
      json is String ? 204 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Answers each request with what [answer] says: a status and a body.
class _Scripted implements HttpClientAdapter {
  _Scripted(this.answer);
  final (int, String) Function(RequestOptions) answer;

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final (status, text) = answer(o);
    return ResponseBody.fromString(text, status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _Signed extends SessionController {
  @override
  Future<Session?> build() async => const Session(
        baseUrl: 'http://jf',
        accessToken: 't',
        userId: 'u',
        userName: 'tester',
      );
}

ProviderContainer _watchlistOn(_PlaylistServer server) {
  final c = ProviderContainer(overrides: [
    deviceIdProvider.overrideWithValue('test-device'),
    sessionControllerProvider.overrideWith(_Signed.new),
    jellyfinClientProvider.overrideWithValue(JellyfinClient(
      deviceId: 'd',
      httpClient: Dio()..httpClientAdapter = server,
    )),
  ]);
  addTearDown(c.dispose);
  c.listen(watchlistProvider, (_, _) {});
  return c;
}

AppLocalizations get _l => lookupAppLocalizations(const Locale('en'));

void main() {
  setUpAll(MediaKit.ensureInitialized);

  group('one page for each', () {
    test("the server's Playlists and Live TV folders open their own pages", () {
      BaseItemDto view(String type) =>
          BaseItemDto(id: type, name: type, collectionType: type);
      expect(libraryViewRoute(view('playlists')), '/playlists');
      expect(libraryViewRoute(view('livetv')), '/livetv');
      expect(libraryViewRoute(view('movies')), '/library');
      expect(libraryViewRoute(view('music')), '/library');
    });

    test('an item opens on the page for its kind, never a title page', () {
      expect(itemPage(_playlist), isA<PlaylistDetailScreen>());
      expect(itemPage(_watchlistPlaylist), isA<WatchlistScreen>());
      expect(itemPage(_artist), isA<ArtistAlbumsScreen>());
      final person = itemPage(_person);
      expect(person, isA<PersonScreen>());
      expect((person as PersonScreen).person.id, 'p1');
      expect(itemPage(_movie), isA<DetailScreen>());
      expect(itemPage(_show), isA<DetailScreen>());
    });

    test('only the playlist named for the Watchlist is the Watchlist', () {
      expect(isWatchlistPlaylist(_watchlistPlaylist), isTrue);
      expect(isWatchlistPlaylist(_playlist), isFalse);
      // A movie that happens to have the name is still a movie.
      expect(
          isWatchlistPlaylist(
              _it('x', 'Movie', name: WatchlistController.kWatchlistName)),
          isFalse);
    });
  });

  group('the Watchlist takes movies and shows', () {
    test('an episode stands for its show; music and people for nothing', () {
      expect(WatchlistController.entryIdFor(_movie), 'm1');
      expect(WatchlistController.entryIdFor(_show), 's1');
      expect(WatchlistController.entryIdFor(_episode), 's1');
      expect(WatchlistController.entryIdFor(_song), isNull);
      expect(WatchlistController.entryIdFor(_person), isNull);
      expect(WatchlistController.entryIdFor(_playlist), isNull);
    });

    test('an episode shows its show is on the Watchlist', () {
      expect(inWatchlistFor([_show], _episode), isTrue);
      expect(watchlistToggleLabel(_l, [_show], _episode),
          'Remove Show from Watchlist');
      expect(watchlistToggleLabel(_l, const [], _episode),
          'Add Show to Watchlist');
      expect(watchlistToggleLabel(_l, const [], _movie), 'Add to Watchlist');
    });

    test('an entry from before still comes off', () {
      // An episode and a song put on before the Watchlist took only movies
      // and shows: each still finds its own entry, so it can be removed.
      expect(watchlistEntryOn([_episode], _episode), 'e1');
      expect(watchlistToggleLabel(_l, [_episode], _episode),
          'Remove from Watchlist');
      expect(hasWatchlistToggle([_song], _song), isTrue);
      expect(hasWatchlistToggle(const [], _song), isFalse);
      expect(hasWatchlistToggle(const [], _person), isFalse);
    });
  });


  group('a show on the Watchlist', () {
    test('episodes in the playlist show as their show, once', () async {
      final server = _PlaylistServer(entries: [
        {..._PlaylistServer.movie('m1'), 'PlaylistItemId': 'p0'},
        // A show added before this fix: the server turned it into episodes.
        for (var i = 1; i <= 3; i++)
          {..._PlaylistServer.episode('s1-e$i', 's1'), 'PlaylistItemId': 'p$i'},
      ]);
      final c = _watchlistOn(server);
      final list = await c.read(watchlistProvider.future);
      expect(list.map((i) => (i.id, i.type)),
          [('s1', 'Series'), ('m1', 'Movie')]);
    });

    test('taking a show off removes every episode of it', () async {
      final server = _PlaylistServer(entries: [
        {..._PlaylistServer.movie('m1'), 'PlaylistItemId': 'p0'},
        for (var i = 1; i <= 3; i++)
          {..._PlaylistServer.episode('s1-e$i', 's1'), 'PlaylistItemId': 'p$i'},
      ]);
      final c = _watchlistOn(server);
      await c.read(watchlistProvider.future);
      await c.read(watchlistProvider.notifier).remove('s1');
      expect(server.removed.single, unorderedEquals(['p1', 'p2', 'p3']));
      expect((await c.read(watchlistProvider.future)).map((i) => i.id), ['m1']);
    });

    test('a show goes on as one episode, not all of them', () async {
      final server = _PlaylistServer();
      final c = _watchlistOn(server);
      await c.read(watchlistProvider.future);
      await c.read(watchlistProvider.notifier).add(
          const BaseItemDto(id: 'show2', name: 'Show Two', type: 'Series'));
      expect(server.added, ['show2-e1']);
      expect(server.entries, hasLength(1));
      final list = await c.read(watchlistProvider.future);
      expect(list.map((i) => (i.id, i.type)), [('show2', 'Series')]);
    });

    test("an episode of a show already on adds nothing", () async {
      final server = _PlaylistServer(entries: [
        {..._PlaylistServer.episode('s1-e1', 's1'), 'PlaylistItemId': 'p1'},
      ]);
      final c = _watchlistOn(server);
      await c.read(watchlistProvider.future);
      await c.read(watchlistProvider.notifier).add(const BaseItemDto(
          id: 's1-e2', name: 'e2', type: 'Episode', seriesId: 's1'));
      expect(server.added, isEmpty);
    });

    test('a show the server no longer has can still come off', () async {
      final server = _PlaylistServer(entries: [
        for (var i = 1; i <= 2; i++)
          {..._PlaylistServer.episode('gone-e$i', 'gone'), 'PlaylistItemId': 'p$i'},
      ])..missingShows.add('gone');
      final c = _watchlistOn(server);
      final list = await c.read(watchlistProvider.future);
      // Shown as its newest episode, since the show itself is gone.
      expect(list.single.type, 'Episode');
      final shown = list.single;
      expect(watchlistToggleLabel(_l, list, shown), 'Remove from Watchlist');
      await c.read(watchlistProvider.notifier).remove(shown.id);
      expect(server.removed.single, unorderedEquals(['p1', 'p2']));
    });

    test('a removal while the list reloads still goes through', () async {
      final server = _PlaylistServer(entries: [
        {..._PlaylistServer.movie('m1'), 'PlaylistItemId': 'p0'},
        {..._PlaylistServer.movie('m2'), 'PlaylistItemId': 'p1'},
      ]);
      final c = _watchlistOn(server);
      await c.read(watchlistProvider.future);
      final notifier = c.read(watchlistProvider.notifier);
      // Two removals back to back: the second starts while the first one's
      // reload is still on its way.
      final first = notifier.remove('m1');
      await Future<void>.delayed(Duration.zero);
      final second = notifier.remove('m2');
      await Future.wait([first, second]);
      expect(server.removed.expand((b) => b), unorderedEquals(['p0', 'p1']));
      expect(await c.read(watchlistProvider.future), isEmpty);
    });

    test('adding before the list has loaded adds no second entry', () async {
      // A card's menu opened right after launch: the list wasn't in yet, so
      // a title already on it looked addable, and was added again.
      final server = _PlaylistServer(entries: [
        {..._PlaylistServer.movie('m1'), 'PlaylistItemId': 'p0'},
      ]);
      final c = _watchlistOn(server);
      // No waiting for the list here.
      await c.read(watchlistProvider.notifier).add(
          const BaseItemDto(id: 'm1', name: 'Rig Movie', type: 'Movie'));
      expect(server.added, isEmpty);
      expect(server.entries, hasLength(1));
    });

    test('a show turned into hundreds of episodes comes off in batches',
        () async {
      final server = _PlaylistServer(entries: [
        for (var i = 0; i < 250; i++)
          {..._PlaylistServer.episode('s1-e$i', 's1'), 'PlaylistItemId': 'p$i'},
      ]);
      final c = _watchlistOn(server);
      await c.read(watchlistProvider.future);
      await c.read(watchlistProvider.notifier).remove('s1');
      expect(server.removed.map((b) => b.length), [100, 100, 50]);
      expect(server.entries, isEmpty);
    });
  });


  group('a playlist plays through', () {
    final movieA = _it('va', 'Movie', name: 'Movie A');
    final episodeB = _it('vb', 'Episode', name: 'Episode B');
    final movieC = _it('vc', 'Movie', name: 'Movie C');

    Future<List<Object?>> open(WidgetTester tester, List<BaseItemDto> items,
        Future<void> Function() act) async {
      final pushed = <Object?>[];
      final router = GoRouter(routes: [
        GoRoute(
            path: '/',
            builder: (_, _) => PlaylistDetailScreen(playlist: _playlist)),
        GoRoute(
            path: '/player',
            builder: (_, state) {
              pushed.add(state.extra);
              return const SizedBox();
            }),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          deviceIdProvider.overrideWithValue('test-device'),
          playlistItemsProvider.overrideWith((ref, id) async => items),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ));
      await tester.pump();
      await tester.pump();
      await act();
      await tester.pumpAndSettle();
      return pushed;
    }

    testWidgets('Play starts at the top with the rest queued after it',
        (tester) async {
      final pushed = await open(tester, [movieA, episodeB, movieC],
          () => tester.tap(find.byIcon(Icons.play_arrow_rounded).first));
      final q = pushed.single as PlayQueue;
      expect(q.items.map((i) => i.id), ['va', 'vb', 'vc']);
      expect(q.index, 0);
    });

    testWidgets('tapping one goes on from there', (tester) async {
      final pushed = await open(tester, [movieA, episodeB, movieC],
          () => tester.tap(find.text('Episode B')));
      final q = pushed.single as PlayQueue;
      expect(q.current.id, 'vb');
      expect(q.items.map((i) => i.id), ['va', 'vb', 'vc']);
    });

    testWidgets('Shuffle plays every video, in some order', (tester) async {
      final pushed = await open(tester, [movieA, episodeB, movieC],
          () => tester.tap(find.byIcon(Icons.shuffle_rounded)));
      final q = pushed.single as PlayQueue;
      expect(q.items.map((i) => i.id), unorderedEquals(['va', 'vb', 'vc']));
      expect(q.index, 0);
    });

    testWidgets('a mixed list keeps its songs in the queue, in order',
        (tester) async {
      final pushed = await open(tester, [movieA, _song, movieC],
          () => tester.tap(find.byIcon(Icons.play_arrow_rounded).first));
      final q = pushed.single as PlayQueue;
      // The song is in it: the player hands over to music when it gets there.
      expect(q.items.map((i) => i.id), ['va', 'a1', 'vc']);
    });

    testWidgets('an item in a playlist twice shows twice, and plays from the '
        'one tapped', (tester) async {
      // Jellyfin gives both the same entry id: with one key for two rows,
      // one of them was left blank.
      BaseItemDto entry(String id, String type, String name) => BaseItemDto(
          id: id, name: name, type: type, playlistItemId: id);
      final list = [
        entry('va', 'Movie', 'Movie A'),
        entry('vb', 'Episode', 'Episode B'),
        entry('va', 'Movie', 'Movie A'),
      ];
      final pushed = await open(tester, list, () async {
        expect(find.text('Movie A'), findsNWidgets(2));
        await tester.tap(find.text('Movie A').last);
      });
      final q = pushed.single as PlayQueue;
      expect(q.index, 2);
    });

    test('songs play as far as the next video, which follows them', () {
      final song2 = _it('a2', 'Audio', name: 'Song Two');
      final list = [_song, song2, movieA, _song, movieC];
      // From the top: two songs, then on to Movie A.
      final (songs, after) = PlaylistRun.songsFrom(PlayQueue(list, 0));
      expect(songs.map((s) => s.id), ['a1', 'a2']);
      expect(after!.current.id, 'va');
      expect(identical(after.items, list), isTrue);
      // The song between the movies: one song, then Movie C.
      final (mid, then) = PlaylistRun.songsFrom(PlayQueue(list, 3));
      expect(mid.map((s) => s.id), ['a1']);
      expect(then!.current.id, 'vc');
      // Songs at the end of a list end it.
      final (last, none) =
          PlaylistRun.songsFrom(PlayQueue([movieA, _song, song2], 1));
      expect(last, hasLength(2));
      expect(none, isNull);
    });

    test("the player's Next steps through the playlist, not the show", () {
      final q = PlayQueue([movieA, episodeB, movieC], 1);
      expect(q.current.id, 'vb');
      expect(q.at(2).current.id, 'vc');
      expect(identical(q.at(2).items, q.items), isTrue);
    });
  });


  group('Search, when the server has nothing', () {
    Future<(List<Uri>, ProviderContainer)> searchFor(WidgetTester tester,
        {required bool seerr}) async {
      final opened = <Uri>[];
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const SearchScreen()),
        GoRoute(
            path: '/discover',
            builder: (_, state) {
              opened.add(state.uri);
              return const SizedBox();
            }),
      ]);
      late ProviderContainer container;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          deviceIdProvider.overrideWithValue('test-device'),
          sessionControllerProvider.overrideWith(_Signed.new),
          jellyfinClientProvider.overrideWithValue(JellyfinClient(
            deviceId: 'd',
            httpClient: Dio()..httpClientAdapter = _PlaylistServer(),
          )),
          seerrConfiguredProvider.overrideWithValue(seerr),
        ],
        child: Consumer(builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          );
        }),
      ));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, 'Dune');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump();
      return (opened, container);
    }

    testWidgets('with Seerr, it offers to look in Discover', (tester) async {
      final (opened, container) = await searchFor(tester, seerr: true);
      expect(find.text(_l.browseNotOnServer('Dune')), findsOneWidget);
      await tester.tap(find.text('Search in Discover'));
      await tester.pumpAndSettle();
      expect(opened.single.queryParameters['tab'], 'search');
      expect(container.read(seerrQueryProvider), 'Dune');
    });

    testWidgets('without Seerr, it only says try another search',
        (tester) async {
      await searchFor(tester, seerr: false);
      expect(find.text('Search in Discover'), findsNothing);
      expect(find.text(_l.browseTryDifferentSearch), findsOneWidget);
    });
  });


  group('renaming a playlist', () {
    test('a current server takes the new name alone', () async {
      final calls = <String>[];
      final client = JellyfinClient(
        deviceId: 'd',
        httpClient: Dio()
          ..httpClientAdapter = _Scripted((o) {
            calls.add('${o.method} ${o.uri.path}');
            return (204, '');
          }),
      );
      await client.renamePlaylist(
          baseUrl: 'http://jf', userId: 'u', token: 't', playlistId: 'p1', name: 'New');
      expect(calls, ['POST /Playlists/p1']);
    });

    test('10.8, which has no such route, gets the whole item back renamed',
        () async {
      final calls = <String>[];
      Object? sent;
      final client = JellyfinClient(
        deviceId: 'd',
        httpClient: Dio()
          ..httpClientAdapter = _Scripted((o) {
            calls.add('${o.method} ${o.uri.path}');
            if (o.uri.path == '/Playlists/p1') return (404, '');
            if (o.method == 'GET') {
              return (200, jsonEncode({'Id': 'p1', 'Name': 'Old', 'Genres': ['Kept']}));
            }
            sent = o.data;
            return (204, '');
          }),
      );
      await client.renamePlaylist(
          baseUrl: 'http://jf', userId: 'u', token: 't', playlistId: 'p1', name: 'New');
      expect(calls,
          ['POST /Playlists/p1', 'GET /Users/u/Items/p1', 'POST /Items/p1']);
      expect(sent, {'Id': 'p1', 'Name': 'New', 'Genres': ['Kept']});
    });

    test('a server that refuses says so, with no second try', () async {
      final calls = <String>[];
      final client = JellyfinClient(
        deviceId: 'd',
        httpClient: Dio()
          ..httpClientAdapter = _Scripted((o) {
            calls.add('${o.method} ${o.uri.path}');
            return (403, '');
          }),
      );
      await expectLater(
          client.renamePlaylist(
              baseUrl: 'http://jf', userId: 'u', token: 't', playlistId: 'p1', name: 'New'),
          throwsA(isA<JellyfinException>()));
      expect(calls, ['POST /Playlists/p1']);
    });

    test("the Watchlist's name can't be given to a playlist", () {
      expect(isPlaylistNameFree('Road Trip'), isTrue);
      expect(isPlaylistNameFree('  '), isFalse);
      expect(isPlaylistNameFree('Fathom Watchlist'), isFalse);
      expect(isPlaylistNameFree(' fathom watchlist '), isFalse);
    });
  });

  group('Favorites', () {
    test('a tile without a picture shows what it is', () {
      expect(placeholderIconFor(_person), Icons.person_rounded);
      expect(placeholderIconFor(_song), Icons.music_note_rounded);
      expect(placeholderIconFor(_artist), Icons.mic_rounded);
      expect(placeholderIconFor(_show), Icons.tv_rounded);
      expect(placeholderIconFor(_playlist), Icons.playlist_play_rounded);
      expect(placeholderIconFor(_movie), Icons.movie_rounded);
    });

    test('every kind has a group, people included', () {
      expect(FavoriteGroup.of(_movie), FavoriteGroup.movies);
      expect(FavoriteGroup.of(_episode), FavoriteGroup.episodes);
      expect(FavoriteGroup.of(_song), FavoriteGroup.music);
      expect(FavoriteGroup.of(_artist), FavoriteGroup.music);
      expect(FavoriteGroup.of(_person), FavoriteGroup.people);
      expect(FavoriteGroup.of(_playlist), FavoriteGroup.playlists);
      // What's asked of /Items covers every group but people, which come
      // from /Persons.
      final asked = favoriteItemTypes.split(',').toSet();
      for (final g in FavoriteGroup.values) {
        if (g == FavoriteGroup.people) continue;
        expect(asked.containsAll(g.types), isTrue, reason: g.name);
      }
      expect(asked.contains('Person'), isFalse);
    });

    Widget favorites(List<BaseItemDto> items) => ProviderScope(
          overrides: [
            deviceIdProvider.overrideWithValue('test-device'),
            favoriteItemsProvider.overrideWith((ref) async => items),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: FavoritesScreen(),
          ),
        );

    testWidgets('chips only for kinds that are there, and they narrow it',
        (tester) async {
      await tester.pumpWidget(favorites([_movie, _song, _person]));
      await tester.pump();
      await tester.pump();
      for (final chip in ['All', 'Movies', 'Music', 'People']) {
        expect(find.widgetWithText(ChoiceChip, chip), findsOneWidget,
            reason: chip);
      }
      for (final chip in ['Shows', 'Episodes', 'Playlists']) {
        expect(find.widgetWithText(ChoiceChip, chip), findsNothing,
            reason: chip);
      }
      expect(find.text('Rig Actor'), findsOneWidget);
      expect(find.text('Rig Movie'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'People'));
      await tester.pump();
      expect(find.text('Rig Actor'), findsOneWidget);
      expect(find.text('Rig Movie'), findsNothing);
      expect(find.text('Rig Song'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('one kind needs no chips', (tester) async {
      await tester.pumpWidget(favorites([_movie]));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Rig Movie'), findsOneWidget);
    });
  });

  group('More menu', () {
    Future<List<String>> menuFor(
        WidgetTester tester, BaseItemDto item, List<BaseItemDto> wl) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          deviceIdProvider.overrideWithValue('test-device'),
          watchlistProvider.overrideWith(() => _FakeWatchlist(wl)),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              ref.watch(watchlistProvider);
              return Scaffold(
                body: TextButton(
                  onPressed: () => showItemActionsMenu(context, ref, item,
                      at: const Offset(10, 10)),
                  child: const Text('open'),
                ),
              );
            },
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return [
        for (final w in tester.widgetList<Text>(find.byType(Text)))
          if (w.data != null) w.data!,
      ];
    }

    testWidgets('a person is only favorited', (tester) async {
      final rows = await menuFor(tester, _person, const []);
      expect(rows, contains('Add to Favorites'));
      expect(rows, isNot(contains('Mark Watched')));
      expect(rows, isNot(contains('Add to Watchlist')));
      expect(rows, isNot(contains('Add to Playlist')));
    });

    testWidgets('a song goes in a playlist, not on the Watchlist',
        (tester) async {
      final rows = await menuFor(tester, _song, const []);
      expect(rows, contains('Add to Playlist'));
      expect(rows, isNot(contains('Add to Watchlist')));
    });

    testWidgets("an episode puts its show on", (tester) async {
      expect(await menuFor(tester, _episode, const []),
          contains('Add Show to Watchlist'));
    });

    testWidgets('a movie has all three lists', (tester) async {
      final rows = await menuFor(tester, _movie, const []);
      expect(rows,
          containsAll(['Add to Favorites', 'Add to Watchlist', 'Add to Playlist']));
    });
  });

  group('Movie Night Wheel', () {
    Widget wheel(_FakeWatchlist wl,
        {List<Override> extra = const [], GoRouter? router}) {
      final overrides = [
        deviceIdProvider.overrideWithValue('test-device'),
        preferencesProvider.overrideWith(_FakePrefs.new),
        watchlistProvider.overrideWith(() => wl),
        ...extra,
      ];
      if (router != null) {
        return ProviderScope(
          overrides: overrides,
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        );
      }
      return ProviderScope(
        overrides: overrides,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MovieWheelScreen(),
        ),
      );
    }

    testWidgets('a Watchlist still loading is not called empty',
        (tester) async {
      await tester.pumpWidget(wheel(_FakeWatchlist(const [], hang: true)));
      await tester.pump();
      expect(find.text(_l.wheelNeedsWatchlist), findsNothing);
    });

    testWidgets('a Watchlist that failed to load says so, with Retry',
        (tester) async {
      await tester.pumpWidget(wheel(_FakeWatchlist(const [], fail: true)));
      await tester.pump();
      await tester.pump();
      expect(find.text(_l.wheelNeedsWatchlist), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('the genre menu ticks the genre picked', (tester) async {
      final titles = [
        BaseItemDto(id: 'g1', name: 'One', type: 'Movie', genres: ['Comedy']),
        BaseItemDto(id: 'g2', name: 'Two', type: 'Movie', genres: ['Drama']),
      ];
      await tester.pumpWidget(wheel(_FakeWatchlist(titles)));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text(_l.wheelFilterGenre));
      await tester.pumpAndSettle();
      // All Genres is ticked until one is picked.
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(find.text('Drama').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drama').first);
      await tester.pumpAndSettle();
      final tick = find.byIcon(Icons.check_rounded);
      expect(tick, findsOneWidget);
      final item = find.ancestor(
          of: tick,
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem<String>));
      expect(item, findsOneWidget);
      final picked = tester.widget<PopupMenuItem<String>>(item).value;
      expect(picked, 'Drama');
    });

    testWidgets('a show that wins plays its Next Up', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Object? played;
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const MovieWheelScreen()),
        GoRoute(
            path: '/player',
            builder: (_, state) {
              played = state.extra;
              return const SizedBox();
            }),
      ]);
      final shows = [
        BaseItemDto(id: 's1', name: 'Show One', type: 'Series'),
        BaseItemDto(id: 's2', name: 'Show Two', type: 'Series'),
      ];
      await tester.pumpWidget(wheel(
        _FakeWatchlist(shows),
        router: router,
        extra: [
          nextUpProvider.overrideWith((ref, id) async =>
              BaseItemDto(id: '$id-next', name: 'Next', type: 'Episode')),
          episodesProvider.overrideWith((ref, id) async => const []),
        ],
      ));
      await tester.pump();
      await tester.pump();
      // Single Spin: the first landing wins.
      await tester.tap(find.text(_l.wheelModeSingle));
      await tester.pump();
      await tester.tap(find.text('Start with 2 Titles'));
      await tester.pump();
      await tester.tap(find.byType(GestureDetector).first);
      for (var i = 0; i < 180; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text("TONIGHT'S PICK"), findsOneWidget);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(played, isA<BaseItemDto>());
      final episode = played as BaseItemDto;
      expect(episode.type, 'Episode');
      expect(episode.id, endsWith('-next'));
    });
  });
}
