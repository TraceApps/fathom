import 'dart:io';

import 'package:fathom/services/app_shown.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// A page that refreshes itself on a timer stops asking once the app is
// minimized or in the background. A Seerr title left open asked its server
// every seven seconds for as long as the app ran.

void main() {
  test('shown while on screen, with or without the keyboard', () {
    expect(appShownIn(AppLifecycleState.resumed), isTrue);
    expect(appShownIn(AppLifecycleState.inactive), isTrue);
    expect(appShownIn(null), isTrue, reason: 'before the first report');
  });

  test('not shown once minimized, in the background or closing', () {
    expect(appShownIn(AppLifecycleState.hidden), isFalse);
    expect(appShownIn(AppLifecycleState.paused), isFalse);
    expect(appShownIn(AppLifecycleState.detached), isFalse);
  });

  test("the Seerr title page's refresh asks first", () {
    final src = File('lib/screens/seerr_detail_screen.dart').readAsStringSync();
    expect(
      src,
      matches(RegExp(r'Timer\.periodic\(const Duration\(seconds: 7\)[\s\S]{0,260}mounted && appShown')),
    );
  });
}
