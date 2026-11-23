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
import 'package:fathom/state/arr_providers.dart';
import 'package:fathom/state/arr_servers.dart';
import 'package:fathom/state/download_providers.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/session_controller.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/arr_servers_ui.dart';
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
    testWidgets('Settings: the Servers dialog, Add, and Use This One', (
      t,
    ) async {
      final container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith(() => _FakePrefs(_main)),
        ],
      );
      addTearDown(container.dispose);
      t.view.physicalSize = const Size(900, 4400);
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
      expect(find.text('Servers'), findsOneWidget);
      expect(find.text('Add another server, such as a 4K one'), findsOneWidget);
      await t.tap(find.text('Servers'));
      await _settle(t);
      expect(find.text('Radarr Servers'), findsOneWidget);
      expect(find.text('Main'), findsOneWidget);
      // Adding needs the address and key; the check comes first.
      await t.tap(find.text('Add Server'));
      await _settle(t);
      final form = find.byType(AlertDialog).last;
      final fields = find.descendant(of: form, matching: find.byType(TextField));
      await t.enterText(fields.at(0), '4K');
      await t.tap(find.descendant(of: form, matching: find.text('Save & Test')));
      await _settle(t);
      expect(
        find.text('Enter the server address and the API key'),
        findsOneWidget,
      );
      // A real check, against nothing (tests have no network): refused,
      // and nothing saved.
      await t.enterText(fields.at(1), 'radarr4k:7878');
      await t.enterText(fields.at(2), '4kkey');
      await t.tap(find.descendant(of: form, matching: find.text('Save & Test')));
      await _settle(t);
      var p = container.read(preferencesProvider).requireValue;
      expect(p.arrServers, isEmpty);
      // Saved another way (as the form does once its check passes): the
      // dialog lists it, and Use This One swaps.
      await container
          .read(preferencesProvider.notifier)
          .edit((p) => arrAddServer(
                p,
                ArrKind.radarr,
                name: '4K',
                url: 'http://radarr4k:7878',
                apiKey: '4kkey',
              ));
      await t.tap(find.text('Cancel'));
      await _settle(t);
      expect(find.text('4K'), findsOneWidget);
      await t.tap(find.text('4K'));
      await _settle(t);
      await t.tap(find.text('Use This One'));
      await _settle(t);
      p = container.read(preferencesProvider).requireValue;
      expect(p.radarrUrl, 'http://radarr4k:7878');
      expect(find.text('Using 4K for Radarr'), findsOneWidget);
      await t.tap(find.text('Close'));
      await _settle(t);
      // The card follows: its name, its address.
      expect(find.text('Radarr: 4K'), findsOneWidget);
      expect(find.text('http://radarr4k:7878'), findsOneWidget);
      expect(find.text('2 servers, 4K in use'), findsOneWidget);
      // A second server with a name already there isn't saved.
      await t.tap(find.text('Servers'));
      await _settle(t);
      await t.tap(find.text('Add Server'));
      await _settle(t);
      final again = find.byType(AlertDialog).last;
      final f = find.descendant(of: again, matching: find.byType(TextField));
      await t.enterText(f.at(1), 'radarr3:7878');
      await t.enterText(f.at(2), 'k3');
      await t.tap(find.descendant(of: again, matching: find.text('Save & Test')));
      await _settle(t);
      expect(
        find.text('Another server of this app has that name'),
        findsOneWidget,
      );
      await t.tap(find.text('Cancel'));
      await _settle(t);
      await t.tap(find.text('Close'));
      await _settle(t);
      // Typing a saved server's address on the card puts that one in use.
      final card = find.ancestor(
        of: find.text('Radarr: 4K'),
        matching: find.byType(Card),
      );
      final cardFields = find.descendant(of: card, matching: find.byType(TextField));
      await t.enterText(cardFields.at(0), 'http://radarr:7878');
      await t.enterText(cardFields.at(1), 'mainkey');
      await t.tap(find.descendant(of: card, matching: find.text('Save & Test')));
      await _settle(t);
      p = container.read(preferencesProvider).requireValue;
      final all = arrServersOf(p, ArrKind.radarr);
      expect([for (final s in all) (s.name, s.active)], [
        ('', true),
        ('4K', false),
      ]);
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
