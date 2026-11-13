import 'package:flutter/services.dart';

/// The buttons in Android's picture-in-picture window: back, play/pause and
/// forward, driving the video on screen.
///
/// Without them Android shows the app's media session controls, and that
/// session belongs to the music player, so play/pause in the PiP window never
/// reached the video. A video screen binds while it's open (and PiP is on),
/// keeps [update] in step with its play state, and unbinds on the way out.
class SystemPipControls {
  SystemPipControls._();

  static const _channel = MethodChannel('app.fathom.player/pip_controls');

  static Object? _owner;

  /// The video screen that switched system PiP on. The next episode replaces
  /// its screen, and the outgoing one is torn down only after the new one has
  /// switched PiP on; it must not switch it back off.
  static Object? _pipOwner;

  /// [owner] switched PiP on.
  static void claimPip(Object owner) => _pipOwner = owner;

  /// Whether [owner] may switch PiP off (it's still the one that switched it
  /// on). Releases it if so.
  static bool releasePip(Object owner) {
    if (!identical(owner, _pipOwner)) return false;
    _pipOwner = null;
    return true;
  }

  static _Handlers? _handlers;
  static Map<String, Object?>? _labels;
  static bool _playing = false;

  /// Shows the buttons for the video owned by [owner]. [backSeconds] and
  /// [forwardSeconds] match the player's own skip buttons.
  static void bind({
    required Object owner,
    required bool playing,
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required void Function(int seconds) onSeekBy,
    required int backSeconds,
    required int forwardSeconds,
    required String playPauseLabel,
    required String backLabel,
    required String forwardLabel,
  }) {
    _owner = owner;
    _handlers = _Handlers(onPlay, onPause, onSeekBy, backSeconds, forwardSeconds);
    _labels = {
      'playPauseLabel': playPauseLabel,
      'backLabel': backLabel,
      'forwardLabel': forwardLabel,
    };
    _playing = playing;
    _channel.setMethodCallHandler(_onCall);
    _push();
  }

  /// The video started or stopped: flip the play/pause button.
  static void update({required Object owner, required bool playing}) {
    if (!identical(owner, _owner) || playing == _playing) return;
    _playing = playing;
    _push();
  }

  /// The video screen is going away. Only its own binding is cleared, so a
  /// screen leaving after the next one opened can't take its buttons.
  static void unbind(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _handlers = null;
    _labels = null;
    _channel.setMethodCallHandler(null);
    _invoke(null);
  }

  /// A button in the PiP window was tapped.
  static Future<void> handle(String action) async {
    final h = _handlers;
    if (h == null) return;
    switch (action) {
      case 'play':
        await h.onPlay();
      case 'pause':
        await h.onPause();
      case 'back':
        h.onSeekBy(-h.back);
      case 'forward':
        h.onSeekBy(h.forward);
    }
  }

  static Future<Object?> _onCall(MethodCall call) async {
    if (call.method == 'action') await handle(call.arguments as String);
    return null;
  }

  static void _push() =>
      _invoke({...?_labels, 'playing': _playing});

  static void _invoke(Map<String, Object?>? args) {
    _channel.invokeMethod<void>('setButtons', args).catchError((_) {});
  }
}

class _Handlers {
  _Handlers(this.onPlay, this.onPause, this.onSeekBy, this.back, this.forward);
  final Future<void> Function() onPlay;
  final Future<void> Function() onPause;
  final void Function(int seconds) onSeekBy;
  final int back;
  final int forward;
}
