import 'package:dio/dio.dart';
import 'package:fathom/api/seerr_client.dart';
import 'package:fathom/models/seerr_result.dart';
import 'package:flutter_test/flutter_test.dart';

SeerrResult _title({int? status, bool active = false}) => SeerrResult.fromJson({
      'id': 1,
      'mediaType': 'movie',
      'title': 'A Movie',
      if (status != null)
        'mediaInfo': {'status': status, 'hasActiveRequest': active},
    });

DioException _error(int code, Object? body) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.badResponse,
      response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: code,
          data: body),
    );

void main() {
  group('Discover hide settings, as Seerr applies them', () {
    test('nothing is hidden when every setting is off', () {
      for (final s in [null, 2, 4, 5, 6]) {
        expect(SeerrHideRules.none.hides(_title(status: s, active: true)),
            isFalse);
      }
    });

    test('Hide Available covers available and partly available titles', () {
      const rules = SeerrHideRules(available: true);
      expect(rules.hides(_title(status: 5)), isTrue);
      expect(rules.hides(_title(status: 4)), isTrue);
      expect(rules.hides(_title(status: 3)), isFalse);
      expect(rules.hides(_title()), isFalse);
    });

    test('Hide Already Requested follows the active-request mark', () {
      const rules = SeerrHideRules(requested: true);
      expect(rules.hides(_title(status: 2, active: true)), isTrue);
      expect(rules.hides(_title(status: 3, active: false)), isFalse);
      expect(rules.hides(_title()), isFalse);
    });

    test('Hide Blocklisted covers blocklisted titles', () {
      const rules = SeerrHideRules(blocklisted: true);
      expect(rules.hides(_title(status: 6)), isTrue);
      expect(rules.hides(_title(status: 5)), isFalse);
    });
  });

  group('Seerr error messages', () {
    test("a refused action shows Seerr's own reason", () {
      expect(
          seerrErrorMessage(
              _error(409, {'message': 'Request is not pending.'})),
          'Seerr: Request is not pending.');
      expect(
          seerrErrorMessage(_error(403,
              {'message': 'You have reached your request limit.'})),
          'Seerr: You have reached your request limit.');
    });

    test('a turned-away key or session still says so', () {
      expect(
          seerrErrorMessage(_error(403,
              {'status': 403, 'error': 'You do not have permission'})),
          'Seerr rejected the API key.');
      expect(seerrErrorMessage(_error(401, null)),
          'Seerr rejected the API key.');
    });

    test('anything else names the status', () {
      expect(seerrErrorMessage(_error(500, '<html>')), 'Seerr error (500).');
    });
  });
}
