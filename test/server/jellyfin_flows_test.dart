import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fathom/state/library_providers.dart' show favoriteItemTypes;
import 'package:fathom/api/jellyfin_client.dart';
import 'package:flutter_test/flutter_test.dart';

// The core flows against a real Jellyfin server: sign in, browse, play,
// resume, mark watched, subtitles. Every other test answers for the server;
// this one asks a real one, old and current, so a server change that breaks
// Fathom fails a check instead of reaching someone's living room.
//
// Skipped unless FATHOM_JELLYFIN_URL is set. tool/server_test_setup.sh
// starts the server and prints what to set; CI does that for each version.

void main() {
  final url = Platform.environment['FATHOM_JELLYFIN_URL'];
  final username = Platform.environment['FATHOM_JELLYFIN_USER'] ?? 'tester';
  final password =
      Platform.environment['FATHOM_JELLYFIN_PASSWORD'] ?? 'fathom-test';
  final skip = url == null || url.isEmpty
      ? 'needs a server: run tool/server_test_setup.sh'
      : false;

  final client = JellyfinClient(deviceId: 'fathom-server-test');
  late String token;
  late String userId;
  late String movieId;

  const tick = 10000000; // one second, as Jellyfin counts

  group('a real Jellyfin server', skip: skip, () {
    setUpAll(() async {
      final auth = await client.authenticateByName(
        baseUrl: url!,
        username: username,
        password: password,
      );
      token = auth.accessToken;
      userId = auth.user.id;
    });

    test('says what it is before anyone signs in', () async {
      final found = await client.resolvePublicServer(url!);
      expect(found.baseUrl, url);
      expect(found.info.version, isNotEmpty);
      // ignore: avoid_print
      print('Jellyfin ${found.info.version}');
    });

    test('a wrong password is refused in plain words', () async {
      await expectLater(
        client.authenticateByName(
          baseUrl: url!,
          username: username,
          password: 'not-the-password',
        ),
        throwsA(
          isA<JellyfinException>().having(
            (e) => e.message,
            'message',
            'Incorrect username or password.',
          ),
        ),
      );
    });

    test('lists the libraries, and the movie in one', () async {
      final views = await client.getUserViews(
        baseUrl: url!,
        userId: userId,
        token: token,
      );
      final movies = views.firstWhere((v) => v.collectionType == 'movies');
      final page = await client.getItems(
        baseUrl: url,
        userId: userId,
        token: token,
        parentId: movies.id,
        includeItemTypes: 'Movie',
        recursive: true,
      );
      expect(page.totalRecordCount, 1);
      expect(page.items.single.name, contains('Fathom Test Movie'));
      movieId = page.items.single.id;
    });

    test('searching the library finds it, and a wrong word finds nothing', () async {
      Future<int> found(String term) async => (await client.getItems(
        baseUrl: url!,
        userId: userId,
        token: token,
        includeItemTypes: 'Movie',
        recursive: true,
        searchTerm: term,
      )).totalRecordCount;
      expect(await found('fathom test'), 1);
      expect(await found('zzzznothing'), 0);
    });

    test('opens a stream that really plays', () async {
      final stream = await client.openVideoStream(
        baseUrl: url!,
        userId: userId,
        token: token,
        itemId: movieId,
      );
      // The first bytes of the file itself, as a player would ask for them.
      final res = await Dio().get<List<int>>(
        stream,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Range': 'bytes=0-1023'},
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      expect(res.data, isNotEmpty);
    });

    test('remembers where playback stopped, and offers to resume', () async {
      await client.reportPlaybackStart(
        baseUrl: url!,
        token: token,
        itemId: movieId,
        positionTicks: 0,
      );
      await client.reportPlaybackProgress(
        baseUrl: url,
        token: token,
        itemId: movieId,
        positionTicks: 120 * tick,
      );
      await client.reportPlaybackStopped(
        baseUrl: url,
        token: token,
        itemId: movieId,
        positionTicks: 120 * tick,
      );
      final item = await client.getItem(
        baseUrl: url,
        userId: userId,
        token: token,
        itemId: movieId,
      );
      expect(item.userData.playbackPositionTicks, 120 * tick);
      final resume = await client.getResumeItems(
        baseUrl: url,
        userId: userId,
        token: token,
      );
      expect(resume.map((i) => i.id), contains(movieId));
    });

    test('marks it watched, and unwatched again', () async {
      Future<bool> played() async => (await client.getItem(
        baseUrl: url!,
        userId: userId,
        token: token,
        itemId: movieId,
      )).userData.played;
      await client.setPlayed(
        baseUrl: url!,
        userId: userId,
        token: token,
        itemId: movieId,
        played: true,
      );
      expect(await played(), isTrue);
      await client.setPlayed(
        baseUrl: url,
        userId: userId,
        token: token,
        itemId: movieId,
        played: false,
      );
      expect(await played(), isFalse);
    });

    test('a favorite sticks', () async {
      await client.setFavorite(
        baseUrl: url!,
        userId: userId,
        token: token,
        itemId: movieId,
        favorite: true,
      );
      final favorites = await client.getItems(
        baseUrl: url,
        userId: userId,
        token: token,
        includeItemTypes: 'Movie',
        recursive: true,
        isFavorite: true,
      );
      expect(favorites.items.map((i) => i.id), contains(movieId));
    });

    test('Favorites lists a favorite person, on old servers too', () async {
      // Jellyfin 10.8 and 10.10 leave people out of /Items even when asked
      // for them; Favorites asks /Persons, which every version answers.
      final movie = await client.getItem(
        baseUrl: url!,
        userId: userId,
        token: token,
        itemId: movieId,
      );
      final actor = movie.people.firstWhere((p) => p.name == 'Fathom Test Actor');
      await client.setFavorite(
        baseUrl: url,
        userId: userId,
        token: token,
        itemId: actor.id,
        favorite: true,
      );
      final people = await client.getFavoritePeople(
        baseUrl: url,
        userId: userId,
        token: token,
      );
      expect(people.map((p) => p.id), contains(actor.id));
      expect(people.single.type, 'Person');
      // And the media list Favorites asks for still has the movie.
      final items = await client.getItems(
        baseUrl: url,
        userId: userId,
        token: token,
        includeItemTypes: favoriteItemTypes,
        recursive: true,
        isFavorite: true,
      );
      expect(items.items.map((i) => i.id), contains(movieId));
    });

    test('searching finds a person by name, on old servers too', () async {
      // 10.8 and 10.10 leave people out of an /Items search; Search asks
      // /Persons for them.
      final people = await client.searchPeople(
        baseUrl: url!,
        userId: userId,
        token: token,
        searchTerm: 'Test Actor',
      );
      expect(people.map((p) => p.name), contains('Fathom Test Actor'));
      final none = await client.searchPeople(
        baseUrl: url,
        userId: userId,
        token: token,
        searchTerm: 'nobody-by-this-name',
      );
      expect(none, isEmpty);
    });

    test('a playlist can be renamed, on old servers too', () async {
      // 10.9 and later rename with POST /Playlists/{id}; 10.8 has no such
      // route and takes the whole item back with its new name.
      final id = await client.createPlaylist(
        baseUrl: url!,
        userId: userId,
        token: token,
        name: 'Before',
      );
      await client.renamePlaylist(
        baseUrl: url,
        userId: userId,
        token: token,
        playlistId: id,
        name: 'After',
      );
      final lists = await client.getPlaylists(
        baseUrl: url,
        userId: userId,
        token: token,
      );
      expect(lists.where((p) => p.id == id).single.name, 'After');
      await client.deleteItem(baseUrl: url, token: token, itemId: id);
    });

    test('a playlist can hold the same title twice, and lose one of them',
        () async {
      // 10.9 and later give both copies one entry id, so removing "one" by
      // that id removes both: Fathom sends the whole list instead. 10.8
      // has no such route, and keeps repeats apart by itself.
      final found = await client.resolvePublicServer(url!);
      final v = (found.info.version ?? '').split('.').map(int.tryParse).toList();
      if (v.length < 2) return;
      if ((v[0] ?? 0) == 10 && (v[1] ?? 0) < 9) return;
      final id = await client.createPlaylist(
        baseUrl: url,
        userId: userId,
        token: token,
        name: 'Twice',
      );
      Future<List<String>> entries() async => [
            for (final i in await client.getPlaylistItems(
              baseUrl: url,
              userId: userId,
              token: token,
              playlistId: id,
            ))
              i.id,
          ];
      await client.setPlaylistItems(
          baseUrl: url, token: token, playlistId: id, itemIds: [movieId, movieId]);
      final held = await entries();
      // 10.10 keeps one of each title in a playlist, so there's nothing to
      // tell apart there; the current server holds both.
      expect(held.toSet(), {movieId});
      expect(held.length, inInclusiveRange(1, 2));
      await client.setPlaylistItems(
          baseUrl: url, token: token, playlistId: id, itemIds: [movieId]);
      expect(await entries(), [movieId]);
      await client.deleteItem(baseUrl: url, token: token, itemId: id);
    });

    test('serves the subtitle that sits beside the video', () async {
      final item = await client.getItem(
        baseUrl: url!,
        userId: userId,
        token: token,
        itemId: movieId,
      );
      final track = item.subtitleStreams.firstWhere((s) => s.isExternal);
      final address = client.subtitleUrl(
        baseUrl: url,
        token: token,
        itemId: movieId,
        index: track.index,
        deliveryUrl: track.deliveryUrl,
        mediaSourceId: item.mediaSourceId,
        codec: track.codec,
      );
      final res = await Dio().get<String>(
        address,
        options: Options(responseType: ResponseType.plain),
      );
      expect(res.data, contains('A line of the test subtitle.'));
    });
  });
}
