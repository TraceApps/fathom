import 'package:fathom/widgets/arr_bulk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('picking starts, toggles and ends', () {
    final s = ArrSelection();
    expect(s.active, isFalse);
    s.start(3);
    expect(s.active, isTrue);
    expect(s.ids, {3});
    s.toggle(5);
    s.toggle(3);
    expect(s.ids, {5});
    s.stop();
    expect((s.active, s.length), (false, 0));
  });

  test('a search or filter change drops what went out of sight', () {
    // So a bulk delete never reaches titles the person can't see.
    final s = ArrSelection()..start();
    s.selectAll([1, 2, 3, 4]);
    var told = 0;
    s.addListener(() => told++);
    s.keepOnly({2, 4, 9});
    expect(s.ids, {2, 4});
    expect(told, 1);
    s.keepOnly({2, 4});
    expect(told, 1, reason: 'nothing dropped, nothing to redraw');
  });
}
