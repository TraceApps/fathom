import 'dart:io';

import 'package:fathom/l10n/generated/app_localizations.dart';
import 'package:fathom/models/session.dart';
import 'package:fathom/state/session_controller.dart';
import 'package:fathom/widgets/sign_out.dart';
import 'package:fathom/widgets/ui_common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SignedIn extends SessionController {
  int signedOut = 0;
  @override
  Future<Session?> build() async => const Session(
    baseUrl: 'http://jelly:8096',
    accessToken: 't',
    userId: 'u',
    userName: 'joe',
    serverName: 'Home',
  );
  @override
  Future<void> signOut() async {
    signedOut++;
    state = const AsyncData(null);
  }
}

/// Every call of the app's confirm() in [src], whole.
Iterable<String> _confirms(String src) sync* {
  for (final m in RegExp(r'(?<![A-Za-z_.])confirm\(').allMatches(src)) {
    if (src.substring(0, m.start).endsWith('Future<bool> ')) continue;
    var i = m.end, depth = 1;
    while (depth > 0 && i < src.length) {
      if (src[i] == '(') depth++;
      if (src[i] == ')') depth--;
      i++;
    }
    yield src.substring(m.start, i);
  }
}

// Anything that deletes, removes, clears or signs out asks first, and asks
// safely: the button is red and focus starts on Cancel, so a stray Enter (or
// a TV remote's Select) can't confirm. Twenty of these used to open with
// focus on the button that does the deed, and a handful didn't ask at all.
void main() {
  Widget host(Widget child, {List<Object> overrides = const []}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  testWidgets('a destructive confirm: Enter backs out, the button is red', (
    t,
  ) async {
    bool? answer;
    await t.pumpWidget(
      host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => answer = await confirm(
              context,
              title: 'Delete Recording?',
              message: 'Gone for good.',
              confirmLabel: 'Delete',
              destructive: true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    final delete = t.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Delete'),
    );
    final scheme = Theme.of(t.element(find.text('Delete'))).colorScheme;
    expect(delete.style!.backgroundColor!.resolve({}), scheme.error);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(answer, isFalse);
    // And the button itself still does it.
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Delete'));
    await t.pumpAndSettle();
    expect(answer, isTrue);
  });

  testWidgets('Sign Out asks, and Cancel keeps the account', (t) async {
    final session = _SignedIn();
    late WidgetRef ref;
    await t.pumpWidget(
      ProviderScope(
        overrides: [sessionControllerProvider.overrideWith(() => session)],
        child: host(
          Consumer(
            builder: (context, r, _) {
              ref = r;
              r.watch(sessionControllerProvider);
              return TextButton(
                onPressed: () => confirmSignOut(context, r),
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Sign Out?'), findsOneWidget);
    expect(
      find.text("You'll need to sign in again to use Home on this device."),
      findsOneWidget,
    );
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(session.signedOut, 0);
    expect(ref.read(sessionControllerProvider).value, isNotNull);
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Sign Out'));
    await t.pumpAndSettle();
    expect(session.signedOut, 1);
  });

  test('every confirm that deletes, removes or clears is marked destructive', () {
    final destructiveLabel = RegExp(
      r'confirmLabel:\s*(?:[a-z]+\s*\?\s*)?l\.(commonDelete|commonRemove|commonClear|'
      r'commonSignOut|adminRevoke|adminUninstall|adminShutDown|adminRestart|'
      r'downloadsCancelAll|detailCancelRecording|arrDisconnect)\b',
    );
    final missing = <String>[];
    var seen = 0;
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final call in _confirms(f.readAsStringSync())) {
        if (!destructiveLabel.hasMatch(call)) continue;
        seen++;
        if (!call.contains('destructive: true')) {
          missing.add('${f.path}: ${call.replaceAll(RegExp(r'\s+'), ' ')}');
        }
      }
    }
    expect(seen, greaterThan(25));
    expect(missing, isEmpty);
  });

  test('nothing signs out, or removes an account, without asking', () {
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (!f.path.endsWith('widgets/sign_out.dart') &&
          !f.path.endsWith('state/session_controller.dart')) {
        expect(
          RegExp(r'\.signOut\(\)').hasMatch(src) &&
              src.contains('sessionControllerProvider.notifier).signOut()'),
          isFalse,
          reason: f.path,
        );
      }
    }
    // The buttons that delete on the server, or a finished download, go
    // through a question.
    String src(String p) => File(p).readAsStringSync();
    expect(
      src('lib/screens/admin/admin_devices_screen.dart'),
      contains('adminRemoveDeviceTitle'),
    );
    final dvr = src('lib/screens/admin/admin_livetv_screens.dart');
    for (final k in [
      'adminDeleteRecordingTitle',
      'adminCancelRecordingTitle',
      'adminDeleteSeriesRuleTitle',
    ]) {
      expect(dvr, contains(k));
    }
    // No button calls them straight any more.
    expect(dvr, isNot(contains('onPressed: () => _cancelTimer(')));
    expect(dvr, isNot(contains('onPressed: () => _cancelSeries(')));
    expect(dvr, isNot(contains('onDelete: (id) => _deleteRecording(')));
    final downloads = src('lib/screens/downloads_screen.dart');
    expect(downloads, isNot(contains('onPressed: () => controller.delete(')));
    expect(downloads, isNot(contains('onPressed: () => controller.deleteSeries(')));
    expect(src('lib/screens/youtube_screen.dart'), contains('ytDeletePlaylistTitle'));
    expect(src('lib/screens/accounts_screen.dart'), contains('accountsRemoveTitle'));
  });
}
