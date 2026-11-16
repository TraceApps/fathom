import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/services/youtube_dropout.dart';

// The picture of a YouTube video playing on with no sound, or a stream that
// stands still while saying it's playing. Neither ends the video, so nothing
// used to notice. These must also leave healthy playback alone.
void main() {
  final t0 = DateTime(2026, 11, 16);
  const dur = Duration(minutes: 3);

  /// Feeds samples 3 s apart: (video seconds, audio clock or null).
  List<YtStall?> run(YtStallWatch w, List<(double, double?)> samples,
      {bool playing = true,
      bool loading = false,
      Duration duration = dur}) {
    var i = 0;
    return [
      for (final (v, a) in samples)
        w.sample(
          position: Duration(milliseconds: (v * 1000).round()),
          duration: duration,
          audioPts: a,
          playing: playing,
          loading: loading,
          now: t0.add(Duration(seconds: 3 * i++)),
        ),
    ];
  }

  test('audio gone while the picture plays on is silent, for as long as it lasts',
      () {
    final r = run(YtStallWatch(), [
      (54, 54), (57, 57), (60, null), (63, null), (66, null), (69, null),
    ]);
    expect(r.indexOf(YtStall.silent), 4, reason: '6 s after the audio stopped');
    expect(r.sublist(4), [YtStall.silent, YtStall.silent],
        reason: 'keeps reporting, so a restart can escalate to a reload');
  });

  test('an audio clock stuck while the picture moves is silent too', () {
    final r = run(YtStallWatch(), [
      (10, 10), (13, 12.5), (16, 12.5), (19, 12.5), (22, 12.5),
    ]);
    expect(r.whereType<YtStall>(), isNotEmpty);
    expect(r.whereType<YtStall>().toSet(), {YtStall.silent});
  });

  test('a playing video standing still is frozen', () {
    final r = run(YtStallWatch(), [for (var i = 0; i < 9; i++) (59.4, 59.4)]);
    expect(r.whereType<YtStall>().toSet(), {YtStall.frozen});
    expect(r.indexOf(YtStall.frozen), 8,
        reason: '20 s still, counted from the first sample after the baseline');
  });

  test('seeks, including a brief audio gap after each, are not silence', () {
    expect(
      run(YtStallWatch(), [
        (0, null), (2, 2), (5, 5), (8, 8),
        (38, null), (40, 40), (70, null), (72, 72), (102, null), (104, 104),
        (20, null), (22, 22), (25, 25),
      ]).whereType<YtStall>(),
      isEmpty,
    );
  });

  test('audio ending before the picture in the last seconds is left alone',
      () {
    expect(
      run(YtStallWatch(), [
        (163, 163), (166, 166), (169, null), (172, null), (175, null),
        (178, null),
      ]).whereType<YtStall>(),
      isEmpty,
    );
  });

  test('paused, loading, or a video without audio is left alone', () {
    expect(
      run(YtStallWatch(), [for (var i = 0; i < 12; i++) (30, 30)],
          playing: false).whereType<YtStall>(),
      isEmpty,
    );
    expect(
      run(YtStallWatch(), [for (var i = 0; i < 12; i++) (30, 30)],
          loading: true).whereType<YtStall>(),
      isEmpty,
    );
    expect(
      run(YtStallWatch(), [for (var i = 0; i < 12; i++) (i * 3.0, null)])
          .whereType<YtStall>(),
      isEmpty,
      reason: 'no audio ever played: nothing was lost',
    );
  });

  test('2x speed is playback, not a seek', () {
    expect(
      run(YtStallWatch(), [for (var i = 0; i < 10; i++) (i * 6.0, i * 6.0)])
          .whereType<YtStall>(),
      isEmpty,
    );
  });

  test('a reload starts the watch afresh', () {
    final w = YtStallWatch();
    run(w, [(54, 54), (57, 57), (60, null), (63, null), (66, null)]);
    w.reset();
    expect(run(w, [(60, null), (63, null), (66, null), (69, null)])
        .whereType<YtStall>(), isEmpty,
        reason: 'the new stream has not played audio yet');
  });
}
