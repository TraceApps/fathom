import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'support/fake_player.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/widgets/volume_control.dart';

class _FakePrefs extends PreferencesController {
  @override
  Future<Prefs> build() async => const Prefs();
  @override
  Future<void> edit(Prefs Function(Prefs) change) async =>
      state = AsyncData(change(state.asData?.value ?? const Prefs()));
}

// Now Playing's transport row: controls centered, the volume at the right
// edge, and the Up Next strip right below. The volume pill used to sit on top
// of Play (an Align in a Stack collapsed inside the row's FittedBox); and
// growing it in the layout would shove the strip below and re-center the page
// every time it opened. It must sit to the right, open without moving
// anything, and still be usable where it hangs over the strip.
void main() {
  // Created outside the widget test's fake clock: disposing a player from
  // inside it waits on real native work that never completes there.
  late Player player;
  setUpAll(() {
    player = FakePlayer();
  });

  testWidgets('the floating volume sits right of Play and opens in place',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [preferencesProvider.overrideWith(_FakePrefs.new)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 48),
                      Container(
                          key: const Key('play'),
                          width: 64,
                          height: 64,
                          color: Colors.pink),
                      VerticalVolumeButton(player: player, floating: true),
                    ],
                  ),
                ),
                const SizedBox(key: Key('below'), width: 300, height: 60),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    // Where anything is on screen, answered by a real hit test, since the
    // pill is drawn on the overlay rather than where it sits in the row.
    bool hits(Offset at, String renderType) {
      final r = HitTestResult();
      tester.binding.hitTestInView(r, at, tester.view.viewId);
      return r.path.any((e) => e.target.runtimeType.toString().contains(renderType));
    }

    // The invisible stand-in the pill is pinned to, in the row.
    final spot = tester.getRect(find.descendant(
        of: find.byType(VerticalVolumeButton),
        matching: find.byType(Opacity)).first);
    final play = tester.getRect(find.byKey(const Key('play')));
    expect(spot.left, greaterThanOrEqualTo(play.right),
        reason: 'the volume sits right of Play, not on top of it');
    final below = Offset(spot.center.dx, spot.bottom + 60);
    // The pill lives on the overlay; before hovering it's just the icon.
    const pill = '_RenderDeferredLayoutBox';
    expect(hits(below, pill), isFalse, reason: 'closed until hovered');

    final belowBefore = tester.getRect(find.byKey(const Key('below')));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(spot.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Opened over the page, not in it: nothing around it moved...
    expect(tester.getRect(find.byKey(const Key('below'))), belowBefore);
    expect(tester.getRect(find.byKey(const Key('play'))), play);
    // ...and the open pill really covers the space below the row, as a
    // target for the pointer, not just paint.
    expect(hits(below, pill), isTrue);
    // Open, it stays the width of its own icon. (Offered a bounded width, as
    // the overlay does, it used to stretch window-wide and push its icon off
    // screen.)
    final open = tester.getSize(find.byType(AnimatedContainer));
    expect(open.width, lessThanOrEqualTo(spot.width + 8));
    expect(open.height, greaterThan(spot.height * 2));
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
