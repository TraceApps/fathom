import 'package:fathom/services/settings_backup.dart';
import 'package:fathom/state/preferences.dart';
import 'package:flutter_test/flutter_test.dart';

// A backup never carries keys or passwords; the ones on this device stay. A
// restore that changed a connection's address used to leave this device's
// key beside it: the next check sent that key to the new address, which may
// be another server, or (a backup passed along) someone else's.
void main() {
  const mine = Prefs(
    prowlarrUrl: 'http://192.168.1.10:9696',
    prowlarrApiKey: 'prowlarr-key',
    bazarrUrl: 'http://192.168.1.10:6767',
    bazarrApiKey: 'bazarr-key',
    sabUrl: 'http://192.168.1.10:8085',
    sabApiKey: 'sab-key',
    qbitUrl: 'http://192.168.1.10:8080',
    qbitUsername: 'admin',
    qbitPassword: 'qbit-pass',
    seerrUrl: 'https://requests.example.com',
    seerrApiKey: 'seerr-key',
    seerrCookie: 'seerr-cookie',
    mdbListApiKey: 'mdb-key',
    themeMode: 'dark',
  );
  const all = {'appearance', 'player', 'youtube', 'general'};

  Prefs restore(Map<String, dynamic> backup, [Set<String> groups = all]) =>
      restoredPrefs(mine, backup, groups)!;

  test('the same addresses: every key stays', () {
    final p = restore({
      ...mine.toJson()..removeWhere((k, _) => secretPrefKeys.contains(k)),
      'themeMode': 'light',
    });
    expect(p.themeMode, 'light');
    expect(p.prowlarrApiKey, 'prowlarr-key');
    expect(p.bazarrApiKey, 'bazarr-key');
    expect(p.sabApiKey, 'sab-key');
    expect(p.qbitPassword, 'qbit-pass');
    expect((p.seerrApiKey, p.seerrCookie), ('seerr-key', 'seerr-cookie'));
    expect(p.mdbListApiKey, 'mdb-key');
  });

  test('a trailing slash or a capital is the same address', () {
    final p = restore({
      'prowlarrUrl': 'http://192.168.1.10:9696/',
      'seerrUrl': 'https://Requests.Example.com',
    });
    expect(p.prowlarrApiKey, 'prowlarr-key');
    expect(p.seerrApiKey, 'seerr-key');
  });

  test('another address: that connection\'s key is not sent there', () {
    final p = restore({
      'prowlarrUrl': 'http://elsewhere.example:9696',
      'bazarrUrl': 'http://elsewhere.example:6767',
      'sabUrl': 'http://elsewhere.example:8085',
      'qbitUrl': 'http://elsewhere.example:8080',
      'seerrUrl': 'https://elsewhere.example',
    });
    expect(p.prowlarrUrl, 'http://elsewhere.example:9696');
    expect(p.prowlarrApiKey, isEmpty);
    expect(p.bazarrApiKey, isEmpty);
    expect(p.sabApiKey, isEmpty);
    expect(p.qbitPassword, isEmpty);
    expect((p.seerrApiKey, p.seerrCookie), ('', ''));
    // What has no address of its own is untouched.
    expect(p.mdbListApiKey, 'mdb-key');
  });

  test('only the one that moved', () {
    final p = restore({'sabUrl': 'http://192.168.1.99:8085'});
    expect(p.sabApiKey, isEmpty);
    expect(p.prowlarrApiKey, 'prowlarr-key');
    expect(p.qbitPassword, 'qbit-pass');
    expect(p.seerrApiKey, 'seerr-key');
  });

  test('qBittorrent as another user: the password isn\'t tried for them', () {
    final p = restore({'qbitUsername': 'someone'});
    expect(p.qbitUrl, mine.qbitUrl);
    expect(p.qbitPassword, isEmpty);
  });

  test('a secret in the file is never taken', () {
    final p = restore({
      'prowlarrApiKey': 'from-the-file',
      'qbitPassword': 'from-the-file',
      'seerrApiKey': 'from-the-file',
      'themeMode': 'light',
    });
    expect(p.prowlarrApiKey, 'prowlarr-key');
    expect(p.qbitPassword, 'qbit-pass');
    expect(p.seerrApiKey, 'seerr-key');
  });

  test('a group not picked changes nothing of it', () {
    // Addresses are General: restoring Appearance alone leaves them be.
    final p = restore({
      'themeMode': 'light',
      'sabUrl': 'http://elsewhere.example:8085',
    }, {'appearance'});
    expect(p.themeMode, 'light');
    expect(p.sabUrl, mine.sabUrl);
    expect(p.sabApiKey, 'sab-key');
    expect(restoredPrefs(mine, {'sabUrl': 'x'}, {'appearance'}), isNull);
  });

  test('a value this build can\'t read costs that setting, not the restore', () {
    final p = restore({'themeMode': 'light', 'accentColor': 'blue'});
    expect(p.themeMode, 'light');
    expect(p.accentColor, const Prefs().accentColor);
    expect(p.prowlarrApiKey, 'prowlarr-key');
  });
}
