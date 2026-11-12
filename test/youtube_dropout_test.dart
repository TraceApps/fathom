import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/services/youtube_dropout.dart';

// The lines real libmpv (through media_kit, at warn level) logged when a relay
// cut the audio connection and refused the reconnect with 403, as googlevideo
// does once the address that resolved the link has changed.
const _premature = 'http: Stream ends prematurely at 242842, should be 485685';
const _reconnect =
    'http: Will reconnect at 242842 in 0 second(s), error=Input/output error.';
const _refused = 'http: HTTP error 403 Forbidden';

void main() {
  final t0 = DateTime(2026, 11, 12, 22, 45);

  test('a refused reconnect is a dropout', () {
    final w = YtDropoutWatch();
    expect(w.refusedAfterReconnect('ffmpeg', _premature, now: t0), isFalse);
    expect(w.refusedAfterReconnect('ffmpeg', _reconnect, now: t0), isFalse);
    expect(
      w.refusedAfterReconnect(
        'ffmpeg',
        _refused,
        now: t0.add(const Duration(milliseconds: 80)),
      ),
      isTrue,
    );
    // Once per reconnect: a second 403 with no new reconnect is not another.
    expect(w.refusedAfterReconnect('ffmpeg', _refused, now: t0), isFalse);
  });

  test('a 4xx without a reconnect before it is left alone', () {
    // A caption or other one-off fetch being refused.
    final w = YtDropoutWatch();
    expect(w.refusedAfterReconnect('ffmpeg', _refused, now: t0), isFalse);
    expect(
      w.refusedAfterReconnect(
        'ffmpeg',
        'http: HTTP error 404 Not Found',
        now: t0,
      ),
      isFalse,
    );
  });

  test('a reconnect that worked, then a much later 403, is not a dropout', () {
    final w = YtDropoutWatch();
    w.refusedAfterReconnect('ffmpeg', _reconnect, now: t0);
    expect(
      w.refusedAfterReconnect(
        'ffmpeg',
        _refused,
        now: t0.add(const Duration(minutes: 5)),
      ),
      isFalse,
    );
  });

  test('only ffmpeg lines count', () {
    final w = YtDropoutWatch();
    w.refusedAfterReconnect('cplayer', _reconnect, now: t0);
    expect(w.refusedAfterReconnect('ffmpeg', _refused, now: t0), isFalse);
  });

  test('ended early: short of the end is a dropout, the end is not', () {
    const dur = Duration(seconds: 30);
    // Measured on real mpv: both tracks refused stopped at 14.4s of 30s; a
    // clean play reported completed at 29.6s.
    expect(
      YtDropoutWatch.endedEarly(const Duration(milliseconds: 14394), dur),
      isTrue,
    );
    expect(
      YtDropoutWatch.endedEarly(const Duration(milliseconds: 29611), dur),
      isFalse,
    );
    expect(YtDropoutWatch.endedEarly(dur, dur), isFalse);
    // No duration known: never claim a dropout.
    expect(
      YtDropoutWatch.endedEarly(const Duration(seconds: 3), Duration.zero),
      isFalse,
    );
  });

  test('gives up after three dropouts close together', () {
    final w = YtDropoutWatch();
    const at = Duration(minutes: 4);
    expect(w.takeTry(at), isTrue);
    expect(w.takeTry(at + const Duration(seconds: 2)), isTrue);
    expect(w.takeTry(at + const Duration(seconds: 5)), isTrue);
    expect(
      w.takeTry(at + const Duration(seconds: 6)),
      isFalse,
      reason: 'a video that keeps dropping on the spot moves on',
    );
  });

  test('dropouts far apart always recover', () {
    final w = YtDropoutWatch();
    for (var m = 1; m <= 6; m++) {
      expect(
        w.takeTry(Duration(minutes: m * 5)),
        isTrue,
        reason: 'drop at ${m * 5} min',
      );
    }
  });

  test('a chain of drops with playback between them keeps recovering', () {
    // 1:00, 2:30, 4:00, 5:30: each one played well past the last.
    final w = YtDropoutWatch();
    for (final s in [60, 150, 240, 330, 420]) {
      expect(w.takeTry(Duration(seconds: s)), isTrue, reason: 'drop at ${s}s');
    }
  });
}
