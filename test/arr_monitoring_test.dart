import 'package:fathom/models/arr.dart';
import 'package:fathom/widgets/arr_monitoring.dart';
import 'package:flutter_test/flutter_test.dart';

// What a Monitoring choice sends to Sonarr. Checked against Sonarr 4.0.20:
// every episode choice turns the specials off and leaves the show's own
// switch alone; monitorSpecials and unmonitorSpecials touch only season 0.
void main() {
  List<String> plan(
    String choice, {
    bool specials = false,
    bool before = false,
    bool hasSpecials = true,
  }) => arrMonitoringPlan(
    choice: choice,
    specials: specials,
    specialsBefore: before,
    hasSpecials: hasSpecials,
  );

  test('a choice alone, with the specials left off', () {
    expect(plan('future'), ['future']);
    expect(plan('firstSeason'), ['firstSeason']);
  });

  test('a choice with the specials kept on goes back for them after', () {
    expect(plan('all', specials: true, before: true), [
      'all',
      'monitorSpecials',
    ]);
  });

  test('only the specials changed', () {
    expect(plan('keep', specials: true), ['monitorSpecials']);
    expect(plan('keep', before: true), ['unmonitorSpecials']);
    expect(plan('keep', specials: true, before: true), isEmpty);
  });

  test('None needs nothing for the specials', () {
    expect(plan('none', before: true), ['none']);
  });

  test('a show with no specials never sends them', () {
    expect(plan('all', specials: true, hasSpecials: false), ['all']);
  });

  test('Add remembers new seasons, the cutoff search and tags', () {
    const d = ArrAddDefaults(
      monitorNewSeasons: false,
      searchCutoff: true,
      tags: [3, 7],
    );
    final back = ArrAddDefaults.fromJson(d.toJson());
    expect(back, d);
    expect(back.tags, [3, 7]);
    expect(back.isEmpty, isFalse);
    expect(const ArrAddDefaults(tags: [1]) == const ArrAddDefaults(tags: [2]),
        isFalse);
  });

  test('older saved defaults without them still read', () {
    final d = ArrAddDefaults.fromJson({'monitor': 'all', 'search': true});
    expect(d.monitorNewSeasons, isNull);
    expect(d.tags, isNull);
  });
}
