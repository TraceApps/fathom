import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// Stands in for a libmpv player in widget tests that only draw the
/// controls around one. A real player starts a native media engine per
/// test file: slow, and on a CI runner with no sound device it could hang
/// when disposed. The controls only read its state and listen to its
/// streams, so this keeps a state and stays quiet.
class FakePlayer implements Player {
  FakePlayer([this._state = const PlayerState()]);

  PlayerState _state;
  final _volumes = StreamController<double>.broadcast();
  final _playing = StreamController<bool>.broadcast();

  /// What was asked of it, in order: `playOrPause`, `seek`, `setVolume`.
  final asked = <String>[];

  @override
  PlayerState get state => _state;

  @override
  PlayerStream get stream => _FakeStreams(
    volume: _volumes.stream,
    playing: _playing.stream,
  );

  @override
  Future<void> setVolume(double volume) async {
    asked.add('setVolume');
    _state = _state.copyWith(volume: volume);
    _volumes.add(volume);
  }

  @override
  Future<void> playOrPause() async {
    asked.add('playOrPause');
    _state = _state.copyWith(playing: !_state.playing);
    _playing.add(_state.playing);
  }

  @override
  Future<void> seek(Duration position) async {
    asked.add('seek');
    _state = _state.copyWith(position: position);
  }

  @override
  Future<void> dispose() async {
    await _volumes.close();
    await _playing.close();
  }

  // Anything else a widget asks of it is accepted and does nothing.
  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.isMethod) {
      asked.add(i.memberName.toString());
      return Future<void>.value();
    }
    return super.noSuchMethod(i);
  }
}

class _FakeStreams implements PlayerStream {
  _FakeStreams({required this.volume, required this.playing});

  @override
  final Stream<double> volume;

  @override
  final Stream<bool> playing;

  // Every other stream (position, buffer, tracks...) simply never speaks.
  @override
  dynamic noSuchMethod(Invocation i) =>
      i.isGetter ? const Stream<Never>.empty() : super.noSuchMethod(i);
}
