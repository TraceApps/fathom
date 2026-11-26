import 'dart:io';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/screens/settings_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Settings search finds every page Settings opens, and the settings added
// with the Manage section.

void main() {
  final l = lookupAppLocalizations(const Locale('en'));
  final index = userSettingsIndex(l);

  test('every page a Settings row opens can be found by searching', () {
    final source = File('lib/screens/settings_screen.dart').readAsStringSync();
    final opened = {
      for (final m in RegExp(r"context\.push\('(/[a-z-]+)'").allMatches(source))
        m.group(1)!,
    };
    // Sanity: the rows are being read.
    expect(opened, containsAll(['/arr-settings', '/accounts', '/updates']));
    final found = {for (final r in index) r.route};
    final desktop = !Platform.isAndroid && !Platform.isIOS;
    expect(
      [
        for (final route in opened)
          if (!found.contains(route) && (route != '/shortcuts' || desktop))
            route,
      ],
      isEmpty,
    );
  });

  test('the Manage notifications and their check are in the index', () {
    final titles = {for (final r in index) r.title};
    expect(
      titles,
      containsAll([
        'Downloaded',
        'Download Failed',
        'Grabbed',
        'Health Problems',
        'Check the Manage Apps',
        'Connections',
        'MDBList',
      ]),
    );
  });

  test('a search for a connection lands on Connections', () {
    for (final word in ['seerr', 'sonarr', 'mdblist', 'qbittorrent']) {
      expect(
        index.where((r) => r.keywords.contains(word)).map((r) => r.route),
        anyOf(contains('/arr-settings'), contains('/connections/mdblist')),
        reason: word,
      );
    }
  });

  test('Server Addresses, a dialog, is found and opened by Settings', () {
    final hit = index.where((r) => r.title == 'Server Addresses').single;
    expect(hit.extra, SettingResult.serverAddresses);
    expect(hit.matches('remote address'), isTrue);
    final source = File('lib/screens/settings_screen.dart').readAsStringSync();
    expect(
      source,
      matches(
        RegExp(
          r'r\.extra == SettingResult\.serverAddresses[\s\S]{0,200}_editServerAddresses',
        ),
      ),
    );
  });

  group('the final look: every control can be found', () {
    List<String> hits(String q, {List<SettingResult>? inIndex}) => [
      for (final r in searchSettings(inIndex ?? index, q)) r.title,
    ];

    test('controls that had no entry at all', () {
      expect(hits('untagged'), contains('Untagged Music'));
      expect(hits('latest by library'), contains('Latest by Library'));
      expect(hits('genre rows'), contains('Genre Rows'));
      expect(hits('customize discover'), contains('Customize Discover'));
      expect(hits('change photo'), contains('Change Photo'));
      expect(hits('avatar'), contains('Change Photo'));
      expect(hits('licenses'), contains('Open Source Licenses'));
      expect(hits('sign out'), contains('Sign Out'));
      expect(hits('log out'), contains('Sign Out'));
      expect(hits('mute'), contains('Keyboard Shortcuts'));
      expect(hits('self-promotion'), isNotEmpty);
      expect(hits('disconnect'), contains('Connections'));
      expect(hits('add connection'), contains('Connections'));
    });

    test('a row of Home by its own name finds Home Layout, on its page', () {
      for (final name in ['continue watching', 'next up', 'recently added']) {
        final found = searchSettings(index, name);
        expect(found.map((r) => r.route), contains('/home-layout'), reason: name);
      }
    });

    test('a plural finds what the singular names', () {
      expect(hits('notifications').length, greaterThan(5));
    });

    test('words that sent people to the wrong page no longer do', () {
      expect(hits('discover'), isNot(contains('Seerr Sign-in')));
      expect(hits('history'), isNot(contains('Connections')));
    });

    test('a result is only offered where its setting exists', () {
      final bare = userSettingsIndex(l, manage: false, youtube: false, seerr: false);
      final titles = {for (final r in bare) r.title};
      expect(titles, isNot(contains('Download Failed')));
      expect(titles, isNot(contains('Customize Discover')));
      expect(titles, contains('Enable YouTube'));
      expect(
        bare.where((r) => r.section == 'YouTube').map((r) => r.title),
        ['Enable YouTube'],
      );
      // Android's choice of player isn't a computer's setting.
      expect(titles, isNot(contains('Video Player (Android)')));
      expect({for (final r in index) r.title}, contains('Smooth Motion (Display Sync)'));
    });

    test('Change Password sits with the account, not the system', () {
      expect(
        index.where((r) => r.title == 'Change Password').single.section,
        l.settingsSectionAccount,
      );
    });

    test('the switches on the Settings page itself do not open it again', () {
      final source = File('lib/screens/settings_screen.dart').readAsStringSync();
      expect(source, contains("if (r.route == '/settings' && r.extra == null) return;"));
      expect(source, contains('SettingResult.licenses'));
      expect(source, contains('SettingResult.signOut'));
    });

    test('Administration: its controls by the names they carry', () {
      final admin = adminSettingsIndex(l);
      List<String> a(String q) => hits(q, inIndex: admin);
      expect(a('base url'), contains('Base URL'));
      expect(a('login disclaimer'), contains('Login Disclaimer'));
      expect(a('transcode thread'), contains('Transcode Thread Count'));
      expect(a('crf'), isNotEmpty);
      expect(a('require https'), isNotEmpty);
      expect(a('parental'), contains('Users'));
      expect(a('reset password'), contains('Users'));
      expect(a('recording path'), contains('Live TV'));
      expect(a('tuners'), contains('Live TV'));
      expect(a('repository'), contains('Plugins'));
      expect(a('create backup'), isNotEmpty);
      expect(a('dlna'), isEmpty);
    });
  });
}
