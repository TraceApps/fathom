import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../state/arr_providers.dart';
import '../state/preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/app_snack.dart';
import '../widgets/app_spinner.dart';
import '../widgets/arr_file_edit.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';

/// Where Manual Import looks: a finished download from the queue, or a
/// folder on the app's server.
class ArrImportTarget {
  final ArrKind kind;
  final String? downloadId;
  final String? folder;

  /// The download's name, shown under the page title.
  final String? title;

  const ArrImportTarget.download(this.kind, String id, {this.title})
    : downloadId = id,
      folder = null;
  const ArrImportTarget.folder(this.kind, String path)
    : folder = path,
      downloadId = null,
      title = null;

  bool get isDownload => downloadId != null;

  String get location => Uri(
    path: '/arr/import',
    queryParameters: {
      'app': kind.name,
      'download': ?downloadId,
      'folder': ?folder,
      'title': ?title,
    },
  ).toString();

  static ArrImportTarget? fromQuery(Map<String, String> q) {
    final kind = q['app'] == 'radarr' ? ArrKind.radarr : ArrKind.sonarr;
    if (q['download'] case final d? when d.isNotEmpty) {
      return ArrImportTarget.download(kind, d, title: q['title']);
    }
    if (q['folder'] case final f? when f.isNotEmpty) {
      return ArrImportTarget.folder(kind, f);
    }
    return null;
  }
}

/// Manual Import, as on the apps' own pages: the files the app found, what it
/// thinks each one is, and why it wouldn't import them by itself. Fix what's
/// wrong (the show and episodes, the movie, quality, languages), tick the
/// files to bring in, and Import. Pops with true once the import started.
class ArrImportScreen extends ConsumerStatefulWidget {
  final ArrImportTarget? target;
  const ArrImportScreen({super.key, required this.target});

  @override
  ConsumerState<ArrImportScreen> createState() => _ArrImportScreenState();
}

class _ArrImportScreenState extends ConsumerState<ArrImportScreen> {
  List<ArrImportItem>? _items;
  Object? _error;
  final Set<int> _picked = {};
  final Set<int> _checking = {};
  bool _importing = false;
  String? _mode; // folders: move or copy

  ArrImportTarget get _t => widget.target!;
  ArrClient? get _client => arrClient(ref, _t.kind);

  @override
  void initState() {
    super.initState();
    _mode = arrImportMode(
      ref.read(preferencesProvider).asData?.value ?? const Prefs(),
    );
    if (widget.target != null) _load();
  }

  Future<void> _load() async {
    final c = _client;
    if (c == null) return;
    setState(() {
      _items = null;
      _error = null;
    });
    try {
      final items = await c.importFiles(
        downloadId: _t.downloadId,
        folder: _t.folder,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        // Files the app fully worked out start ticked, as on its own page,
        // except ones it flagged (not an upgrade, a sample...): those wait
        // for a deliberate tick, so one tap can't replace a better file.
        _picked
          ..clear()
          ..addAll([
            for (final i in items)
              if (i.gap == null && i.rejections.isEmpty && i.size > 0) i.id,
          ]);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _replace(Iterable<ArrImportItem> changed) {
    final byId = {for (final i in changed) i.id: i};
    _items = [for (final i in _items!) byId[i.id] ?? i];
  }

  /// Has the app look at [items] again: the episodes for a new show or
  /// season, and its verdict on each.
  Future<void> _recheck(List<ArrImportItem> all) async {
    final c = _client;
    // The apps can only check a file once it has a show or movie.
    final items = [
      for (final i in all)
        if ((i.kind == ArrKind.sonarr ? i.seriesId : i.movieId) != null) i,
    ];
    if (c == null || items.isEmpty) return;
    final ids = {for (final i in items) i.id};
    setState(() => _checking.addAll(ids));
    try {
      final back = {for (final r in await c.recheckImport(items)) r.id: r};
      if (!mounted) return;
      setState(() {
        _replace([
          for (final i in _items!)
            if (back[i.id] case final r?) i.mergeReprocessed(r),
        ]);
      });
    } catch (e) {
      if (mounted) {
        showSnack(context, e.toString(), kind: SnackKind.error);
      }
    } finally {
      if (mounted) setState(() => _checking.removeAll(ids));
    }
  }

  Future<void> _edit(ArrImportItem item) async {
    final changes = await showArrFileEditDialog(
      context,
      kind: _t.kind,
      subtitle: item.fileName,
      titleChoice: true,
      episodeChoice: _t.kind == ArrKind.sonarr,
      seriesId: item.seriesId,
      movieId: item.movieId,
      seasonNumber: item.seasonNumber,
      episodeIds: [for (final e in item.episodes) e.id],
      qualityId: arrQualityId(item.quality),
      languages: item.languages,
      releaseGroup: item.releaseGroup,
    );
    if (changes == null || changes.isEmpty || !mounted) return;
    final next = changes.applyTo(item);
    setState(() {
      _replace([next]);
      // Changing a file means bringing it in, as on the apps' pages.
      _picked.add(item.id);
    });
    await _recheck([next]);
  }

  Future<void> _editPicked(List<ArrImportItem> picked) async {
    // One show for all of them: the season can change too.
    final shows = {for (final i in picked) i.seriesId};
    final changes = await showArrFileEditDialog(
      context,
      kind: _t.kind,
      subtitle: '',
      count: picked.length,
      titleChoice: true,
      episodeChoice: _t.kind == ArrKind.sonarr,
      seriesId: shows.length == 1 ? shows.first : null,
    );
    if (changes == null || changes.isEmpty || !mounted) return;
    final next = [for (final i in picked) changes.applyTo(i)];
    setState(() => _replace(next));
    await _recheck(next);
  }

  Future<void> _import(List<ArrImportItem> picked) async {
    final l = AppLocalizations.of(context);
    final c = _client;
    final mode = _t.isDownload ? 'auto' : _mode;
    if (c == null || mode == null || _importing) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _importing = true);
    try {
      await c.manualImport(picked, mode);
      if (!_t.isDownload) {
        // A convenience: failing to note the folder isn't a failed import.
        rememberArrImportFolder(ref, _t.kind, _t.folder!).ignore();
      }
      showSnackOn(
        messenger,
        l.arrImportStarted(picked.length, _t.kind.appName),
        kind: SnackKind.success,
      );
      ref.invalidate(arrQueueProvider);
      if (mounted) context.pop(true);
    } catch (e) {
      showSnackOn(messenger, e.toString(), kind: SnackKind.error);
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (widget.target == null || _client == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.arrManualImport)),
        body: EmptyState(
          icon: Icons.link_off_rounded,
          title: l.arrNotConnected,
        ),
      );
    }
    final items = _items;
    final picked = [
      for (final i in items ?? const <ArrImportItem>[])
        if (_picked.contains(i.id)) i,
    ];
    final unready = picked.where((i) => i.gap != null).length;
    final all = items != null && items.isNotEmpty && picked.length == items.length;
    final app = _t.kind.appName;

    Widget body;
    if (_error != null) {
      body = ErrorView(message: _error.toString(), onRetry: _load);
    } else if (items == null) {
      body = const Center(child: AppSpinner());
    } else if (items.isEmpty) {
      body = EmptyState(
        icon: Icons.folder_off_rounded,
        title: l.arrImportNothing,
        message: _t.isDownload
            ? l.arrImportNothingDownload(app)
            : l.arrImportNothingFolder,
      );
    } else {
      final flagged = items.any((i) => i.rejections.isNotEmpty);
      body = ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          if (!_t.isDownload)
            _ModeChoice(
              mode: _mode,
              onChanged: (m) {
                setState(() => _mode = m);
                saveArrImportMode(ref, m);
              },
            ),
          if (flagged)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
              child: Text(
                l.arrImportFlaggedHint(app),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ImportCard(
                item: i,
                picked: _picked.contains(i.id),
                checking: _checking.contains(i.id),
                onPick: () => setState(() {
                  if (!_picked.remove(i.id)) _picked.add(i.id);
                }),
                // Not while the app checks it: its answer would land on
                // a newer edit.
                onEdit: _importing || _checking.contains(i.id)
                    ? null
                    : () => _edit(i),
              ),
            ),
        ],
      );
    }

    final canImport =
        picked.isNotEmpty &&
        unready == 0 &&
        _checking.isEmpty &&
        !_importing &&
        (_t.isDownload || _mode != null);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.arrManualImport),
            Text(
              _t.title ?? _t.folder ?? app,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (items != null && items.length > 1)
            TextButton(
              onPressed: () => setState(() {
                if (all) {
                  _picked.clear();
                } else {
                  _picked.addAll(items.map((i) => i.id));
                }
              }),
              child: Text(all ? l.arrSelectNoFiles : l.arrSelectAllFiles),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
      bottomNavigationBar: picked.isEmpty
          ? null
          : SafeArea(
              child: Material(
                color: theme.colorScheme.surfaceContainerHigh,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.arrFilesSelected(
                                picked.length,
                                arrSize(picked.fold<int>(0, (t, i) => t + i.size)),
                              ),
                              style: theme.textTheme.titleSmall,
                            ),
                            if (unready > 0)
                              Text(
                                l.arrImportNeedsChoice(unready),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: arrWarningColor,
                                ),
                              )
                            else if (!_t.isDownload && _mode == null)
                              Text(
                                l.arrImportChooseMode,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: arrWarningColor,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (picked.length > 1) ...[
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                          ),
                          onPressed: _importing || _checking.isNotEmpty
                              ? null
                              : () => _editPicked(picked),
                          child: Text(l.arrEdit),
                        ),
                        const SizedBox(width: 8),
                      ],
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        icon: _importing
                            ? const AppSpinner.inline()
                            : const Icon(Icons.download_done_rounded),
                        label: Text(l.arrImport),
                        onPressed: canImport ? () => _import(picked) : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// Move or Copy, for files imported from a folder. Nothing is picked until
/// the person chooses (then it's remembered), as the apps ask every time.
class _ModeChoice extends StatelessWidget {
  final String? mode;
  final ValueChanged<String> onChanged;
  const _ModeChoice({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: 'move',
                icon: const Icon(Icons.drive_file_move_rounded),
                label: Text(l.arrMoveFilesMode),
              ),
              ButtonSegment(
                value: 'copy',
                icon: const Icon(Icons.file_copy_rounded),
                label: Text(l.arrCopyFilesMode),
              ),
            ],
            selected: {?mode},
            onSelectionChanged: (s) {
              if (s.isNotEmpty) onChanged(s.first);
            },
          ),
          const SizedBox(height: 6),
          Text(
            switch (mode) {
              'move' => l.arrMoveFilesModeHint,
              'copy' => l.arrCopyFilesModeHint,
              _ => l.arrImportChooseMode,
            },
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One file: ticked or not, what the app thinks it is (or what's missing),
/// its quality, languages and release group, and the app's reasons.
class _ImportCard extends StatelessWidget {
  final ArrImportItem item;
  final bool picked;
  final bool checking;
  final VoidCallback onPick;
  final VoidCallback? onEdit;
  const _ImportCard({
    required this.item,
    required this.picked,
    required this.checking,
    required this.onPick,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gap = item.gap;
    final shows = item.kind == ArrKind.sonarr;

    // "Breaking Bad · S02E03 · Bit by a Dead Bee", or "Interstellar (2014)".
    final known = shows
        ? [
            ?item.seriesTitle,
            ?item.episodeCode,
            if (item.episodes.length == 1 &&
                (item.episodes.first.title?.isNotEmpty ?? false))
              item.episodes.first.title!,
          ].join(' · ')
        : [
            ?item.movieTitle,
            if (item.movieYear != null && item.movieYear! > 0)
              '(${item.movieYear})',
          ].join(' ');
    final missing = switch (gap) {
      ArrImportGap.title => shows ? l.arrChooseShow : l.arrChooseMovie,
      ArrImportGap.season || ArrImportGap.episodes => l.arrChooseEpisodes,
      ArrImportGap.quality => l.arrChooseQuality,
      ArrImportGap.languages => l.arrChooseLanguages,
      null => null,
    };
    final facts = [
      ?item.qualityName,
      if (item.languages.isNotEmpty)
        item.languages.map((x) => x.name).join(', '),
      ?item.releaseGroup,
      if (item.size > 0) arrSize(item.size),
    ].join(' · ');

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: picked, onChanged: (_) => onPick()),
              const SizedBox(width: 2),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (known.isNotEmpty)
                        Text(
                          known,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      Text(
                        item.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: (known.isEmpty
                                ? theme.textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  )
                                : theme.textTheme.bodySmall)
                            ?.copyWith(
                              color: known.isEmpty
                                  ? null
                                  : scheme.onSurfaceVariant,
                            ),
                      ),
                      if (facts.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            facts,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (checking)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: AppSpinner.inline(),
                        )
                      else ...[
                        if (missing != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: ArrChip(
                              label: missing,
                              color: arrWarningColor,
                              icon: Icons.edit_rounded,
                            ),
                          ),
                        for (final r in item.rejections)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 1, right: 6),
                                  child: Icon(
                                    Icons.info_outline_rounded,
                                    size: 15,
                                    color: arrWarningColor,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    r,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: arrWarningColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: l.arrEditFile,
                icon: const Icon(Icons.edit_rounded),
                onPressed: onEdit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens Manual Import for a finished download; true once it imported.
Future<bool> arrOpenDownloadImport(
  BuildContext context,
  ArrQueueItem item,
) async =>
    await context.push<bool>(
      ArrImportTarget.download(
        item.kind,
        item.downloadId!,
        title: item.title,
      ).location,
    ) ==
    true;

/// Asks which folder on the server to import from (and, with both apps,
/// which app), then opens Manual Import there.
Future<void> arrOpenFolderImport(
  BuildContext context, {
  ArrKind? kind,
  String? folder,
}) async {
  final picked = await showDialog<(ArrKind, String)>(
    context: context,
    builder: (_) => _FolderDialog(kind: kind, folder: folder),
  );
  if (picked == null || !context.mounted) return;
  context.push(ArrImportTarget.folder(picked.$1, picked.$2).location);
}

/// Browses the app's server for a folder, starting from the last ones used.
class _FolderDialog extends ConsumerStatefulWidget {
  final ArrKind? kind;
  final String? folder;
  const _FolderDialog({this.kind, this.folder});

  @override
  ConsumerState<_FolderDialog> createState() => _FolderDialogState();
}

class _FolderDialogState extends ConsumerState<_FolderDialog> {
  late ArrKind _kind;
  late final _path = TextEditingController(text: widget.folder ?? '');
  ArrFolderListing? _listing;
  Object? _error;
  bool _loading = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _kind =
        widget.kind ??
        (ref.read(sonarrClientProvider) != null
            ? ArrKind.sonarr
            : ArrKind.radarr);
    _browse(widget.folder ?? '');
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _browse(String path) async {
    final c = arrClient(ref, _kind);
    if (c == null) return;
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await c.folders(path);
      if (!mounted || seq != _seq) return;
      setState(() {
        _listing = listing;
        _loading = false;
        if (path.isNotEmpty) _path.text = path;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final both =
        ref.watch(sonarrClientProvider) != null &&
        ref.watch(radarrClientProvider) != null;
    final recent = arrImportRecent(
      ref.watch(preferencesProvider).asData?.value ?? const Prefs(),
      _kind,
    );
    final listing = _listing;
    final path = _path.text.trim();
    return AlertDialog(
      title: Text(l.arrManualImport),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      content: SizedBox(
        width: 480,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (both && widget.kind == null) ...[
              SegmentedButton<ArrKind>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ArrKind.sonarr, label: Text('Sonarr')),
                  ButtonSegment(value: ArrKind.radarr, label: Text('Radarr')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) {
                  setState(() {
                    _kind = s.first;
                    _path.clear();
                    _listing = null;
                  });
                  _browse('');
                },
              ),
              const SizedBox(height: 12),
            ],
            Text(
              l.arrImportFolderHint(_kind.appName),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _path,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                isDense: true,
                hintText: l.arrImportFolderPath,
                suffixIcon: IconButton(
                  tooltip: l.arrImportFolderGo,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: () => _browse(_path.text.trim()),
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (v) => _browse(v.trim()),
            ),
            const SizedBox(height: 8),
            if (recent.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in recent)
                    ActionChip(
                      avatar: const Icon(Icons.history_rounded, size: 16),
                      label: Text(
                        f,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () => _browse(f),
                    ),
                ],
              ),
            const SizedBox(height: 4),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Text(
                        _error.toString(),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : listing == null
                  ? const Center(child: AppSpinner(size: 24))
                  : Stack(
                      children: [
                        ListView(
                          children: [
                            if (listing.parent != null)
                              ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.drive_folder_upload_rounded,
                                ),
                                title: const Text('..'),
                                onTap: () => _browse(listing.parent!),
                              ),
                            for (final f in listing.folders)
                              ListTile(
                                dense: true,
                                leading: const Icon(Icons.folder_rounded),
                                title: Text(f.name),
                                onTap: () => _browse(f.path),
                              ),
                          ],
                        ),
                        if (_loading)
                          const Positioned(
                            top: 8,
                            right: 8,
                            child: AppSpinner.inline(),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          style: kInlineButtonStyle,
          onPressed: path.isEmpty
              ? null
              : () => Navigator.pop(context, (_kind, path)),
          child: Text(l.arrImportFolderOpen),
        ),
      ],
    );
  }
}
