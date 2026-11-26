import 'dart:convert';
import 'dart:io';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The app's own words: no long dashes, US spelling, "Sign In" for its own
// sign-in buttons, and counts that agree with their number.

void main() {
  final arb =
      jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;
  final words = {
    for (final e in arb.entries)
      if (!e.key.startsWith('@') && e.value is String) e.key: e.value as String,
  };
  final l = lookupAppLocalizations(const Locale('en'));

  test('no long dash in anything the app says', () {
    expect(
      [
        for (final e in words.entries)
          if (e.value.contains('\u2014')) e.key,
      ],
      isEmpty,
    );
  });

  test('no long dash stands in for a missing value', () {
    final standIn = RegExp("'\u2014'");
    expect(
      [
        for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.dart') && standIn.hasMatch(f.readAsStringSync()))
            f.path,
      ],
      isEmpty,
    );
  });

  test('US spelling, and Sign In on our own buttons', () {
    final british = RegExp(r'[Cc]ancelled|[Cc]olour|[Ff]avourite|[Cc]entre\b');
    expect(
      [
        for (final e in words.entries)
          if (british.hasMatch(e.value)) e.key,
      ],
      isEmpty,
    );
    expect(l.seerrLoginWithJellyfin, 'Sign In with Jellyfin');
    expect(l.seerrLoginWithSeerr, 'Sign In with Seerr');
  });

  test('counts agree with their number', () {
    expect(l.arrEpisodesOf(1, 1), '1 of 1 episode');
    expect(l.arrEpisodesOf(3, 10), '3 of 10 episodes');
    expect(l.arrTracksOf(0, 1), '0 of 1 track');
    expect(l.arrMonitorKeepHint(1, 1), '1 of 1 episode is monitored now');
    expect(l.arrMonitorKeepAlbumsHint(2, 5), '2 of 5 albums are monitored now');
    expect(l.playerSubtitleDownloads(1), '1 download');
    expect(
      l.ytMoveDownloadsPartial(0, 1),
      startsWith('Moved 0 of 1 download. The rest'),
    );
  });
}
