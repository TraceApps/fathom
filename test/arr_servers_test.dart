import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/arr.dart';
import 'package:fathom/models/session.dart';
import 'package:fathom/screens/arr_screen.dart';
import 'package:fathom/screens/arr_settings_screen.dart';
import 'package:fathom/services/settings_backup.dart';
import 'package:fathom/services/tv_mode.dart';
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/arr_servers.dart';
import 'package:fathom/state/download_providers.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/session_controller.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/arr_servers_ui.dart';
import 'package:fathom/widgets/tv_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// More than one server of an app: a 4K Radarr beside the usual one. One is
// in use at a time, in the usual fields, so every page follows it; the
// others wait with their own Defaults for New Titles. Switching swaps them.

const _main = Prefs(
  radarrUrl: 'http://radarr:7878',
  radarrApiKey: 'mainkey',
  radarrAddDefaults: {'qualityProfileId': 4, 'rootFolder': '/movies'},
);

Prefs _withFourK() => arrAddServer(
  _main,
  ArrKind.radarr,
  name: '4K',
  url: 'http://radarr4k:7878',
  apiKey: '4kkey',
);

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

/// Radarr as it answers its status, by address: which server was asked.
class _Radarrs implements HttpClientAdapter {
  final List<String> hosts = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    hosts.add(o.uri.host);
    final key = o.headers['X-Api-Key'];
    final ok =
        (o.uri.host == 'radarr' && key == 'mainkey') ||
        (o.uri.host == 'radarr4k' && key == '4kkey');
    final path = o.uri.path;
    final data = !ok
        ? null
        : path.endsWith('system/status')
        ? {'appName': 'Radarr', 'version': '6.0.4'}
        : <Object>[];
    return ResponseBody.fromString(
      jsonEncode(data ?? {'message': 'Unauthorized'}),
      ok ? 200 : 401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('the servers, saved', () {
    test('one server: in use, no name, no id yet', () {
      final all = arrServersOf(_main, ArrKind.radarr);
      expect(all, hasLength(1));
      expect(all.single.active, isTrue);
      expect(all.single.name, isEmpty);
      expect(arrServersOf(_main, ArrKind.sonarr), isEmpty);
    });

    test('another added waits, its key apart', () {
      final p = _withFourK();
      final all = arrServersOf(p, ArrKind.radarr);
      expect([for (final s in all) (s.name, s.active)], [
        ('', true),
        ('4K', false),
      ]);
      // The one in use is unchanged.
      expect(p.radarrUrl, 'http://radarr:7878');
      // The key isn't in the saved list: only in the key map.
      expect(jsonEncode(p.arrServers), isNot(contains('4kkey')));
      expect(p.arrServerKeys.values, ['4kkey']);
    });

    test('switching swaps them, each with its own defaults', () {
      final p = _withFourK();
      final fourK = arrServersOf(p, ArrKind.radarr)[1];
      final q = arrSwitchServer(p, ArrKind.radarr, fourK.id);
      expect((q.radarrUrl, q.radarrApiKey), ('http://radarr4k:7878', '4kkey'));
      // The 4K one has no defaults of its own yet: not the other's.
      expect(q.radarrAddDefaults, isEmpty);
      final all = arrServersOf(q, ArrKind.radarr);
      expect([for (final s in all) (s.name, s.active)], [
        ('4K', true),
        ('', false),
      ]);
      // And back: the first one's defaults came with it.
      final back = arrSwitchServer(q, ArrKind.radarr, all[1].id);
      expect(back.radarrUrl, 'http://radarr:7878');
      expect(back.radarrApiKey, 'mainkey');
      expect(back.radarrAddDefaults, _main.radarrAddDefaults);
      expect(arrServersOf(back, ArrKind.radarr), hasLength(2));
      // Keys follow their servers, and none is left over.
      expect(back.arrServerKeys.values, ['4kkey']);
    });

    test('a switch to what isn\'t there changes nothing', () {
      final p = _withFourK();
      expect(identical(arrSwitchServer(p, ArrKind.radarr, 'nope'), p), isTrue);
      // Nor to the one in use.
      final id = arrServersOf(p, ArrKind.radarr).first.id;
      expect(identical(arrSwitchServer(p, ArrKind.radarr, id), p), isTrue);
    });

    test('the first server of an app goes straight in use', () {
      final p = arrAddServer(
        const Prefs(),
        ArrKind.sonarr,
        name: 'Anime',
        url: 'http://s',
        apiKey: 'k',
      );
      expect((p.sonarrUrl, p.sonarrApiKey), ('http://s', 'k'));
      expect(arrServersOf(p, ArrKind.sonarr).single.name, 'Anime');
      expect(p.arrServers, isEmpty);
    });

    test('remove and rename; a restored one needs its key', () {
      var p = _withFourK();
      final fourK = arrServersOf(p, ArrKind.radarr)[1];
      p = arrEditServer(p, ArrKind.radarr, fourK.id, name: 'UHD');
      expect(arrServersOf(p, ArrKind.radarr)[1].name, 'UHD');
      // The one in use gets a name too.
      final main = arrServersOf(p, ArrKind.radarr).first;
      p = arrEditServer(p, ArrKind.radarr, main.id, name: 'HD');
      expect(arrServersOf(p, ArrKind.radarr).first.name, 'HD');
      expect(p.radarrUrl, 'http://radarr:7878');
      // A backup has the list without the keys.
      final restored = Prefs.fromJson({
        for (final e in p.toJson().entries)
          if (!secretPrefKeys.contains(e.key)) e.key: e.value,
      });
      final waiting = arrServersOf(restored, ArrKind.radarr)[1];
      expect(waiting.ready, isFalse);
      p = arrRemoveServer(p, fourK.id);
      expect(arrServersOf(p, ArrKind.radarr), hasLength(1));
      expect(p.arrServerKeys, isEmpty);
    });

    test('disconnecting the one in use puts the next in use', () {
      final p = arrDisconnectActive(_withFourK(), ArrKind.radarr);
      expect(p.radarrUrl, 'http://radarr4k:7878');
      expect(p.radarrApiKey, '4kkey');
      final all = arrServersOf(p, ArrKind.radarr);
      expect([for (final s in all) (s.name, s.active)], [('4K', true)]);
      expect(p.arrServerKeys, isEmpty);
      // The last one: simply disconnected, its defaults kept as before.
      final none = arrDisconnectActive(_main, ArrKind.radarr);
      expect(none.radarrUrl, isEmpty);
      expect(none.radarrApiKey, isEmpty);
      expect(none.radarrAddDefaults, _main.radarrAddDefaults);
    });

    test('a backup made with the other in use: keys follow addresses', () {
      // This device: Main in use, 4K saved.
      final local = _withFourK();
      // The backup: made while 4K was in use (so without any keys).
      final fourK = arrServersOf(local, ArrKind.radarr)[1];
      final made = arrSwitchServer(local, ArrKind.radarr, fourK.id);
      final backup = {
        for (final e in made.toJson().entries)
          if (!secretPrefKeys.contains(e.key)) e.key: e.value,
      };
      // Restored as the restore does: the backup over this device's
      // settings, this device's keys kept.
      final merged = Prefs.fromJson({...local.toJson(), ...backup});
      final p = arrReconcileRestore(local, merged);
      expect((p.radarrUrl, p.radarrApiKey), ('http://radarr4k:7878', '4kkey'));
      final all = arrServersOf(p, ArrKind.radarr);
      expect([for (final s in all) (s.url, s.apiKey, s.active)], [
        ('http://radarr4k:7878', '4kkey', true),
        ('http://radarr:7878', 'mainkey', false),
      ]);
      // And switching back loses nothing.
      final back = arrSwitchServer(p, ArrKind.radarr, all[1].id);
      expect((back.radarrUrl, back.radarrApiKey), ('http://radarr:7878', 'mainkey'));
      expect(arrServersOf(back, ArrKind.radarr)[1].apiKey, '4kkey');
    });

    test('an old backup (one server) after a switch: no server twice', () {
      final two = _withFourK();
      final fourK = arrServersOf(two, ArrKind.radarr)[1];
      final local = arrSwitchServer(two, ArrKind.radarr, fourK.id);
      expect(local.radarrUrl, 'http://radarr4k:7878');
      // From before there were servers: Main's address and defaults only.
      final merged = Prefs.fromJson({
        ...local.toJson(),
        'radarrUrl': 'http://radarr:7878',
        'radarrAddDefaults': _main.radarrAddDefaults,
      });
      final p = arrReconcileRestore(local, merged);
      final all = arrServersOf(p, ArrKind.radarr);
      expect([for (final s in all) (s.name, s.url, s.apiKey, s.active)], [
        ('', 'http://radarr:7878', 'mainkey', true),
        ('4K', 'http://radarr4k:7878', '4kkey', false),
      ]);
    });

    test('a restored list with one address twice keeps it once', () {
      final local = _withFourK();
      final saved = local.arrServers.single;
      final merged = local.copyWith(
        arrServers: [
          saved,
          {...saved, 'id': 'copy', 'name': '4K copy'},
        ],
      );
      final p = arrReconcileRestore(local, merged);
      expect(arrServersOf(p, ArrKind.radarr), hasLength(2));
    });

    test('restored on a new device: servers come, keys don\'t', () {
      final backup = {
        for (final e in _withFourK().toJson().entries)
          if (!secretPrefKeys.contains(e.key)) e.key: e.value,
      };
      final p = arrReconcileRestore(
        const Prefs(),
        Prefs.fromJson({...const Prefs().toJson(), ...backup}),
      );
      expect(p.radarrUrl, 'http://radarr:7878');
      expect(p.radarrApiKey, isEmpty);
      expect(arrServersOf(p, ArrKind.radarr)[1].ready, isFalse);
      // Nothing to put in use instead of it: disconnecting leaves the
      // keyless one saved.
      final off = arrDisconnectActive(p, ArrKind.radarr);
      expect(off.radarrUrl, isEmpty);
      expect(arrServersOf(off, ArrKind.radarr), hasLength(1));
    });

    test('the first server keeps the defaults set before', () {
      final p = arrAddServer(
        const Prefs(radarrAddDefaults: {'qualityProfileId': 7}),
        ArrKind.radarr,
        name: '',
        url: 'http://r',
        apiKey: 'k',
      );
      expect(p.radarrAddDefaults, {'qualityProfileId': 7});
    });

    test('the keys stay out of backups', () {
      expect(secretPrefKeys, contains('arrServerKeys'));
      final p = _withFourK();
      final back = Prefs.fromJson(p.toJson());
      expect(back.arrServers, p.arrServers);
      expect(back.arrServerKeys, p.arrServerKeys);
    });

    test('a switch shows once an app has two', () {
      ProviderContainer with_(Prefs p) => ProviderContainer(
        overrides: [preferencesProvider.overrideWith(() => _FakePrefs(p))],
      );
      final one = with_(_main);
      final two = with_(_withFourK());
      addTearDown(one.dispose);
      addTearDown(two.dispose);
      one.listen(preferencesProvider, (_, _) {});
      two.listen(preferencesProvider, (_, _) {});
      return Future.wait([
        one.read(preferencesProvider.future),
        two.read(preferencesProvider.future),
      ]).then((_) {
        expect(one.read(arrMultiServerKindsProvider), isEmpty);
        expect(two.read(arrMultiServerKindsProvider), [ArrKind.radarr]);
      });
    });
  });

  group('on screen', () {
    // Settings tries a connection through this: a Radarr at each address,
    // taking its own key, and nothing else answering.
    Future<String> radarrs(ConnApp app, String url, String user, String key) async {
      final host = Uri.parse(url).host;
      if ((host == 'radarr' && key == 'mainkey') ||
          (host == 'radarr4k' && key == '4kkey') ||
          (host == 'radarr3' && key == 'k3')) {
        return '6.0.4';
      }
      throw ArrException('Radarr rejected the API key.');
    }

    Future<ProviderContainer> settings(
      WidgetTester t,
      Prefs p, {
      Size size = const Size(500, 1400),
    }) async {
      final container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith(() => _FakePrefs(p)),
          connTesterProvider.overrideWithValue(radarrs),
          radarrClientProvider.overrideWithValue(null),
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
            home: const ArrSettingsScreen(),
          ),
        ),
      );
      await _settle(t);
      return container;
    }

    Finder field(int i) => find.byType(TextField).at(i);
    Finder inDialog(String text) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(text),
    );

    testWidgets('Settings: each server a row, Add, and Use This One', (
      t,
    ) async {
      final container = await settings(t, _main);
      // One row: the app, its address, its version, how it's doing.
      expect(find.text('Radarr'), findsOneWidget);
      expect(find.text('radarr:7878 · 6.0.4'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      // The one there always was has an id to be opened by.
      var p = container.read(preferencesProvider).requireValue;
      expect(arrServersOf(p, ArrKind.radarr).single.id, 'main-radarr');
      // Add Connection: Radarr is there already, so it's another server.
      await t.tap(find.text('Add Connection'));
      await _settle(t);
      expect(find.text('Add another server, such as a 4K one'), findsOneWidget);
      expect(find.text('Shows'), findsOneWidget);
      await t.tap(inDialog('Radarr'));
      await _settle(t);
      // Its usual address is taken (that's the one there is): left empty.
      expect(t.widget<TextField>(field(0)).controller!.text, '');
      await t.enterText(field(2), '4K');
      await t.tap(find.text('Save & Test'));
      await _settle(t);
      expect(
        find.text('Enter the server address and the API key'),
        findsOneWidget,
      );
      // A key the server refuses: said on the page, and nothing saved.
      await t.enterText(field(0), 'radarr4k:7878');
      await t.enterText(field(1), 'wrong');
      await t.tap(find.text('Save & Test'));
      await _settle(t);
      expect(
        find.text("Couldn't connect: Radarr rejected the API key."),
        findsOneWidget,
      );
      expect(find.text('Save Anyway'), findsOneWidget);
      p = container.read(preferencesProvider).requireValue;
      expect(p.arrServers, isEmpty);
      // The right one: saved, and the page is that server now.
      await t.enterText(field(1), '4kkey');
      await t.tap(find.text('Save & Test'));
      await _settle(t);
      expect(find.text('Connected to Radarr 6.0.4'), findsOneWidget);
      expect(find.text('Save Anyway'), findsNothing);
      expect(find.text('Disconnect'), findsOneWidget);
      p = container.read(preferencesProvider).requireValue;
      expect([
        for (final s in arrServersOf(p, ArrKind.radarr)) (s.name, s.url, s.active),
      ], [
        ('', 'http://radarr:7878', true),
        ('4K', 'http://radarr4k:7878', false),
      ]);
      expect(find.text('Radarr: 4K'), findsOneWidget); // the page's title
      // Not in use: it can be.
      await t.tap(find.text('Use This One'));
      await _settle(t);
      p = container.read(preferencesProvider).requireValue;
      expect(p.radarrUrl, 'http://radarr4k:7878');
      expect(find.text('Using 4K for Radarr'), findsOneWidget);
      expect(find.text('Use This One'), findsNothing);
      // Back on the list: both servers, by name, the one in use marked.
      await t.pageBack();
      await _settle(t);
      expect(find.text('Radarr: Main'), findsOneWidget);
      expect(find.text('Radarr: 4K'), findsOneWidget);
      expect(find.text('In use'), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Radarr: 4K'),
            matching: find.byType(ListTile),
          ),
          matching: find.text('In use'),
        ),
        findsOneWidget,
      );
      // Another with no name: "Main" is taken.
      await t.tap(find.text('Add Connection'));
      await _settle(t);
      await t.tap(inDialog('Radarr'));
      await _settle(t);
      await t.enterText(field(0), 'radarr3:7878');
      await t.enterText(field(1), 'k3');
      await t.tap(find.text('Save & Test'));
      await _settle(t);
      expect(
        find.text('Another server of this app has that name'),
        findsOneWidget,
      );
      await t.pageBack();
      await _settle(t);
      // Main's address on 4K's page: that address is Main's.
      await t.tap(find.text('Radarr: 4K'));
      await _settle(t);
      await t.enterText(field(0), 'http://radarr:7878');
      await t.tap(find.text('Save & Test'));
      await _settle(t);
      expect(find.text('Main already uses this address'), findsOneWidget);
      await t.pageBack();
      await _settle(t);
      // Disconnecting Main, not in use, asks first, then removes it.
      await t.tap(find.text('Radarr: Main'));
      await _settle(t);
      await t.tap(find.text('Disconnect'));
      await _settle(t);
      expect(find.text('Disconnect Radarr: Main?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await _settle(t);
      p = container.read(preferencesProvider).requireValue;
      expect(arrServersOf(p, ArrKind.radarr), hasLength(2));
      await t.tap(find.text('Disconnect'));
      await _settle(t);
      await t.tap(find.widgetWithText(FilledButton, 'Disconnect'));
      await _settle(t);
      p = container.read(preferencesProvider).requireValue;
      expect([
        for (final s in arrServersOf(p, ArrKind.radarr)) (s.name, s.active),
      ], [
        ('4K', true),
      ]);
      // Back on the list, with one server: just the app's name again.
      expect(find.text('Radarr: 4K'), findsOneWidget);
      expect(find.text('In use'), findsNothing);
    });

    testWidgets('Settings: leaving while Save & Test waits still saves', (
      t,
    ) async {
      final answer = Completer<String>();
      final container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith(() => _FakePrefs(const Prefs())),
          connTesterProvider.overrideWithValue(
            (app, url, user, key) => app == ConnApp.radarr && key == 'slow'
                ? answer.future
                : radarrs(app, url, user, key),
          ),
          radarrClientProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      t.view.physicalSize = const Size(500, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(const Color(0xFF8AB4F8)),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ArrSettingsScreen(),
          ),
        ),
      );
      await _settle(t);
      await t.tap(find.text('Add Connection'));
      await _settle(t);
      await t.tap(inDialog('Radarr'));
      await _settle(t);
      await t.enterText(field(0), 'radarr:7878');
      await t.enterText(field(1), 'slow');
      await t.tap(find.text('Save & Test'));
      await _settle(t);
      // Back before the answer comes.
      await t.pageBack();
      await _settle(t);
      answer.complete('6.0.4');
      await _settle(t);
      expect(t.takeException(), isNull);
      final p = container.read(preferencesProvider).requireValue;
      expect((p.radarrUrl, p.radarrApiKey), ('http://radarr:7878', 'slow'));
      expect(find.text('Connected to Radarr 6.0.4'), findsOneWidget);
    });

    testWidgets('TV: a failed Save & Test keeps the remote on the button', (
      t,
    ) async {
      isTvDevice = true;
      addTearDown(() => isTvDevice = false);
      final container = await settings(t, _main);
      await t.tap(find.text('Add Connection'));
      await _settle(t);
      await t.tap(inDialog('Sonarr'));
      await _settle(t);
      // On TV the fields open Fathom's own keyboard: filled in directly.
      TextEditingController box(int i) =>
          t.widget<TvTextField>(find.byType(TvTextField).at(i)).controller;
      box(0).text = 'sonarr:8989';
      box(1).text = 'wrong';
      // The remote on Save & Test, then Select.
      final node = Focus.of(t.element(find.text('Save & Test')));
      node.requestFocus();
      await t.pump();
      expect(FocusManager.instance.primaryFocus, node);
      await t.tap(find.text('Save & Test'));
      await _settle(t);
      expect(find.textContaining("Couldn't connect"), findsOneWidget);
      // Still there, not on a field above.
      expect(FocusManager.instance.primaryFocus, node);
      expect(container.read(preferencesProvider).requireValue.sonarrUrl, isEmpty);
    });

    testWidgets('Settings: nothing yet, then a first one next to another', (
      t,
    ) async {
      final container = await settings(
        t,
        const Prefs(sonarrUrl: 'http://10.0.0.5:8989', sonarrApiKey: 'nope'),
      );
      // Sonarr refuses its key: the row says so.
      expect(find.text("Can't connect"), findsOneWidget);
      await t.tap(find.text('Add Connection'));
      await _settle(t);
      await t.tap(inDialog('Radarr'));
      await _settle(t);
      // The same computer, at Radarr's usual port.
      expect(
        t.widget<TextField>(field(0)).controller!.text,
        'http://10.0.0.5:7878',
      );
      await t.enterText(field(1), 'whatever');
      await t.tap(find.text('Save & Test'));
      await _settle(t);
      // Saved anyway, on purpose: kept, and said so.
      await t.tap(find.text('Save Anyway'));
      await _settle(t);
      final p = container.read(preferencesProvider).requireValue;
      expect(p.radarrUrl, 'http://10.0.0.5:7878');
      expect(p.radarrApiKey, 'whatever');
      expect(
        find.textContaining('Saved, but the test failed'),
        findsOneWidget,
      );
    });

    testWidgets('Settings: an empty list explains, and a wide window '
        'opens a connection beside it', (t) async {
      await settings(t, const Prefs(), size: const Size(1300, 900));
      expect(find.textContaining('Your API keys and passwords'), findsOneWidget);
      expect(find.text('Pick a connection to see it here, or add one.'),
          findsOneWidget);
      await t.tap(find.text('Add Connection'));
      await _settle(t);
      await t.tap(inDialog('Radarr'));
      await _settle(t);
      // In the pane: the list stays.
      expect(find.text('Add Connection'), findsOneWidget);
      // Its address takes the cursor, not Add Connection behind the list.
      expect(
        FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<TextField>(),
        t.widget<TextField>(field(0)),
      );
      await t.enterText(field(0), 'radarr:7878');
      await t.enterText(field(1), 'mainkey');
      await t.tap(find.text('Save & Test'));
      await _settle(t);
      // The new row, picked.
      final row = find.ancestor(
        of: find.text('radarr:7878 · 6.0.4'),
        matching: find.byType(ListTile),
      );
      expect(t.widget<ListTile>(row).selected, isTrue);
      expect(find.textContaining('Your API keys and passwords'), findsNothing);
      expect(
        find.text(
          'API keys and passwords stay on this device and are never '
          'included in backups.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a server without its key yet isn\'t put in use', (t) async {
      // As a backup brings it back: the key stays out of backups.
      final restored = _withFourK().copyWith(arrServerKeys: const {});
      final container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith(() => _FakePrefs(restored)),
          sessionControllerProvider.overrideWith(_SignedOut.new),
          radarrClientProvider.overrideWithValue(null),
          sonarrClientProvider.overrideWithValue(null),
          lidarrClientProvider.overrideWithValue(null),
          prowlarrClientProvider.overrideWithValue(null),
          qbitClientProvider.overrideWithValue(null),
          sabClientProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      await container.read(preferencesProvider.future);
      t.view.physicalSize = const Size(1200, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(const Color(0xFF8AB4F8)),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () =>
                      showArrServerSwitch(context, ref, at: Offset.zero),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await _settle(t);
      await t.tap(find.text('Radarr: 4K'));
      await _settle(t);
      expect(find.text('Needs its API key on this device'), findsOneWidget);
      expect(
        container.read(preferencesProvider).requireValue.radarrUrl,
        'http://radarr:7878',
      );
    });

    testWidgets('Manage: Switch Server, and each page follows', (t) async {
      final net = _Radarrs();
      final container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith(() => _FakePrefs(_withFourK())),
          sessionControllerProvider.overrideWith(_SignedOut.new),
          radarrClientProvider.overrideWith((ref) {
            final p =
                ref.watch(preferencesProvider).asData?.value ?? const Prefs();
            if (p.radarrUrl.isEmpty) return null;
            return RadarrClient(
              p.radarrUrl,
              p.radarrApiKey,
              dio: Dio()..httpClientAdapter = net,
            );
          }),
          sonarrClientProvider.overrideWithValue(null),
          lidarrClientProvider.overrideWithValue(null),
          prowlarrClientProvider.overrideWithValue(null),
          qbitClientProvider.overrideWithValue(null),
          sabClientProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      t.view.physicalSize = const Size(1200, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark(const Color(0xFF8AB4F8)),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ArrScreen(),
          ),
        ),
      );
      await _settle(t);
      expect(net.hosts, contains('radarr'));
      expect(net.hosts, isNot(contains('radarr4k')));
      await t.tap(find.byTooltip('Switch Server'));
      await _settle(t);
      expect(find.text('Radarr: Main'), findsOneWidget);
      await t.tap(find.text('Radarr: 4K'));
      await _settle(t);
      // The library is asked of the 4K one now.
      expect(net.hosts, contains('radarr4k'));
      // The menu keeps its order: Main first, in use or not.
      await t.tap(find.byTooltip('Switch Server'));
      await _settle(t);
      expect(
        t.getTopLeft(find.text('Radarr: Main')).dy,
        lessThan(t.getTopLeft(find.text('Radarr: 4K')).dy),
      );
      expect(
        container.read(preferencesProvider).requireValue.radarrUrl,
        'http://radarr4k:7878',
      );
    });
  });
}
