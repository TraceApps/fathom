import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fathom/api/mdblist_client.dart';
import 'package:fathom/api/seerr_client.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/session.dart';
import 'package:fathom/screens/arr_settings_screen.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/session_controller.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// Connections: Seerr and MDBList stand in the same list as the Manage apps
// and work the same way. Save & Test tries before it saves, a failure says
// why and offers Save Anyway, and Disconnect asks first.

class _FakePrefs extends PreferencesController {
  _FakePrefs(this.initial);
  final Prefs initial;
  @override
  Future<Prefs> build() async => initial;
  @override
  Future<void> edit(Prefs Function(Prefs) change) async {
    state = AsyncData(change(state.asData?.value ?? initial));
  }
}

class _SignedOut extends SessionController {
  @override
  Future<Session?> build() async => null;
}

/// Answers each path with a status and a body.
class _Answers implements HttpClientAdapter {
  _Answers(this.answers);
  final Map<String, (int, Object?)> answers;
  final asked = <String>[];
  final headers = <String, Map<String, dynamic>>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    asked.add(o.uri.path);
    headers[o.uri.path] = o.headers;
    final (code, body) = answers[o.uri.path] ?? (404, null);
    return ResponseBody.fromString(
      jsonEncode(body),
      code,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 200));
  }
}

typedef _Tester =
    Future<String> Function(ConnApp app, String url, String user, String key);

Future<ProviderContainer> _open(
  WidgetTester t, {
  Prefs prefs = const Prefs(),
  required _Tester tester,
  Widget home = const ArrSettingsScreen(),
  Size size = const Size(500, 1400),
}) async {
  final container = ProviderContainer(
    overrides: [
      preferencesProvider.overrideWith(() => _FakePrefs(prefs)),
      sessionControllerProvider.overrideWith(_SignedOut.new),
      connTesterProvider.overrideWithValue(tester),
    ],
  );
  addTearDown(container.dispose);
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(const Color(0xFF8AB4F8)),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await _settle(t);
  return container;
}

Future<void> _add(WidgetTester t, String app) async {
  await t.tap(find.text('Add Connection'));
  await _settle(t);
  await t.tap(
    find.descendant(of: find.byType(AlertDialog), matching: find.text(app)),
  );
  await _settle(t);
}

Prefs _prefs(ProviderContainer c) => c.read(preferencesProvider).requireValue;

void main() {
  group('Seerr check', () {
    SeerrClient client(_Answers a, {String? cookie}) => SeerrClient(
      'http://s',
      'key',
      cookie: cookie,
      dio: Dio()..httpClientAdapter = a,
    );

    test('a wrong key is refused, though its status answers anyone', () async {
      final a = _Answers({
        '/api/v1/status': (200, {'version': '2.7.3'}),
        '/api/v1/auth/me': (403, {'message': 'no'}),
      });
      await expectLater(
        client(a).version(),
        throwsA(
          isA<SeerrException>().having(
            (e) => e.message,
            'message',
            'Seerr rejected the API key.',
          ),
        ),
      );
      expect(a.asked, ['/api/v1/status', '/api/v1/auth/me']);
    });

    test('the right key gives the version; the key goes only to Seerr', () async {
      final a = _Answers({
        '/api/v1/status': (200, {'version': '2.7.3'}),
        '/api/v1/auth/me': (200, {'id': 1}),
      });
      expect(await client(a).version(), '2.7.3');
      expect(a.headers['/api/v1/auth/me']!['X-Api-Key'], 'key');
      // The open status call is asked without it.
      expect(a.headers['/api/v1/status']!.containsKey('X-Api-Key'), isFalse);
    });

    test('an ended sign-in says to sign in again', () async {
      final a = _Answers({
        '/api/v1/status': (200, {'version': '2.7.3'}),
        '/api/v1/auth/me': (401, null),
      });
      await expectLater(
        client(a, cookie: 'connect.sid=x').version(),
        throwsA(
          isA<SeerrException>().having(
            (e) => e.message,
            'message',
            contains('Sign in again'),
          ),
        ),
      );
    });

    test('another app at the address, or nothing, is said', () async {
      await expectLater(
        client(_Answers({'/api/v1/status': (200, {'app': 'other'})})).version(),
        throwsA(
          isA<SeerrException>().having(
            (e) => e.message,
            'message',
            "This address doesn't answer as Seerr.",
          ),
        ),
      );
      await expectLater(
        client(_Answers({})).version(),
        throwsA(
          isA<SeerrException>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
    });
  });

  group('MDBList check', () {
    test('a refused key is said; a good one passes', () async {
      final bad = _Answers({'/user': (403, {'error': 'Invalid API key'})});
      await expectLater(
        MdbListClient('k', dio: Dio()..httpClientAdapter = bad).check(),
        throwsA(
          isA<MdbListException>().having(
            (e) => e.message,
            'message',
            'MDBList rejected the API key.',
          ),
        ),
      );
      final good = _Answers({'/user': (200, {'api_requests': 1000})});
      await MdbListClient('k', dio: Dio()..httpClientAdapter = good).check();
      expect(good.asked, ['/user']);
    });
  });

  test('the list holds Seerr and MDBList, and Settings counts them', () {
    const p = Prefs(
      seerrUrl: 'http://s:5055',
      seerrAuthMode: 'cookie',
      seerrCookie: 'connect.sid=x',
      seerrApiKey: 'old',
      mdbListApiKey: 'mk',
      radarrUrl: 'http://r:7878',
      radarrApiKey: 'rk',
    );
    final all = connectionsOf(p);
    expect([for (final c in all) c.app], [
      ConnApp.seerr,
      ConnApp.radarr,
      ConnApp.mdblist,
    ]);
    // Signed in with an account: checked with that session, not the key.
    expect((all.first.user, all.first.secret), (seerrSession, 'connect.sid=x'));
    // Signed out again, with no key: it needs one, and isn't tried.
    final out = connectionsOf(
      const Prefs(seerrUrl: 'http://s:5055'),
    ).single;
    expect(out.ready, isFalse);
  });

  testWidgets('every app is in Add Connection, under its kind', (t) async {
    await _open(t, tester: (_, _, _, _) async => '1');
    await t.tap(find.text('Add Connection'));
    await _settle(t);
    final dialog = find.byType(AlertDialog);
    for (final text in [
      'Requests',
      'Seerr',
      'Apps',
      'Download Clients',
      'Ratings',
      'MDBList',
    ]) {
      expect(
        find.descendant(of: dialog, matching: find.text(text)),
        findsOneWidget,
        reason: text,
      );
    }
  });

  testWidgets('Seerr: a failed test saves nothing, and says why', (t) async {
    var fail = true;
    final tried = <(ConnApp, String, String, String)>[];
    final c = await _open(
      t,
      tester: (app, url, user, key) async {
        tried.add((app, url, user, key));
        if (fail) throw SeerrException('Seerr rejected the API key.');
        return '2.7.3';
      },
    );
    await _add(t, 'Seerr');
    expect(find.text('http://192.168.1.10:5055'), findsOneWidget);
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), '10.0.0.5:5055');
    await t.enterText(fields.at(1), 'wrong');
    await t.tap(find.text('Save & Test'));
    await _settle(t);
    expect(tried.single, (ConnApp.seerr, 'http://10.0.0.5:5055', '', 'wrong'));
    expect(
      find.text("Couldn't connect: Seerr rejected the API key."),
      findsOneWidget,
    );
    expect(_prefs(c).seerrUrl, isEmpty);
    // Right key: saved, and said.
    fail = false;
    await t.enterText(fields.at(1), 'right');
    await t.tap(find.text('Save & Test'));
    await _settle(t);
    expect(find.text('Connected to Seerr 2.7.3'), findsOneWidget);
    final p = _prefs(c);
    expect(
      (p.seerrUrl, p.seerrApiKey, p.seerrAuthMode),
      ('http://10.0.0.5:5055', 'right', 'apikey'),
    );
    expect(find.text("Couldn't connect: Seerr rejected the API key."), findsNothing);
  });

  testWidgets('Seerr: Save Anyway keeps it after a failed test', (t) async {
    final c = await _open(
      t,
      tester: (_, _, _, _) async => throw SeerrException('Could not reach Seerr.'),
    );
    await _add(t, 'Seerr');
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'http://s:5055/');
    await t.enterText(fields.at(1), 'k');
    expect(find.text('Save Anyway'), findsNothing);
    await t.tap(find.text('Save & Test'));
    await _settle(t);
    await t.tap(find.text('Save Anyway'));
    await _settle(t);
    expect((_prefs(c).seerrUrl, _prefs(c).seerrApiKey), ('http://s:5055', 'k'));
  });

  testWidgets('Seerr: nothing is tried with a field empty', (t) async {
    var tried = 0;
    final c = await _open(
      t,
      tester: (_, _, _, _) async {
        tried++;
        return '1';
      },
    );
    await _add(t, 'Seerr');
    await t.enterText(find.byType(TextField).at(0), 'http://s:5055');
    await t.tap(find.text('Save & Test'));
    await _settle(t);
    expect(tried, 0);
    expect(_prefs(c).seerrUrl, isEmpty);
  });

  testWidgets('Seerr: its row, and Disconnect asks before removing all of it', (
    t,
  ) async {
    final c = await _open(
      t,
      prefs: const Prefs(
        seerrUrl: 'http://s:5055',
        seerrApiKey: 'k',
        seerrCookie: 'connect.sid=old',
      ),
      tester: (_, _, _, _) async => '2.7.3',
    );
    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('s:5055 · 2.7.3'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    await t.tap(find.text('Seerr'));
    await _settle(t);
    await t.tap(find.text('Disconnect'));
    await _settle(t);
    expect(find.text('Disconnect Seerr?'), findsOneWidget);
    // Cancel keeps it.
    await t.tap(find.text('Cancel'));
    await _settle(t);
    expect(_prefs(c).seerrUrl, 'http://s:5055');
    await t.tap(find.text('Disconnect'));
    await _settle(t);
    await t.tap(find.widgetWithText(FilledButton, 'Disconnect'));
    await _settle(t);
    final p = _prefs(c);
    expect((p.seerrUrl, p.seerrApiKey, p.seerrCookie), ('', '', ''));
    // Back on the list, with nothing connected.
    expect(find.text('Requests'), findsNothing);
    expect(find.text('Add Connection'), findsOneWidget);
  });

  testWidgets('Seerr opens beside the list in a wide window', (t) async {
    await _open(
      t,
      prefs: const Prefs(seerrUrl: 'http://s:5055', seerrApiKey: 'k'),
      tester: (_, _, _, _) async => '2.7.3',
      size: const Size(1300, 900),
    );
    await t.tap(find.text('Seerr'));
    await _settle(t);
    // The list is still there, with the page beside it.
    expect(find.text('Add Connection'), findsOneWidget);
    expect(find.text('Save & Test'), findsOneWidget);
    expect(find.text('Seerr 2.7.3'), findsOneWidget);
  });

  testWidgets('MDBList: a key and no address, tested before it is saved', (
    t,
  ) async {
    var fail = true;
    final c = await _open(
      t,
      tester: (app, url, user, key) async {
        expect((app, url, key), (ConnApp.mdblist, '', 'mk'));
        if (fail) throw MdbListException('MDBList rejected the API key.');
        return '';
      },
    );
    await _add(t, 'MDBList');
    // Only the key to enter.
    expect(find.byType(TextField), findsOneWidget);
    await t.tap(find.text('Save & Test'));
    await _settle(t);
    expect(find.text('Enter the API key'), findsOneWidget);
    await t.enterText(find.byType(TextField), ' mk ');
    await t.tap(find.text('Save & Test'));
    await _settle(t);
    expect(
      find.text("Couldn't connect: MDBList rejected the API key."),
      findsOneWidget,
    );
    expect(_prefs(c).mdbListApiKey, isEmpty);
    fail = false;
    await t.tap(find.text('Save & Test'));
    await _settle(t);
    expect(find.text('Connected to MDBList'), findsOneWidget);
    expect(_prefs(c).mdbListApiKey, 'mk');
    // Its row, under Ratings, with where it is in place of an address.
    await t.pageBack();
    await _settle(t);
    expect(find.text('Ratings'), findsOneWidget);
    expect(find.text('mdblist.com'), findsOneWidget);
  });

  testWidgets('MDBList on its own page (from Ratings): Disconnect drops the key', (
    t,
  ) async {
    final c = await _open(
      t,
      prefs: const Prefs(mdbListApiKey: 'mk', showLetterboxd: true),
      tester: (_, _, _, _) async => '',
      home: const ConnectionScreen(ConnApp.mdblist),
    );
    expect(find.text('Connected'), findsOneWidget);
    await t.tap(find.text('Disconnect'));
    await _settle(t);
    await t.tap(find.widgetWithText(FilledButton, 'Disconnect'));
    await _settle(t);
    expect(_prefs(c).mdbListApiKey, isEmpty);
    // What it was showing is left as chosen, for when a key comes back.
    expect(_prefs(c).showLetterboxd, isTrue);
  });

  test('Settings has one way in: no Seerr row of its own, no key field', () {
    final settings = File('lib/screens/settings_screen.dart').readAsStringSync();
    expect(settings.contains("'/seerr-settings'"), isFalse);
    expect(settings.contains("'/arr-settings'"), isTrue);
    final prefs = File('lib/screens/preferences_screen.dart').readAsStringSync();
    expect(prefs.contains('mdbListApiKey: v'), isFalse);
    expect(prefs.contains("'/connections/mdblist'"), isTrue);
  });
}
