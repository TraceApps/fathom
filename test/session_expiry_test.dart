import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fathom/api/jellyfin_client.dart';
import 'package:fathom/models/session.dart';
import 'package:fathom/state/providers.dart';
import 'package:fathom/state/session_controller.dart';
import 'package:fathom/state/session_expiry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Jellyfin server: what it answers by path, and what it was asked.
class _Server implements HttpClientAdapter {
  /// The status for a path ending in the key; 200 otherwise.
  final Map<String, int> status;
  final List<String> asked = [];
  bool down = false;
  _Server(this.status);

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    asked.add(o.uri.path);
    if (down) {
      throw DioException.connectionError(requestOptions: o, reason: 'down');
    }
    var code = 200;
    for (final e in status.entries) {
      if (o.uri.path.endsWith(e.key)) code = e.value;
    }
    final data = o.uri.path.endsWith('Users/Me')
        ? {'Id': 'u1', 'Name': 'joe', 'Policy': <String, dynamic>{}}
        : {'Items': <Object>[]};
    return ResponseBody.fromString(
      jsonEncode(code == 200 ? data : {'error': code}),
      code,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _SignedIn extends SessionController {
  Session session;
  _SignedIn(this.session);
  @override
  Future<Session?> build() async => session;
  void replace(Session s) {
    session = s;
    state = AsyncData(s);
  }
}

const _joe = Session(
  baseUrl: 'http://jelly:8096',
  accessToken: 'token-one',
  userId: 'u1',
  userName: 'joe',
  serverName: 'Home',
  serverId: 's1',
);

JellyfinClient _client(_Server server) => JellyfinClient(
  deviceId: 'd1',
  httpClient: Dio()..httpClientAdapter = server,
);

// A sign-in token stops working when it's revoked, the device is removed or
// the user is deleted. Every request then came back "The server returned an
// error (401)", on every row, with nothing to do about it.
void main() {
  group('the client', () {
    test('tells of a refused token, in a header or an address', () async {
      final server = _Server({'UserViews': 401, 'Views': 401, 'stream': 401});
      final refused = <String>[];
      final c = _client(server)..onUnauthorized = refused.add;
      await expectLater(
        c.getUserViews(baseUrl: _joe.baseUrl, userId: 'u1', token: 'token-one'),
        throwsA(
          isA<JellyfinException>().having(
            (e) => e.message,
            'message',
            'Your sign-in to this server has ended. Sign in again.',
          ),
        ),
      );
      expect(refused.toSet(), {'token-one'});
      refused.clear();
      // A stream's address carries the token as api_key.
      await expectLater(
        (Dio()..httpClientAdapter = server).get<dynamic>(
          'http://jelly:8096/Videos/1/stream?api_key=token-one',
        ),
        throwsA(isA<DioException>()),
      );
      // (A bare Dio isn't the client: nothing is told.)
      expect(refused, isEmpty);
    });

    test('says nothing of a 401 that carried no token, or another refusal', () async {
      final server = _Server({'UserViews': 403, 'Views': 403});
      final refused = <String>[];
      final c = _client(server)..onUnauthorized = refused.add;
      await expectLater(
        c.getUserViews(baseUrl: _joe.baseUrl, userId: 'u1', token: 'token-one'),
        throwsA(isA<JellyfinException>()),
      );
      expect(refused, isEmpty);
    });

    test('tokenRefused: only a plain 401 means signed out', () async {
      final gone = _Server({'Users/Me': 401});
      final refused = <String>[];
      final c = _client(gone)..onUnauthorized = refused.add;
      expect(await c.tokenRefused(baseUrl: _joe.baseUrl, token: 't'), isTrue);
      // The question itself reports nothing.
      expect(refused, isEmpty);
      for (final code in [200, 403, 404, 500, 502]) {
        final s = _Server({'Users/Me': code});
        expect(
          await _client(s).tokenRefused(baseUrl: _joe.baseUrl, token: 't'),
          isFalse,
          reason: '$code',
        );
      }
      final down = _Server({})..down = true;
      expect(
        await _client(down).tokenRefused(baseUrl: _joe.baseUrl, token: 't'),
        isFalse,
      );
    });
  });

  group('the app', () {
    ProviderContainer app(_Server server, _SignedIn session) {
      final c = ProviderContainer(
        overrides: [
          deviceIdProvider.overrideWithValue('d1'),
          sessionControllerProvider.overrideWith(() => session),
          jellyfinClientProvider.overrideWith(
            (ref) => _client(server)
              ..onUnauthorized = (t) =>
                  ref.read(sessionExpiryProvider.notifier).refused(t),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<void> ask(ProviderContainer c, String token) async {
      try {
        await c
            .read(jellyfinClientProvider)
            .getUserViews(baseUrl: _joe.baseUrl, userId: 'u1', token: token);
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    test('a token the server no longer knows: sign in again', () async {
      final server = _Server({'UserViews': 401, 'Views': 401, 'Users/Me': 401});
      final session = _SignedIn(_joe);
      final c = app(server, session);
      await c.read(sessionControllerProvider.future);
      expect(c.read(sessionExpiredProvider), isFalse);
      await ask(c, 'token-one');
      expect(c.read(sessionExpiredProvider), isTrue);
      // Asked once, however many rows fail after that.
      final asked = server.asked.where((p) => p.endsWith('Users/Me')).length;
      await ask(c, 'token-one');
      await ask(c, 'token-one');
      expect(server.asked.where((p) => p.endsWith('Users/Me')).length, asked);
      // Signed in again: a new token, and nothing more to say.
      session.replace(
        const Session(
          baseUrl: 'http://jelly:8096',
          accessToken: 'token-two',
          userId: 'u1',
          userName: 'joe',
        ),
      );
      expect(c.read(sessionExpiredProvider), isFalse);
    });

    test('a 401 for one thing, from a server that still knows the token', () async {
      final server = _Server({'UserViews': 401, 'Views': 401});
      final session = _SignedIn(_joe);
      final c = app(server, session);
      await c.read(sessionControllerProvider.future);
      await ask(c, 'token-one');
      expect(server.asked.any((p) => p.endsWith('Users/Me')), isTrue);
      expect(c.read(sessionExpiredProvider), isFalse);
    });

    test('a 401 for another account\'s token says nothing of this one', () async {
      final server = _Server({'UserViews': 401, 'Views': 401, 'Users/Me': 401});
      final session = _SignedIn(_joe);
      final c = app(server, session);
      await c.read(sessionControllerProvider.future);
      await ask(c, 'someone-else');
      expect(server.asked.any((p) => p.endsWith('Users/Me')), isFalse);
      expect(c.read(sessionExpiredProvider), isFalse);
    });

    test('the real client is wired to it', () async {
      final session = _SignedIn(_joe);
      final c = ProviderContainer(
        overrides: [
          deviceIdProvider.overrideWithValue('d1'),
          sessionControllerProvider.overrideWith(() => session),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(jellyfinClientProvider).onUnauthorized, isNotNull);
    });
  });
}
