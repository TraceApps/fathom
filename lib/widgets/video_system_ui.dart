import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Which player screen currently holds the phone's video mode (landscape,
/// system bars hidden).
///
/// Next, Previous and a playlist's advance REPLACE one player with another:
/// the new one takes video mode as it opens, and the old one, on its way
/// out a moment later, used to put the system bars back and drop the
/// landscape lock, leaving the new video in portrait with the bars showing.
/// A player now gives video mode back only while it still holds it.
abstract final class VideoSystemUi {
  static Object? _holder;

  /// [owner] takes video mode (it's about to ask the platform for it).
  static void take(Object owner) => _holder = owner;

  /// Whether [owner] still holds video mode, giving it up if so. False when
  /// a newer player took it: [owner] must then leave the platform alone.
  static bool giveBack(Object owner) {
    if (!identical(_holder, owner)) return false;
    _holder = null;
    return true;
  }

  /// Puts the system bars back after a video, with icons that suit the
  /// app's theme.
  ///
  /// Leaving fullscreen resets the bars' icons to white a moment after the
  /// call returns, and Flutter only sends a style that differs from the last
  /// one it sent: the page underneath asks for the same dark icons it had
  /// before the video, so nothing was sent, and in the light theme the clock
  /// and battery stayed white on a pale page. So once the bars are back, the
  /// style is sent again, by way of the other one so that it counts as a
  /// change. The dark theme wants the white icons the reset leaves anyway.
  static void restoreBars({required bool lightTheme}) {
    SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!lightTheme) return;
    SystemUiOverlayStyle bars(SystemUiOverlayStyle icons) => icons.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        );
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      SystemChrome.setSystemUIOverlayStyle(bars(SystemUiOverlayStyle.light));
      Future<void>.delayed(const Duration(milliseconds: 30), () {
        SystemChrome.setSystemUIOverlayStyle(bars(SystemUiOverlayStyle.dark));
        // And let the page on screen have its say again.
        WidgetsBinding.instance.scheduleFrame();
      });
    });
  }
}
