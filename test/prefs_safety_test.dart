import 'dart:async';
import 'dart:convert';

import 'package:fathom/services/resilient_secure_storage.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The device's store, in memory. A write can be held back, and a read too,
/// to stand in for a slow keyring.
class _Store implements ResilientSecureStorage {
  final Map<String, String> saved;
  Completer<void>? holdWrites;
  Completer<void>? holdReads;
  int writes = 0;
  _Store([Map<String, String>? saved]) : saved = saved ?? {};

  @override
  Future<String?> read({required String key}) async {
    await holdReads?.future;
    return saved[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    writes++;
    await holdWrites?.future;
    saved[key] = value;
  }

  @override
  Future<void> delete({required String key}) async => saved.remove(key);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ProviderContainer _app(_Store store) {
  final c = ProviderContainer(
    overrides: [secureStorageProvider.overrideWithValue(store)],
  );
  addTearDown(c.dispose);
  return c;
}

Map<String, dynamic> _saved(_Store s) =>
    jsonDecode(s.saved['fathom_prefs']!) as Map<String, dynamic>;

// The settings hold every server address and API key. They used to be lost
// whole to one value that couldn't be read, and a change could be lost to
// another made at the same moment.
void main() {
  group('reading what was saved', () {
    test('one value of the wrong kind costs that setting only', () async {
      final store = _Store({
        'fathom_prefs': jsonEncode({
          'radarrUrl': 'http://radarr:7878',
          'radarrApiKey': 'rkey',
          'themeMode': 'dark',
          // A bool where the name of a channel belongs.
          'updateChannel': true,
          // And text where a number does.
          'accentColor': 'blue',
          'sonarrUrl': 'http://sonarr:8989',
        }),
      });
      final c = _app(store);
      final p = await c.read(preferencesProvider.future);
      expect(p.radarrUrl, 'http://radarr:7878');
      expect(p.radarrApiKey, 'rkey');
      expect(p.sonarrUrl, 'http://sonarr:8989');
      expect(p.themeMode, 'dark');
      // The two that couldn't be read are as on a first run.
      expect(p.updateChannel, const Prefs().updateChannel);
      expect(p.accentColor, const Prefs().accentColor);
      // What was there is kept as it was, before a save goes over it.
      expect(jsonDecode(store.saved[PreferencesController.badKey]!), {
        'radarrUrl': 'http://radarr:7878',
        'radarrApiKey': 'rkey',
        'themeMode': 'dark',
        'updateChannel': true,
        'accentColor': 'blue',
        'sonarrUrl': 'http://sonarr:8989',
      });
    });

    test('settings that read are not copied aside', () async {
      final store = _Store({
        'fathom_prefs': jsonEncode({'radarrUrl': 'http://radarr:7878'}),
      });
      final c = _app(store);
      await c.read(preferencesProvider.future);
      expect(store.saved.containsKey(PreferencesController.badKey), isFalse);
      expect(store.writes, 0);
    });

    test('a file that is not settings at all is kept, and the app opens', () async {
      for (final raw in ['{"radarrUrl": "http://rad', '[1, 2]', 'null', '']) {
        final store = _Store({'fathom_prefs': raw});
        final c = _app(store);
        final p = await c.read(preferencesProvider.future);
        expect(p.radarrUrl, isEmpty);
        expect(store.saved[PreferencesController.badKey], raw, reason: raw);
        // And a change after that doesn't take the copy away.
        await c.read(preferencesProvider.notifier).edit(
          (x) => x.copyWith(themeMode: 'light'),
        );
        expect(store.saved[PreferencesController.badKey], raw, reason: raw);
      }
    });

    test('every setting survives a save and a read', () async {
      // What a build writes, it reads back whole.
      final all = const Prefs().toJson();
      final (p, partly) = prefsFromSaved(
        jsonDecode(jsonEncode(all)) as Map<String, dynamic>,
      );
      expect(partly, isFalse);
      expect(p.toJson(), all);
    });

    test('settings saved by 0.13.1 read whole in this build', () {
      // The keys 0.13.1 wrote that matter most, as it wrote them.
      final (p, partly) = prefsFromSaved({
        'themeMode': 'dark',
        'accentColor': 4287542008,
        'seerrUrl': 'https://requests.example.com',
        'seerrApiKey': 'skey',
        'seerrAuthMode': 'apikey',
        'mdbListApiKey': 'mkey',
        'startupScreen': 'libraries',
        'youtubeEnabled': true,
        'radioEnabled': true,
        'updateChannel': 'stable',
        'homeRows': ['continue', 'nextup', 'latest'],
        // One this build has never heard of.
        'somethingFromTheFuture': {'a': 1},
      });
      expect(partly, isFalse);
      expect(p.themeMode, 'dark');
      expect(p.seerrUrl, 'https://requests.example.com');
      expect(p.seerrApiKey, 'skey');
      expect(p.mdbListApiKey, 'mkey');
      expect(p.startupScreen, 'libraries');
      // And everything added since starts not connected.
      expect(p.sonarrUrl, isEmpty);
      expect(p.qbitUrl, isEmpty);
    });
  });

  group('saving a change', () {
    test('two changes made together both hold', () async {
      final store = _Store({
        'fathom_prefs': jsonEncode({'themeMode': 'dark'}),
      });
      final c = _app(store);
      await c.read(preferencesProvider.future);
      final n = c.read(preferencesProvider.notifier);
      // The store is slow: the second change is asked for while the first is
      // still being written.
      store.holdWrites = Completer<void>();
      final first = n.edit((p) => p.copyWith(radarrUrl: 'http://radarr:7878'));
      final second = n.edit((p) => p.copyWith(sonarrUrl: 'http://sonarr:8989'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      store.holdWrites!.complete();
      store.holdWrites = null;
      await Future.wait([first, second]);
      final p = c.read(preferencesProvider).requireValue;
      expect((p.radarrUrl, p.sonarrUrl), (
        'http://radarr:7878',
        'http://sonarr:8989',
      ));
      expect(_saved(store)['radarrUrl'], 'http://radarr:7878');
      expect(_saved(store)['sonarrUrl'], 'http://sonarr:8989');
      expect(_saved(store)['themeMode'], 'dark');
    });

    test('a change made before the settings loaded keeps them', () async {
      final store = _Store({
        'fathom_prefs': jsonEncode({
          'radarrUrl': 'http://radarr:7878',
          'radarrApiKey': 'rkey',
        }),
      })..holdReads = Completer<void>();
      final c = _app(store);
      // Still loading: the keyring hasn't answered.
      final n = c.read(preferencesProvider.notifier);
      final change = n.edit((p) => p.copyWith(themeMode: 'light'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      store.holdReads!.complete();
      await change;
      final saved = _saved(store);
      expect(saved['themeMode'], 'light');
      expect(saved['radarrUrl'], 'http://radarr:7878');
      expect(saved['radarrApiKey'], 'rkey');
    });

    test('a save that failed doesn\'t stop the next', () async {
      final store = _Store();
      final c = _app(store);
      await c.read(preferencesProvider.future);
      final n = c.read(preferencesProvider.notifier);
      await expectLater(
        n.edit((p) => throw StateError('no')),
        throwsStateError,
      );
      await n.edit((p) => p.copyWith(themeMode: 'light'));
      expect(_saved(store)['themeMode'], 'light');
    });
  });
}
