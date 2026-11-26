import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fathom/api/arr_client.dart';
import 'package:fathom/api/error_text.dart';
import 'package:fathom/api/jellyfin_client.dart';
import 'package:fathom/api/seerr_client.dart';
import 'package:flutter_test/flutter_test.dart';

// One way to say what went wrong. A failure nobody had worded reached the
// screen as Dart prints it: "DioException [connection error]: ...", "type
// 'Null' is not a subtype of type 'String'".

DioException _dio(DioExceptionType type, {int? code, Object? error}) =>
    DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: type,
      error: error,
      response: code == null
          ? null
          : Response(requestOptions: RequestOptions(path: '/x'), statusCode: code),
    );

void main() {
  test("a client's own message is shown as written", () {
    expect(errorText(JellyfinException('Incorrect username or password.')),
        'Incorrect username or password.');
    expect(errorText(ArrException('Radarr rejected the API key.')),
        'Radarr rejected the API key.');
    expect(errorText(SeerrException('Seerr: Request limit reached.')),
        'Seerr: Request limit reached.');
  });

  test('also when the network layer carries it', () {
    expect(
      errorText(
        _dio(DioExceptionType.unknown, error: ArrException('Could not reach Sonarr.')),
      ),
      'Could not reach Sonarr.',
    );
  });

  test('a failed request is said plainly, never as Dart prints it', () {
    final cases = {
      _dio(DioExceptionType.connectionError): 'Lost connection to the server.',
      _dio(DioExceptionType.receiveTimeout): startsWith('The server took too long'),
      _dio(DioExceptionType.badCertificate): contains('certificate'),
      _dio(DioExceptionType.badResponse, code: 500):
          'The server returned an error (500).',
      _dio(DioExceptionType.badResponse, code: 404):
          'The requested resource was not found (404).',
      _dio(DioExceptionType.badResponse, code: 401): contains('Sign in again'),
    };
    cases.forEach((e, want) {
      final text = errorText(e);
      expect(text, want);
      expect(text, isNot(contains('DioException')));
    });
  });

  test('a first connection says there is no server, not "resource"', () {
    expect(
      dioErrorText(_dio(DioExceptionType.badResponse, code: 404), connecting: true),
      'No Jellyfin server was found at that address.',
    );
    expect(
      dioErrorText(_dio(DioExceptionType.connectionError), connecting: true),
      startsWith('Could not reach that server.'),
    );
  });

  test('what the system throws is worded too', () {
    expect(errorText(const SocketException('x')), 'Lost connection to the server.');
    expect(errorText(TimeoutException('x')), startsWith('The server took too long'));
  });

  test("an Exception with words of ours loses Dart's prefix", () {
    expect(errorText(Exception('ffmpeg: no such file')), 'ffmpeg: no such file');
  });

  test("a fault inside the app isn't printed at the person", () {
    late Object fault;
    try {
      (null as dynamic).length;
    } catch (e) {
      fault = e;
    }
    final text = errorText(fault);
    expect(text, startsWith('Something went wrong.'));
    expect(text, isNot(contains('NoSuchMethod')));
    expect(errorText(const FormatException('bad')), startsWith('Something went wrong.'));
  });

  test('no screen prints an error as Dart does', () {
    final raw = RegExp(
      r"""message: '\$e'|Text\('\$e'|_error = '\$e'|\be\.toString\(\)|\.error\.toString\(\)""",
    );
    expect(
      [
        for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.dart') &&
              (f.path.contains('/screens/') ||
                  f.path.contains('/widgets/') ||
                  f.path.contains('/state/')) &&
              raw.hasMatch(f.readAsStringSync()))
            f.path,
      ],
      isEmpty,
    );
  });

  test("the clients' own messages come from the strings file", () {
    // A message written in English inside a client can't be translated. The
    // app's name in front of a server's own words ("SABnzbd: ...") is fine.
    final english = RegExp(r'''Exception\(\s*['"](?![A-Za-z]+: \$)[A-Z][a-z]+ [a-z]''');
    expect(
      [
        for (final dir in ['lib/api', 'lib/state', 'lib/models'])
          for (final f in Directory(dir).listSync(recursive: true).whereType<File>())
            if (f.path.endsWith('.dart') && english.hasMatch(f.readAsStringSync()))
              f.path,
      ],
      isEmpty,
    );
  });

  test('what the updater and file mover say reaches the screen', () {
    // They are written for the reader. Thrown as a StateError they were
    // replaced by the general line, and the reason was shown nowhere.
    for (final f in ['lib/services/app_installer.dart', 'lib/services/shared_files.dart']) {
      expect(File(f).readAsStringSync(), isNot(contains('throw StateError(')), reason: f);
    }
    expect(
      errorText(Exception('The update download was incomplete. Your current version was kept.')),
      'The update download was incomplete. Your current version was kept.',
    );
  });
}
