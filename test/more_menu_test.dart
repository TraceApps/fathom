import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// A "More" menu is the same thing everywhere: three upright dots, named More.
// It used to be More, More Options or Options, upright or sideways.

void main() {
  test('every More menu is named More', () {
    final arb =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    expect(arb['commonMore'], 'More');
    // One key: there were six, saying More, More Options and Options.
    expect(
      arb.entries
          .where((e) => !e.key.startsWith('@') && e.value == 'More')
          .map((e) => e.key),
      // appNavMore is the side menu's own word, not a menu button.
      unorderedEquals(['commonMore', 'appNavMore']),
    );
  });

  test('the dots are upright, but for Shorts and a connection being checked', () {
    final sideways = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') &&
            f.readAsStringSync().contains('more_horiz'))
          f.path,
    ]..sort();
    expect(sideways, [
      'lib/screens/arr_settings_screen.dart',
      'lib/screens/youtube_shorts_screen.dart',
    ]);
  });

  test('a menu button says what it is, not "Show menu"', () {
    final src = File('lib/screens/detail_screen.dart').readAsStringSync();
    final buttons = RegExp(r'PopupMenuButton<String>\(\s*(tooltip:)?')
        .allMatches(src)
        .toList();
    expect(buttons, isNotEmpty);
    for (final b in buttons) {
      expect(b.group(1), isNotNull, reason: src.substring(b.start, b.end + 40));
    }
  });
}
