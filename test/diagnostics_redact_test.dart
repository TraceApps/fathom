import 'package:fathom/services/diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

// The diagnostics report is made to be pasted into a public issue. A stream's
// address carries the sign-in token, and libmpv, a cast or an image error can
// each quote that address in a line of their own: no credential may reach
// the report, whoever wrote the line.
void main() {
  const token = 'f3a9c1d2e4b5a6978877665544332211';
  final d = Diagnostics.instance;

  setUp(() {
    d
      ..clear()
      ..enabled = true
      ..protect(const []);
  });
  tearDown(() {
    d
      ..clear()
      ..enabled = false
      ..protect(const []);
  });

  String report() => d.report(const {});

  test('an address in a line of libmpv, a cast or an error', () {
    d.add(
      'mpv',
      'cplayer [v] Playing: http://10.0.0.5:8096/Videos/42/stream.mkv'
          '?Static=true&api_key=$token&MediaSourceId=42',
    );
    d.add('app', '[cast] load url=http://10.0.0.5:8096/Audio/7/universal?api_key=$token');
    d.add(
      'error',
      "HTTP request failed, statusCode: 404, http://10.0.0.5:8096/Items/1/Images/Primary?ApiKey=$token&quality=90",
    );
    d.add('mpv', "ffmpeg [v] Opening 'http://sab:8085/api?mode=queue&apikey=$token&output=json'");
    final r = report();
    expect(r, isNot(contains(token)));
    // What was asked for is still readable.
    expect(r, contains('/Videos/42/stream.mkv?Static=true&api_key=<redacted>&MediaSourceId=42'));
    expect(r, contains('apikey=<redacted>&output=json'));
    expect(r, contains('quality=90'));
  });

  test('a request header, and Jellyfin\'s own', () {
    d.add('net', 'X-Emby-Token: $token');
    d.add('net', 'x-api-key=$token');
    d.add('net', 'Authorization: MediaBrowser Client="Fathom", Token="$token"');
    d.add('net', 'Cookie: QBT_SID_8080=$token; other=1');
    d.add('net', 'MediaBrowser Device="TV", Token="$token", Version="1.0"');
    final r = report();
    expect(r, isNot(contains(token)));
    expect(r, contains('X-Emby-Token: <redacted>'));
    expect(r, contains('Version="1.0"'));
  });

  test('a secret the app holds, wherever it turns up', () {
    const password = 'p@ss word/1';
    d.protect(const [token, password, 'abc', null]);
    d.add('app', 'opening /Users/$token/Items');
    d.add('app', 'signing in to qBittorrent as admin with $password');
    d.add('app', 'form body username=admin&x=${Uri.encodeQueryComponent(password)}');
    // Too short to be worth hiding: it would blank ordinary words.
    d.add('app', 'the abc of it');
    final r = report();
    expect(r, isNot(contains(token)));
    expect(r, isNot(contains(password)));
    expect(r, isNot(contains(Uri.encodeQueryComponent(password))));
    expect(r, contains('/Users/<redacted>/Items'));
    expect(r, contains('the abc of it'));
  });

  test('where the user\'s servers are, in a line and in the header', () {
    d.protect(
      const [],
      addresses: const [
        'https://media.smith-family.example:8920/jellyfin',
        '192.168.1.44:8989',
        'http://localhost:7878',
        '',
        null,
      ],
    );
    d.add('mpv', 'Playing: https://media.smith-family.example:8920/jellyfin/Videos/1/stream');
    d.add('app', 'Could not reach http://192.168.1.44:8989/api/v3/queue');
    d.add('app', 'asking http://localhost:7878');
    final r = d.report(const {
      'Server address': 'https://media.smith-family.example:8920/jellyfin',
    });
    expect(r, isNot(contains('smith-family')));
    expect(r, isNot(contains('192.168.1.44')));
    // The rest of an address stays: scheme, port, path.
    expect(r, contains('Server address: https://<host>:8920/jellyfin'));
    expect(r, contains('https://<host>:8920/jellyfin/Videos/1/stream'));
    expect(r, contains('http://<host>:8989/api/v3/queue'));
    expect(r, contains('http://localhost:7878'));
  });

  test('what isn\'t a credential is left as it is', () {
    d.add('mpv', 'vd [v] Using hardware decoding (vaapi), bypass=1, keyframe=250');
    d.add('app', 'monkey=banana&compass=north');
    final r = report();
    expect(r, contains('bypass=1, keyframe=250'));
    expect(r, contains('monkey=banana&compass=north'));
  });

  test('redactUrl still hides a query\'s credentials', () {
    expect(
      redactUrl('http://h/x?api_key=$token&a=1'),
      isNot(contains(token)),
    );
  });
}
