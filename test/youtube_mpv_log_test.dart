import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/services/youtube_stream_recovery.dart';

void main() {
  test('mpv log lines keep only the host of a stream URL', () {
    expect(
      mpvLogWithoutQueries(
          'Opening failed: https://rr3---sn-abc.googlevideo.com/videoplayback?expire=1&ip=203.0.113.7&sig=XYZ'),
      'Opening failed: https://rr3---sn-abc.googlevideo.com/...',
    );
    expect(
      mpvLogWithoutQueries(
          'http: HTTP error 403 https://rr1.googlevideo.com/videoplayback/ip/203.0.113.7/id/9 '),
      'http: HTTP error 403 https://rr1.googlevideo.com/...',
    );
    expect(mpvLogWithoutQueries('Will reconnect at 1234 '), 'Will reconnect at 1234');
  });
}
