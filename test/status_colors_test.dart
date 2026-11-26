import 'package:fathom/theme/status_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Status colors that read. The green and the amber are made for a dark
// page: as text on a light one, or under white text, they came to about 2:1.

const _green = Color(0xFF22C55E);
const _amber = Color(0xFFF59E0B);
const _blue = Color(0xFF3B82F6);
const _red = Color(0xFFEF4444);

Future<Color> _ink(WidgetTester t, Brightness b, Color c) async {
  late Color got;
  await t.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: b),
      home: Builder(
        builder: (context) {
          got = statusInk(context, c);
          return const SizedBox();
        },
      ),
    ),
  );
  return got;
}

void main() {
  test('white on the green and the amber is why', () {
    expect(contrastOf(Colors.white, _green), lessThan(3));
    expect(contrastOf(Colors.white, _amber), lessThan(3));
  });

  test('a solid pill gets text that reads on it', () {
    for (final fill in [_green, _amber, _blue, _red]) {
      expect(contrastOf(onStatus(fill), fill), greaterThanOrEqualTo(3));
    }
    expect(onStatus(_blue), Colors.white);
    expect(onStatus(_red), Colors.white);
    expect(onStatus(_green), isNot(Colors.white));
  });

  testWidgets('on a light page a status color is deepened until it reads', (
    t,
  ) async {
    for (final c in [_green, _amber, _blue]) {
      final ink = await _ink(t, Brightness.light, c);
      final page = ThemeData(brightness: Brightness.light).colorScheme.surface;
      expect(contrastOf(ink, page), greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('on a dark page it is left as it is', (t) async {
    expect(await _ink(t, Brightness.dark, _green), _green);
  });
}
