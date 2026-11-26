import 'dart:io';

import 'package:fathom/widgets/cached_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';

// A download cut short leaves an empty or half-written picture in the cache.
// The cache went on listing it, so the same poster failed to draw at every
// launch for three weeks. Seen on the foldable emulator after it crashed
// mid-download: twelve posters saved as empty files, blank from then on.

class _Cache extends Fake implements BaseCacheManager {
  final removed = <String>[];
  bool fail = false;

  @override
  Future<void> removeFile(String key) async {
    if (fail) throw const FileSystemException('busy');
    removed.add(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a picture that cannot be read is thrown out of the cache', () async {
    final cache = _Cache();
    await forgetBrokenImage('http://jf/Items/1/Images/Primary', cache: cache);
    expect(cache.removed, ['http://jf/Items/1/Images/Primary']);
  });

  test('and a cache that will not let go does not stop the retry', () async {
    final cache = _Cache()..fail = true;
    await expectLater(
      forgetBrokenImage('http://jf/x', cache: cache),
      completes,
    );
  });

  test('a failed picture is fetched afresh once, not for ever', () {
    final src = File('lib/widgets/cached_image.dart').readAsStringSync();
    expect(src, contains('errorListener: (_) => _failed()'));
    expect(src, contains('if (_retried) return;'));
    expect(src, contains('key: ValueKey(_attempt)'));
  });
}
