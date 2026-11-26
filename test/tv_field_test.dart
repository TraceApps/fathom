import 'dart:io';

import 'package:fathom/services/tv_mode.dart';
import 'package:fathom/widgets/tv_keyboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A text field written the ordinary way traps a remote: it swallows the
// arrow keys and raises a keyboard the remote can't drive. Administration,
// the user editor and Profile had nineteen of them.

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: Column(children: [child])),
);

void main() {
  tearDown(() => isTvDevice = false);

  testWidgets('off a TV it is the field as written', (t) async {
    await t.pumpWidget(
      _app(const TvField(child: TextField(decoration: InputDecoration(labelText: 'Name')))),
    );
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('on a TV it is a tile, with the label and the text', (t) async {
    isTvDevice = true;
    final c = TextEditingController(text: 'Living Room');
    await t.pumpWidget(
      _app(
        TvField(
          child: TextField(
            controller: c,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
        ),
      ),
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Living Room'), findsOneWidget);
  });

  testWidgets('a form field starts from its value and reports changes', (
    t,
  ) async {
    isTvDevice = true;
    final heard = <String>[];
    await t.pumpWidget(
      _app(
        TvField(
          label: 'Port',
          child: TextFormField(initialValue: '8096', onChanged: heard.add),
        ),
      ),
    );
    expect(find.text('Port'), findsOneWidget);
    expect(find.text('8096'), findsOneWidget);
    // What the TV keyboard does: write to the controller.
    final state = t.state(find.byType(TvField)) as dynamic;
    (state.debugController as TextEditingController).text = '9000';
    await t.pump();
    expect(heard, ['9000']);
    expect(find.text('9000'), findsOneWidget);
  });

  testWidgets('a password shows dots', (t) async {
    isTvDevice = true;
    await t.pumpWidget(
      _app(
        TvField(
          child: TextField(
            controller: TextEditingController(text: 'abc'),
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
        ),
      ),
    );
    expect(find.text('abc'), findsNothing);
    expect(find.text('•••'), findsOneWidget);
  });

  test('no bare text field in Administration, the user editor or Profile', () {
    final bare = RegExp(r'(?<!child: )(?<![A-Za-z_])(TextField|TextFormField)\(');
    final files = [
      ...Directory('lib/screens/admin').listSync().whereType<File>(),
      File('lib/screens/admin_screen.dart'),
      File('lib/screens/user_edit_screen.dart'),
      File('lib/screens/profile_screen.dart'),
    ];
    expect(
      [
        for (final f in files)
          if (bare.hasMatch(f.readAsStringSync())) f.path,
      ],
      isEmpty,
    );
  });
}
