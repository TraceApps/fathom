import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fathom/theme/app_theme.dart' show kInlineButtonStyle;

// _EditRequestDialog (seerr_edit_request_dialog.dart) and _SeerrRequestDialog
// (seerr_request_dialog.dart) are file-private, so this reconstructs their
// exact actions-row shape (a right-aligned Cancel + Save/Request button
// pair) rather than importing them directly. Pins the layout that replaced a
// real overflow: German "Abbrechen"/"Speichern"/"Staffel(n) auswählen" (long
// translations of Cancel/Save/"Select Seasons") overflowed a plain
// Row on any phone narrower than ~400 logical pixels, a very common width,
// even though the English labels always fit.
Widget buildEditRequestActions({required double dialogMaxWidth}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: dialogMaxWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () {}, child: const Text('Abbrechen')),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: kInlineButtonStyle,
                      onPressed: () {},
                      child: const Text('Speichern'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget buildRequestDialogActions({required double dialogMaxWidth}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: dialogMaxWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () {}, child: const Text('Abbrechen')),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: kInlineButtonStyle,
                      onPressed: () {},
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Staffel(n) auswählen'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final width in [460.0, 400.0, 360.0, 320.0, 280.0]) {
    testWidgets('EditRequest dialog actions never overflow at phone width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(buildEditRequestActions(dialogMaxWidth: 460));
      expect(tester.takeException(), isNull, reason: 'width=$width');
    });
  }

  for (final width in [560.0, 400.0, 360.0, 320.0, 280.0]) {
    testWidgets('RequestDialog actions never overflow at phone width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(buildRequestDialogActions(dialogMaxWidth: 560));
      expect(tester.takeException(), isNull, reason: 'width=$width');
    });
  }
}
