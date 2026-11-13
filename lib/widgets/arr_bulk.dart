import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../state/arr_providers.dart';
import '../theme/app_theme.dart';
import 'app_snack.dart';
import 'app_spinner.dart';
import 'arr_actions.dart';
import 'arr_monitoring.dart';
import 'arr_tags.dart';
import 'arr_widgets.dart';

/// The titles picked in the Movies or Shows tab, by id. Picking is a mode the
/// tab enters (long-press a poster, or Select), so an ordinary tap still
/// opens a title.
class ArrSelection extends ChangeNotifier {
  final _ids = <int>{};
  bool _active = false;

  bool get active => _active;
  Set<int> get ids => Set.unmodifiable(_ids);
  int get length => _ids.length;
  bool contains(int id) => _ids.contains(id);

  void start([int? first]) {
    _active = true;
    if (first != null) _ids.add(first);
    notifyListeners();
  }

  void stop() {
    _active = false;
    _ids.clear();
    notifyListeners();
  }

  void toggle(int id) {
    if (!_ids.remove(id)) _ids.add(id);
    notifyListeners();
  }

  void selectAll(Iterable<int> all) {
    _ids.addAll(all);
    notifyListeners();
  }

  /// Drops ids no longer on screen (a filter or search changed).
  void keepOnly(Set<int> shown) {
    if (_ids.difference(shown).isEmpty) return;
    _ids.retainAll(shown);
    notifyListeners();
  }
}

/// The bar above the grid while picking: how many, Select All, and what the
/// apps' select mode can do to them all at once.
class ArrBulkBar extends ConsumerStatefulWidget {
  final ArrClient client;
  final ArrSelection selection;

  /// Every title on screen, for Select All.
  final List<int> all;

  /// Total size on disk of each title, for the delete dialog.
  final Map<int, int> sizes;

  /// Refreshes the library after a change.
  final VoidCallback onChanged;

  const ArrBulkBar({
    super.key,
    required this.client,
    required this.selection,
    required this.all,
    required this.sizes,
    required this.onChanged,
  });

  @override
  ConsumerState<ArrBulkBar> createState() => _ArrBulkBarState();
}

class _ArrBulkBarState extends ConsumerState<ArrBulkBar> {
  bool _busy = false;

  bool get _shows => widget.client is SonarrClient;
  List<int> get _picked => widget.selection.ids.toList();

  String _count(AppLocalizations l, int n) =>
      _shows ? l.arrCountShows(n) : l.arrCountMovies(n);

  /// Runs one call for the picked titles and says how it went. Changes end
  /// the picking and refresh the library; a search or refresh doesn't
  /// change what's picked, so it stays.
  Future<void> _run(
    Future<void> Function(List<int> ids) call,
    String done, {
    bool changes = true,
  }) async {
    final ids = _picked;
    setState(() => _busy = true);
    final ok = await arrRun(context, () => call(ids), done: done);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok && changes) {
      widget.selection.stop();
      widget.onChanged();
    }
  }

  Future<void> _edit() async {
    final changes = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          _BulkEditDialog(client: widget.client, count: _picked.length),
    );
    if (changes == null || changes.isEmpty || !mounted) return;
    await _run(
      (ids) => widget.client.editMany(ids, changes),
      AppLocalizations.of(context).arrSaved,
    );
  }

  Future<void> _monitoring() async {
    final c = widget.client;
    if (c is! SonarrClient) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => _BulkMonitoringDialog(client: c, count: _picked.length),
    );
    if (choice == null || !mounted) return;
    await _run(
      (ids) => c.applyMonitoringMany(ids, choice),
      AppLocalizations.of(context).arrSaved,
    );
  }

  Future<void> _tags() async {
    final changes = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) =>
          _BulkTagsDialog(client: widget.client, count: _picked.length),
    );
    if (changes == null || !mounted) return;
    await _run(
      (ids) => widget.client.editMany(ids, changes),
      AppLocalizations.of(context).arrSaved,
    );
  }

  Future<void> _rename() async {
    final l = AppLocalizations.of(context);
    final c = widget.client;
    final app = c.kind.appName;
    final messenger = ScaffoldMessenger.of(context);
    // Same check as one title's Rename: with renaming off it does nothing.
    try {
      if (!await c.renamingOn()) {
        showSnackOn(messenger, l.arrRenamingOff(app));
        return;
      }
    } catch (e) {
      showSnackOn(messenger, e.toString(), kind: SnackKind.error);
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmFrame(
        client: c,
        heading: l.arrRenameFiles,
        title: _count(l, _picked.length),
        message: l.arrRenameSelectedMessage(app),
        confirm: l.arrRenameFiles,
      ),
    );
    if (ok != true || !mounted) return;
    await _run(
      (ids) => c.renameMany(ids),
      l.arrRenameStarted(app),
      changes: false,
    );
  }

  Future<void> _delete() async {
    final ids = _picked;
    final size = ids.fold<int>(0, (t, id) => t + (widget.sizes[id] ?? 0));
    final done = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _BulkDeleteDialog(client: widget.client, ids: ids, size: size),
    );
    if (done == true && mounted) {
      widget.selection.stop();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final sel = widget.selection;
    final app = widget.client.kind.appName;
    final enabled = !_busy && sel.length > 0;
    final actions = <({IconData icon, String label, VoidCallback? run, bool danger})>[
      (icon: Icons.edit_rounded, label: l.arrEdit, run: enabled ? _edit : null, danger: false),
      if (_shows)
        (
          icon: Icons.bookmark_rounded,
          label: l.arrMonitoring,
          run: enabled ? _monitoring : null,
          danger: false,
        ),
      (icon: Icons.sell_rounded, label: l.arrTags, run: enabled ? _tags : null, danger: false),
      (
        icon: Icons.search_rounded,
        label: _shows ? l.arrSearchMonitored : l.arrSearchMoviesBulk,
        run: enabled
            ? () => _run(
                widget.client.searchMany,
                l.arrSearchStarted(app),
                changes: false,
              )
            : null,
        danger: false,
      ),
      (
        icon: Icons.sync_rounded,
        label: l.arrRefreshScan,
        run: enabled
            ? () => _run(
                widget.client.refreshMany,
                l.arrRefreshStarted(app),
                changes: false,
              )
            : null,
        danger: false,
      ),
      (
        icon: Icons.drive_file_rename_outline_rounded,
        label: l.arrRenameFiles,
        run: enabled ? _rename : null,
        danger: false,
      ),
      (icon: Icons.delete_rounded, label: l.commonDelete, run: enabled ? _delete : null, danger: true),
    ];
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: LayoutBuilder(
        builder: (context, c) {
          // Seven buttons, the count and Select All need about 760 logical
          // pixels; narrower, the actions fold into one menu.
          final narrow = c.maxWidth < 780;
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Row(
              children: [
                IconButton(
                  tooltip: l.commonCancel,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _busy ? null : sel.stop,
                ),
                Flexible(
                  child: Text(
                    l.selectionCount(sel.length),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: AppSpinner.inline(),
                  ),
                if (narrow)
                  IconButton(
                    tooltip: l.selectionSelectAll,
                    icon: const Icon(Icons.select_all_rounded),
                    onPressed: _busy ? null : () => sel.selectAll(widget.all),
                  )
                else
                  TextButton(
                    onPressed: _busy ? null : () => sel.selectAll(widget.all),
                    child: Text(l.selectionSelectAll),
                  ),
                if (narrow)
                  PopupMenuButton<VoidCallback?>(
                    tooltip: l.commonMoreOptions,
                    enabled: enabled,
                    onSelected: (run) => run?.call(),
                    itemBuilder: (context) => [
                      for (final a in actions)
                        PopupMenuItem<VoidCallback?>(
                          value: a.run,
                          enabled: a.run != null,
                          child: Row(
                            children: [
                              Icon(
                                a.icon,
                                size: 20,
                                color: a.danger ? theme.colorScheme.error : null,
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(
                                  a.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: a.danger
                                      ? TextStyle(color: theme.colorScheme.error)
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  )
                else
                  for (final a in actions)
                    IconButton(
                      tooltip: a.label,
                      icon: Icon(a.icon),
                      color: a.danger ? theme.colorScheme.error : null,
                      onPressed: a.run,
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A plain confirm in the Arr dialog frame.
class _ConfirmFrame extends StatelessWidget {
  final ArrClient client;
  final String heading;
  final String title;
  final String message;
  final String confirm;
  const _ConfirmFrame({
    required this.client,
    required this.heading,
    required this.title,
    required this.message,
    required this.confirm,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ArrDialogFrame(
      client: client,
      images: const [],
      heading: heading,
      title: title,
      body: Text(message),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          style: kInlineButtonStyle,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- Edit

/// Edit for several titles: every field starts on No Change, and only the
/// ones changed are sent, as in the apps' own select mode.
class _BulkEditDialog extends ConsumerStatefulWidget {
  final ArrClient client;
  final int count;
  const _BulkEditDialog({required this.client, required this.count});

  @override
  ConsumerState<_BulkEditDialog> createState() => _BulkEditDialogState();
}

class _BulkEditDialogState extends ConsumerState<_BulkEditDialog> {
  static const _keep = '';
  String _monitored = _keep;
  String _profile = _keep;
  String _root = _keep;
  String _seriesType = _keep;
  String _seasonFolder = _keep;
  String _newSeasons = _keep;
  String _availability = _keep;

  bool get _shows => widget.client is SonarrClient;

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final changes = <String, dynamic>{
      if (_monitored != _keep) 'monitored': _monitored == 'yes',
      if (_profile != _keep) 'qualityProfileId': int.parse(_profile),
      if (_shows && _seriesType != _keep) 'seriesType': _seriesType,
      if (_shows && _seasonFolder != _keep) 'seasonFolder': _seasonFolder == 'yes',
      if (_shows && _newSeasons != _keep) 'monitorNewItems': _newSeasons,
      if (!_shows && _availability != _keep) 'minimumAvailability': _availability,
    };
    if (_root != _keep) {
      // As for one title: a new root folder asks whether to move the files.
      final move = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.arrMoveFilesTitle),
          content: Text(l.arrMoveFilesToRoot(_root)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.arrMoveFilesNo),
            ),
            FilledButton(
              style: kInlineButtonStyle,
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.arrMoveFilesYes),
            ),
          ],
        ),
      );
      if (move == null || !mounted) return;
      changes['rootFolderPath'] = _root;
      changes['moveFiles'] = move;
    }
    Navigator.pop(context, changes);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final kind = widget.client.kind;
    final profiles =
        ref.watch(arrQualityProfileListProvider(kind)).asData?.value ??
        const <ArrQualityProfile>[];
    final roots =
        ref.watch(arrRootFoldersProvider(kind)).asData?.value ??
        const <ArrRootFolder>[];
    Map<String, String> keep(Map<String, String> m) => {_keep: l.arrNoChange, ...m};
    final changed = [
      _monitored, _profile, _root, _seriesType, _seasonFolder, _newSeasons,
      _availability,
    ].any((v) => v != _keep);
    return ArrDialogFrame(
      client: widget.client,
      images: const [],
      heading: l.arrEdit,
      title: _shows ? l.arrCountShows(widget.count) : l.arrCountMovies(widget.count),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArrDropdownField<String>(
            label: l.arrMonitored,
            value: _monitored,
            options: keep({'yes': l.arrFilterMonitored, 'no': l.arrUnmonitored}),
            onChanged: (v) => setState(() => _monitored = v ?? _keep),
          ),
          ArrDropdownField<String>(
            label: l.arrQualityProfile,
            value: _profile,
            options: keep({for (final p in profiles) '${p.id}': p.name}),
            onChanged: (v) => setState(() => _profile = v ?? _keep),
          ),
          ArrDropdownField<String>(
            label: l.arrRootFolder,
            value: _root,
            options: keep({for (final r in roots) r.path: r.path}),
            onChanged: (v) => setState(() => _root = v ?? _keep),
          ),
          if (_shows) ...[
            ArrDropdownField<String>(
              label: l.arrSeriesType,
              value: _seriesType,
              options: keep(arrSeriesTypes(l)),
              onChanged: (v) => setState(() => _seriesType = v ?? _keep),
            ),
            ArrDropdownField<String>(
              label: l.arrSeasonFolders,
              value: _seasonFolder,
              options: keep({'yes': l.arrSeasonFoldersYes, 'no': l.arrSeasonFoldersNo}),
              onChanged: (v) => setState(() => _seasonFolder = v ?? _keep),
            ),
            ArrDropdownField<String>(
              label: l.arrMonitorNewSeasons,
              value: _newSeasons,
              options: keep({'all': l.arrYes, 'none': l.arrNo}),
              helper: l.arrMonitorNewSeasonsHint,
              onChanged: (v) => setState(() => _newSeasons = v ?? _keep),
            ),
          ] else
            ArrDropdownField<String>(
              label: l.arrMinimumAvailability,
              value: _availability,
              options: keep(arrAvailabilities(l)),
              onChanged: (v) => setState(() => _availability = v ?? _keep),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          style: kInlineButtonStyle,
          onPressed: changed ? _save : null,
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- Monitoring

/// Which episodes of several shows to monitor, in one go: Sonarr's Update
/// Monitoring. Returns the choice.
class _BulkMonitoringDialog extends StatefulWidget {
  final SonarrClient client;
  final int count;
  const _BulkMonitoringDialog({required this.client, required this.count});

  @override
  State<_BulkMonitoringDialog> createState() => _BulkMonitoringDialogState();
}

class _BulkMonitoringDialogState extends State<_BulkMonitoringDialog> {
  String? _choice;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final choices = {
      ...arrMonitoringChoices(l, monitored: 0, total: 0)..remove('keep'),
      'monitorSpecials': (
        label: l.arrMonitorSpecials,
        hint: l.arrMonitorSpecialsChoiceHint,
      ),
      'unmonitorSpecials': (
        label: l.arrUnmonitorSpecials,
        hint: l.arrUnmonitorSpecialsHint,
      ),
    };
    return ArrDialogFrame(
      client: widget.client,
      images: const [],
      heading: l.arrMonitoring,
      title: l.arrCountShows(widget.count),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              l.arrMonitorEpisodes,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: _choice,
            isExpanded: true,
            hint: Text(l.arrPickOne),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              helperText: choices[_choice]?.hint,
              helperMaxLines: 2,
            ),
            items: [
              for (final e in choices.entries)
                DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _choice = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          style: kInlineButtonStyle,
          onPressed: _choice == null
              ? null
              : () => Navigator.pop(context, _choice),
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- Tags

/// Tags for several titles: pick tags, then add them, remove them, or make
/// them each title's only tags.
class _BulkTagsDialog extends StatefulWidget {
  final ArrClient client;
  final int count;
  const _BulkTagsDialog({required this.client, required this.count});

  @override
  State<_BulkTagsDialog> createState() => _BulkTagsDialogState();
}

class _BulkTagsDialogState extends State<_BulkTagsDialog> {
  List<int> _tags = const [];
  String _apply = 'add';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final shows = widget.client is SonarrClient;
    final hint = switch (_apply) {
      'remove' => l.arrTagsRemoveHint,
      'replace' => l.arrTagsReplaceHint,
      _ => l.arrTagsAddHint,
    };
    // Replace with nothing picked clears every tag, which is a real choice;
    // adding or removing nothing does nothing.
    final ready = _tags.isNotEmpty || _apply == 'replace';
    return ArrDialogFrame(
      client: widget.client,
      images: const [],
      heading: l.arrTags,
      title: shows ? l.arrCountShows(widget.count) : l.arrCountMovies(widget.count),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArrTagPicker(
            client: widget.client,
            selected: _tags,
            onChanged: (ids) => setState(() => _tags = ids),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              l.arrTagsApply,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'add', label: Text(l.arrTagsAdd)),
              ButtonSegment(value: 'remove', label: Text(l.arrTagsRemove)),
              ButtonSegment(value: 'replace', label: Text(l.arrTagsReplace)),
            ],
            selected: {_apply},
            onSelectionChanged: (v) => setState(() => _apply = v.first),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          style: kInlineButtonStyle,
          onPressed: ready
              ? () => Navigator.pop(context, {'tags': _tags, 'applyTags': _apply})
              : null,
          // Replace with nothing picked takes every tag off: say so.
          child: Text(
            _apply == 'replace' && _tags.isEmpty ? l.arrClearTags : l.commonSave,
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ Delete

/// Deletes several titles, with the same choices as deleting one.
class _BulkDeleteDialog extends StatefulWidget {
  final ArrClient client;
  final List<int> ids;
  final int size;
  const _BulkDeleteDialog({
    required this.client,
    required this.ids,
    required this.size,
  });

  @override
  State<_BulkDeleteDialog> createState() => _BulkDeleteDialogState();
}

class _BulkDeleteDialogState extends State<_BulkDeleteDialog> {
  bool _files = false;
  bool _exclude = false;
  bool _busy = false;

  Future<void> _delete() async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    final ok = await arrRun(
      context,
      () => widget.client.deleteMany(
        widget.ids,
        deleteFiles: _files,
        addExclusion: _exclude,
      ),
      done: l.arrDeletedCount(widget.ids.length),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final app = widget.client.kind.appName;
    final n = widget.ids.length;
    final shows = widget.client is SonarrClient;
    return ArrDialogFrame(
      client: widget.client,
      images: const [],
      heading: l.commonDelete,
      title: shows ? l.arrCountShows(n) : l.arrCountMovies(n),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.arrDeleteSelectedMessage(n, app)),
          const SizedBox(height: 8),
          ArrCheck(
            label: l.arrDeleteFiles,
            hint: widget.size > 0
                ? (n == 1
                      ? l.arrDeleteFilesHint(arrSize(widget.size))
                      : l.arrDeleteFilesManyHint(arrSize(widget.size)))
                : null,
            value: _files,
            onChanged: _busy ? null : (v) => setState(() => _files = v),
          ),
          ArrCheck(
            label: l.arrPreventReadding,
            hint: n == 1 ? l.arrPreventReaddingHint : l.arrPreventReaddingManyHint,
            value: _exclude,
            onChanged: _busy ? null : (v) => setState(() => _exclude = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          style: kInlineButtonStyle.merge(
            FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
          ),
          onPressed: _busy ? null : _delete,
          child: _busy ? const AppSpinner.inline() : Text(l.commonDelete),
        ),
      ],
    );
  }
}
