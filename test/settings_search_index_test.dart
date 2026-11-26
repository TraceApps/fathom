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
}
