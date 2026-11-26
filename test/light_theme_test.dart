import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'support/fake_player.dart';
import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/state/preferences.dart';
import 'package:fathom/theme/app_theme.dart';
import 'package:fathom/widgets/volume_control.dart';

class _FakePrefs extends PreferencesController {
  @override
  Future<Prefs> build() async => const Prefs();
  @override
  Future<void> edit(Prefs Function(Prefs) change) async =>
      state = AsyncData(change(state.asData?.value ?? const Prefs()));
}

// Most of the app's hardcoded colours are deliberate: brand marks, and white
// text over artwork or video, which read the same in either theme. The volume
// pill was not one of those. It sits on the music screens over an ordinary
// themed background, and a fixed near-black fill hid the icon drawn on it in
// the light theme.
void main() {
  late Player player;
  setUpAll(() {
    player = FakePlayer();
  });

  testWidgets('the volume pill takes its surface from the light theme',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [preferencesProvider.overrideWith(_FakePrefs.new)],
      child: MaterialApp(
        theme: AppTheme.light(AppTheme.seed),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(child: VerticalVolumeButton(player: player)),
        ),
      ),
    ));
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(VerticalVolumeButton)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final box = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer).first);
    final fill = (box.decoration! as BoxDecoration).color!;
    expect(fill.computeLuminance(), greaterThan(0.5),
        reason: 'an open volume pill in the light theme should be a light '
            'surface, or the icon on it disappears');
    await mouse.removePointer();
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
