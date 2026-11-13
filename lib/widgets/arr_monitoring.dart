import 'package:flutter/material.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../theme/app_theme.dart';
import 'app_spinner.dart';
import 'arr_actions.dart';

/// Which of a show's episodes Sonarr looks for: the show's own switch, a
/// choice that sets every episode at once (All, Future, Missing...), the
/// specials, and whether seasons announced later are monitored. True when
/// something changed.
Future<bool> showArrMonitoringDialog(
  BuildContext context, {
  required SonarrClient client,
  required ArrSeries series,
  required List<ArrEpisode>? episodes,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _MonitoringDialog(
      client: client,
      series: series,
      episodes: episodes,
    ),
  );
  return ok ?? false;
}

/// The episode choices for a show already in Sonarr, with what each does.
/// The specials have their own switch, so they aren't in this list.
Map<String, ({String label, String hint})> arrMonitoringChoices(
  AppLocalizations l, {
  required int monitored,
  required int total,
}) => {
  'keep': (label: l.arrMonitorKeep, hint: l.arrMonitorKeepHint(monitored, total)),
  'all': (label: l.arrMonitorAll, hint: l.arrMonitorAllHint),
  'future': (label: l.arrMonitorFuture, hint: l.arrMonitorFutureHint),
  'missing': (label: l.arrMonitorMissing, hint: l.arrMonitorMissingHint),
  'existing': (label: l.arrMonitorExisting, hint: l.arrMonitorExistingHint),
  'recent': (label: l.arrMonitorRecent, hint: l.arrMonitorRecentHint),
  'pilot': (label: l.arrMonitorPilot, hint: l.arrMonitorPilotHint),
  'firstSeason': (label: l.arrMonitorFirstSeason, hint: l.arrMonitorFirstSeasonHint),
  'lastSeason': (label: l.arrMonitorLastSeason, hint: l.arrMonitorLastSeasonHint),
  'none': (label: l.arrMonitorNone, hint: l.arrMonitorNoneHint),
};

/// The calls that carry out a Monitoring choice, in the order Sonarr needs
/// them. Every episode choice turns the specials off, so the specials go
/// after it; the choices leave the show's own switch alone (only None turns
/// it off), so it's sent with each. Checked against Sonarr 4.0.20.
@visibleForTesting
List<String> arrMonitoringPlan({
  required String choice,
  required bool specials,
  required bool specialsBefore,
  required bool hasSpecials,
}) => [
  if (choice != 'keep') choice,
  if (hasSpecials &&
      choice != 'none' &&
      (choice != 'keep' ? specials : specials != specialsBefore))
    specials ? 'monitorSpecials' : 'unmonitorSpecials',
];

class _MonitoringDialog extends StatefulWidget {
  final SonarrClient client;
  final ArrSeries series;
  final List<ArrEpisode>? episodes;
  const _MonitoringDialog({
    required this.client,
    required this.series,
    required this.episodes,
  });

  @override
  State<_MonitoringDialog> createState() => _MonitoringDialogState();
}

class _MonitoringDialogState extends State<_MonitoringDialog> {
  Map<String, dynamic>? _raw;
  String? _error;
  bool _busy = false;

  late bool _monitored = widget.series.monitored;
  String _choice = 'keep';
  late final bool _hasSpecials = widget.series.seasons.any(
    (s) => s.seasonNumber == 0,
  );
  late final bool _specialsBefore = widget.series.seasons.any(
    (s) => s.seasonNumber == 0 && s.monitored,
  );
  late bool _specials = _specialsBefore;
  bool _newSeasons = true;
  bool _newSeasonsBefore = true;
  // Something already reached Sonarr (a save that failed part-way), so the
  // show's page must refresh even if the dialog is then cancelled.
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await widget.client.seriesRaw(widget.series.id);
      if (!mounted) return;
      setState(() {
        _raw = raw;
        _monitored = raw['monitored'] == true;
        _newSeasons = _newSeasonsBefore = raw['monitorNewItems'] != 'none';
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _pick(String choice) => setState(() {
    _choice = choice;
    // Back to Keep undoes what the other choices switched along the way.
    if (choice == 'keep') {
      _monitored = _raw?['monitored'] == true;
      _specials = _specialsBefore;
      return;
    }
    // None stops the show being monitored; anything else is pointless with
    // the show switched off, so it switches it back on.
    if (choice == 'none') {
      _monitored = false;
      _specials = false;
    } else if (choice != 'keep') {
      _monitored = true;
      // Each choice turns the specials off unless asked to keep them.
      _specials = false;
    }
  });

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final c = widget.client;
    final id = widget.series.id;
    setState(() => _busy = true);
    final ok = await arrRun(context, () async {
      for (final m in arrMonitoringPlan(
        choice: _choice,
        specials: _specials,
        specialsBefore: _specialsBefore,
        hasSpecials: _hasSpecials,
      )) {
        await c.applyMonitoring(id, monitor: m, monitored: _monitored);
        _applied = true;
      }
      // The show's switch and new seasons: from a fresh copy, so the season
      // changes just made aren't written back over.
      final raw = await c.seriesRaw(id);
      final newItems = _newSeasons ? 'all' : 'none';
      if (raw['monitored'] != _monitored || raw['monitorNewItems'] != newItems) {
        raw['monitored'] = _monitored;
        raw['monitorNewItems'] = newItems;
        await c.updateSeries(raw);
      }
    }, done: l.arrSaved);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  bool get _changed =>
      _choice != 'keep' ||
      _specials != _specialsBefore ||
      _newSeasons != _newSeasonsBefore ||
      (_raw != null && _monitored != (_raw!['monitored'] == true));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final eps = widget.episodes ?? const <ArrEpisode>[];
    final regular = [for (final e in eps) if (e.seasonNumber > 0) e];
    final choices = arrMonitoringChoices(
      l,
      monitored: regular.where((e) => e.monitored).length,
      total: regular.length,
    );
    if (widget.episodes == null) choices.remove('keep');
    final enabled = !_busy && _raw != null;
    Widget body;
    if (_error != null) {
      body = Text(
        _error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    } else if (_raw == null) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: AppSpinner()),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.arrMonitorThisShow),
            subtitle: Text(l.arrMonitoredShowHint),
            value: _monitored,
            onChanged: enabled
                ? (v) {
                    if (v && _choice == 'none') {
                      _pick('keep');
                      setState(() => _monitored = true);
                    } else {
                      setState(() => _monitored = v);
                    }
                  }
                : null,
          ),
          const SizedBox(height: 12),
          ArrDropdownField<String>(
            label: l.arrMonitorEpisodes,
            value: choices.containsKey(_choice) ? _choice : null,
            options: {for (final e in choices.entries) e.key: e.value.label},
            helper: choices[_choice]?.hint,
            onChanged: enabled ? (v) => _pick(v ?? 'keep') : null,
          ),
          if (_hasSpecials)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.arrMonitorSpecials),
              subtitle: Text(l.arrMonitorSpecialsHint),
              value: _specials,
              onChanged: enabled && _choice != 'none'
                  ? (v) => setState(() => _specials = v)
                  : null,
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.arrMonitorNewSeasons),
            subtitle: Text(l.arrMonitorNewSeasonsHint),
            value: _newSeasons,
            onChanged: enabled ? (v) => setState(() => _newSeasons = v) : null,
          ),
        ],
      );
    }
    return ArrDialogFrame(
      client: widget.client,
      images: widget.series.images,
      heading: l.arrMonitoring,
      title: widget.series.title,
      body: body,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, _applied),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          style: kInlineButtonStyle,
          onPressed: enabled && _changed ? _save : null,
          child: _busy ? const AppSpinner.inline() : Text(l.commonSave),
        ),
      ],
    );
  }
}
