import 'dart:convert';
import 'dart:io';

import 'package:fathom/models/session.dart';
import 'package:fathom/services/settings_backup.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/state/server_address.dart';
import 'package:flutter_test/flutter_test.dart';

// The final look at Backup & Restore: nothing a person set is left behind,
// nothing that belongs to one device travels to another, a damaged file
// can't break the app, and a backup's server addresses only ever go to the
// server they were saved for.

Session _account({
  String serverId = 'srv-1',
  String name = 'Home Server',
  String base = 'https://jf.example.com',
  String? internal,
  String? external,
}) => Session(
  baseUrl: base,
  accessToken: 't',
  userId: 'u1',
  userName: 'joe',
  serverId: serverId,
  serverName: name,
  internalUrl: internal,
  externalUrl: external,
);

void main() {
  const groups = {'appearance', 'player', 'youtube', 'general', 'radio'};

  group('what a backup holds', () {
    test('every setting is in a backup, a secret, or kept to this device', () {
      // The catch-all group takes anything not named: this pins that the
      // three kinds between them cover every setting there is.
      final all = const Prefs().toJson().keys.toSet();
      expect(secretPrefKeys.difference(all), isEmpty, reason: 'stale secret');
      expect(
        deviceOnlyPrefKeys.difference(all),
        isEmpty,
        reason: 'a device-only key that is no longer a setting',
      );
      expect(secretPrefKeys.intersection(deviceOnlyPrefKeys), isEmpty);
    });

    test('a round trip brings back every setting that travels', () {
      const mine = Prefs(
        themeMode: 'light',
        radioEnabled: true,
        replayGain: 'album',
        seerrRowOrder: ['trending', 'popular'],
        navHidden: ['/radio'],
        youtubeEnabled: true,
        startupScreen: '/libraries',
      );
      final file = mine.toJson()
        ..removeWhere(
          (k, _) => secretPrefKeys.contains(k) || deviceOnlyPrefKeys.contains(k),
        );
      final back = restoredPrefs(const Prefs(), file, groups)!;
      final a = back.toJson(), b = mine.toJson();
      for (final key in b.keys) {
        if (secretPrefKeys.contains(key) || deviceOnlyPrefKeys.contains(key)) {
          continue;
        }
        expect(jsonEncode(a[key]), jsonEncode(b[key]), reason: key);
      }
    });

    test("this device's own settings don't come from a backup", () {
      final back = restoredPrefs(const Prefs(), {
        'themeMode': 'light',
        'forceTvMode': true,
        'jellyfinDownloadPath': '/home/someone/Videos',
        'diagnosticLogging': true,
      }, groups)!;
      expect(back.themeMode, 'light');
      expect(back.forceTvMode, isFalse);
      expect(back.jellyfinDownloadPath, const Prefs().jellyfinDownloadPath);
      expect(back.diagnosticLogging, isFalse);
    });

    test('settings sit in the group a person would look for them in', () {
      Set<String> found(Map<String, dynamic> prefs) =>
          groupsInBackup({'preferences': prefs});
      expect(found({'radioEnabled': true}), {'radio'});
      expect(found({'replayGain': 'track'}), {'player'});
      expect(found({'upNextStyle': 'pill'}), {'player'});
      expect(found({'seerrRowOrder': <String>[]}), {'appearance'});
      expect(found({'movieWheelEnabled': true}), {'general'});
      expect(found({'movieWheelMode': 'single'}), {'general'});
      expect(found({'forceTvMode': true}), isEmpty);
      expect(found({'seerrApiKey': 'k'}), isEmpty);
    });

    test('whether the side menu is open travels with Appearance', () {
      expect(groupsInBackup({'sideMenuOpen': false}), {'appearance'});
      expect(groupsInBackup({'sideMenuOpen': 'yes'}), isEmpty);
      final src = File('lib/services/settings_backup.dart').readAsStringSync();
      // Written on export, applied on restore, and never on a TV.
      expect(src, contains("result['sideMenuOpen'] = rail == '1';"));
      expect(src, contains("selectedGroups.contains('appearance') && !isTvDevice"));
    });

    test("YouTube's library on its own counts as the YouTube group", () {
      expect(
        groupsInBackup({
          'youtubeLibrary': {
            'subscriptions': [
              {'id': 'UC1', 'title': 'A channel'},
            ],
          },
        }),
        {'youtube'},
      );
    });
  });

  group("YouTube's library", () {
    test('subscriptions, feed groups and both kinds of playlist are kept', () {
      expect(youtubeLibraryStores.keys, [
        'subscriptions',
        'feedGroups',
        'playlists',
        'savedPlaylists',
      ]);
      // Each is a store the app really writes.
      final src = File('lib/state/youtube_providers.dart').readAsStringSync();
      for (final key in youtubeLibraryStores.values) {
        expect(src, contains("'$key'"), reason: key);
      }
    });

    test("a restore adds what's missing and keeps what's here", () {
      final merged = mergedById(
        [
          {'id': 'a', 'title': 'Mine, as I named it'},
        ],
        [
          {'id': 'a', 'title': 'From the backup'},
          {'id': 'b', 'title': 'New'},
          {'id': 'b', 'title': 'Twice in the file'},
        ],
      );
      expect(merged.map((e) => e['title']), ['Mine, as I named it', 'New']);
    });
  });

  group('a damaged or hand-edited file', () {
    test('a list holding the wrong kind of thing costs only its bad entries', () {
      final back = restoredPrefs(const Prefs(), {
        'navOrder': ['/home', 7, null, '/search'],
        'recentSearches': [1, 2],
        'themeMode': 'light',
      }, groups)!;
      expect(back.navOrder, ['/home', '/search']);
      expect(back.recentSearches, isEmpty);
      expect(back.themeMode, 'light');
      // And it can be saved: a lazy cast used to blow up here instead.
      expect(() => jsonEncode(back.toJson()), returnsNormally);
    });

    test('numbers out of range are brought back into it', () {
      final back = restoredPrefs(const Prefs(), {
        'interfaceScale': 20,
        'subtitleScale': 0.01,
        'playbackSpeed': 99,
        'youtubeMaxConcurrentDownloads': 0,
        'seerrPollMinutes': -5,
      }, groups)!;
      expect(back.interfaceScale, 3.0);
      expect(back.subtitleScale, 0.5);
      expect(back.playbackSpeed, 4.0);
      expect(back.youtubeMaxConcurrentDownloads, 1);
      expect(back.seerrPollMinutes, 0);
    });

    test('Off stays Off, and Automatic stays Automatic', () {
      final back = restoredPrefs(const Prefs(arrPollMinutes: 5), {
        'arrPollMinutes': 0,
        'interfaceScale': 0,
      }, groups)!;
      expect(back.arrPollMinutes, 0);
      expect(back.interfaceScale, 0);
    });
  });

  group('server addresses', () {
    Map<String, dynamic> file(Map<String, dynamic> server) => {
      'servers': [server],
    };

    test('go to the account on the same server, by its id', () {
      final changes = serverAddressChanges(
        file({
          'serverId': 'srv-1',
          'serverName': 'Renamed since',
          'internalUrl': 'http://192.168.1.5:8096/',
          'externalUrl': 'https://jf.example.com',
        }),
        [_account()],
      );
      expect(changes, hasLength(1));
      expect(changes.single.internal, 'http://192.168.1.5:8096');
      expect(changes.single.external, 'https://jf.example.com');
      expect(changes.single.label, 'Home Server (joe)');
    });

    test('a file that only names your server changes nothing', () {
      // The hole this closes: the app moves a signed-in session to
      // whichever saved address answers, so an address from a file that
      // merely carried the same server name received the sign-in.
      for (final server in [
        {
          'serverName': 'Home Server',
          'baseUrl': 'https://jf.example.com',
          'internalUrl': 'http://evil.example:8096',
        },
        {
          'serverId': 'someone-elses',
          'serverName': 'Home Server',
          'internalUrl': 'http://evil.example:8096',
        },
      ]) {
        expect(serverAddressChanges(file(server), [_account()]), isEmpty);
      }
    });

    test('every signed-in account gets its own, not only the one in use', () {
      final changes = serverAddressChanges(
        {
          'servers': [
            {'serverId': 'srv-2', 'internalUrl': 'http://10.0.0.2:8096'},
            {'serverId': 'srv-1', 'internalUrl': 'http://10.0.0.1:8096'},
          ],
        },
        [_account(), _account(serverId: 'srv-2', name: 'Cabin')],
      );
      expect(changes.map((c) => '${c.label} ${c.internal}'), [
        'Home Server (joe) http://10.0.0.1:8096',
        'Cabin (joe) http://10.0.0.2:8096',
      ]);
    });

    test('addresses already the same, or of the wrong kind, change nothing', () {
      expect(
        serverAddressChanges(
          file({'serverId': 'srv-1', 'internalUrl': 'http://10.0.0.1:8096'}),
          [_account(internal: 'http://10.0.0.1:8096')],
        ),
        isEmpty,
      );
      expect(
        serverAddressChanges(
          file({'serverId': 'srv-1', 'internalUrl': 42, 'externalUrl': ['x']}),
          [_account()],
        ),
        isEmpty,
      );
    });

    test('the app only moves a session to the same server', () {
      expect(sameServer('srv-1', 'srv-1'), isTrue);
      expect(sameServer('srv-1', 'other'), isFalse);
      expect(sameServer('srv-1', null), isFalse, reason: 'nothing answered');
      expect(sameServer(null, 'anything'), isTrue, reason: 'an old sign-in');
    });
  });
}
