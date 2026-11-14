import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../state/arr_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/app_spinner.dart';
import '../widgets/arr_actions.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import 'arr_add_screen.dart' show arrMonitorOptions, arrMovieMonitorOptions;

/// One folder on disk the app doesn't manage, and what it was matched to.
class _Folder {
  final ArrFolder folder;
  final String root;
  bool searching = true;
  Object? error;
  ArrLookup<Object>? match;

  _Folder(this.folder, this.root);

  String get path => folder.path;

  /// The title's id on its database (tvdb or tmdb), to spot two folders of
  /// the same title.
  int? get titleKey => switch (match?.item) {
    final ArrSeries s => s.tvdbId,
    final ArrMovie m => m.tmdbId,
    _ => null,
  };
}

/// Import Library, as in the apps: every folder in the root folders that
/// the app doesn't manage yet, each matched to a show or movie by its name.
/// Check the matches, choose how they're added, and add them all at once,
/// with the files already in them.
class ArrLibraryImportScreen extends ConsumerStatefulWidget {
  final ArrKind kind;
  const ArrLibraryImportScreen({super.key, required this.kind});

  @override
  ConsumerState<ArrLibraryImportScreen> createState() =>
      _ArrLibraryImportScreenState();
}

class _ArrLibraryImportScreenState
    extends ConsumerState<ArrLibraryImportScreen> {
  List<_Folder>? _folders;
  final Set<String> _picked = {};
  bool _importing = false;
  bool _started = false;

  // How they're added; starts on Add's own starting choices.
  int? _profile;
  String _monitor = 'all';
  String _seriesType = 'standard';
  bool _seasonFolder = true;
  String _availability = 'released';
  bool _search = false;

  bool get _shows => widget.kind == ArrKind.sonarr;
  ArrClient? get _client => arrClient(ref, widget.kind);

  void _start(ArrAddSetup setup) {
    _started = true;
    final c = setup.choice;
    _profile = c.qualityProfileId;
    _monitor = (_shows ? arrMonitorOptions : arrMovieMonitorOptions)(
              AppLocalizations.of(context),
            ).containsKey(c.monitor)
        ? c.monitor
        : (_shows ? 'all' : 'movieOnly');
    _seriesType = c.seriesType;
    _seasonFolder = c.seasonFolder;
    _availability = c.minimumAvailability;
    _folders = [
      for (final r in setup.roots)
        for (final f in r.unmappedFolders) _Folder(f, r.path),
    ]..sort(
        (a, b) => a.folder.name.toLowerCase().compareTo(
          b.folder.name.toLowerCase(),
        ),
      );
    _lookUpAll();
  }

  /// Looks each folder up by its name, two at a time, as the apps do.
  Future<void> _lookUpAll() async {
    final queue = [...?_folders];
    Future<void> worker() async {
      while (queue.isNotEmpty && mounted) {
        await _lookUp(queue.removeAt(0));
      }
    }

    await Future.wait([worker(), worker()]);
  }

  Future<void> _lookUp(_Folder f, [String? term]) async {
    final c = _client;
    if (c == null) return;
    setState(() {
      f.searching = true;
      f.error = null;
    });
    try {
      final results = await _results(c, term ?? f.folder.name);
      if (!mounted) return;
      setState(() {
        f.match = results.firstOrNull;
        f.searching = false;
        _autoPick(f);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        f.error = e;
        f.searching = false;
      });
    }
  }

  static Future<List<ArrLookup<Object>>> _results(
    ArrClient c,
    String term,
  ) async => switch (c) {
    final SonarrClient s => [
      for (final x in await s.lookup(term)) ArrLookup<Object>(x.item, x.raw),
    ],
    final RadarrClient r => [
      for (final x in await r.lookup(term)) ArrLookup<Object>(x.item, x.raw),
    ],
    _ => const [],
  };

  /// Ready ones start ticked, except a second folder of a title another
  /// ticked folder already has.
  void _autoPick(_Folder f) {
    if (_state(f) != _Ready.ready) return;
    final taken = _folders!.any(
      (o) => o != f && _picked.contains(o.path) && o.titleKey == f.titleKey,
    );
    if (!taken) _picked.add(f.path);
  }

  _Ready _state(_Folder f) {
    if (f.searching) return _Ready.searching;
    if (f.error != null) return _Ready.failed;
    if (f.match == null) return _Ready.noMatch;
    if (f.match!.inLibrary) return _Ready.inLibrary;
    return _Ready.ready;
  }

  void _toggle(_Folder f) => setState(() {
    if (_picked.remove(f.path)) return;
    // One folder per title: ticking this one unticks the other.
    _picked
      ..removeWhere(
        (p) => _folders!.any(
          (o) => o.path == p && o.titleKey != null && o.titleKey == f.titleKey,
        ),
      )
      ..add(f.path);
  });

  Future<void> _change(_Folder f) async {
    final c = _client;
    if (c == null) return;
    final picked = await showDialog<ArrLookup<Object>>(
      context: context,
      builder: (_) => _MatchDialog(client: c, folder: f.folder),
    );
    if (picked == null || !mounted) return;
    setState(() {
      f.match = picked;
      f.error = null;
      f.searching = false;
      _picked.remove(f.path);
      if (_state(f) == _Ready.ready) _toggle(f);
    });
  }

  Future<void> _import(List<_Folder> picked) async {
    final c = _client;
    final profile = _profile;
    if (c == null || profile == null || _importing) return;
    final l = AppLocalizations.of(context);
    setState(() => _importing = true);
    final items = [
      for (final f in picked)
        (lookupRaw: f.match!.raw, path: f.path, root: f.root),
    ];
    final ok = await arrRun(context, () async {
      if (c is SonarrClient) {
        await c.importSeries(
          items,
          qualityProfileId: profile,
          monitor: _monitor,
          seriesType: _seriesType,
          seasonFolder: _seasonFolder,
          search: _search,
        );
      } else if (c is RadarrClient) {
        await c.importMovies(
          items,
          qualityProfileId: profile,
          monitor: _monitor,
          minimumAvailability: _availability,
          search: _search,
        );
      }
    }, done: l.arrLibraryImported(picked.length, c.kind.appName));
    if (!mounted) return;
    setState(() {
      _importing = false;
      if (ok) {
        final gone = {for (final f in picked) f.path};
        _folders!.removeWhere((f) => gone.contains(f.path));
        _picked.removeAll(gone);
      }
    });
    if (ok) {
      ref.invalidate(
        _shows ? sonarrSeriesListProvider : radarrMoviesProvider,
      );
      ref.invalidate(arrRootFoldersProvider(widget.kind));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final app = widget.kind.appName;
    final setupAsync = ref.watch(arrAddSetupProvider(widget.kind));
    final setup = setupAsync.asData?.value;
    if (setup != null && !_started) {
      // After this frame: starting the lookups calls setState.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_started) setState(() => _start(setup));
      });
    }
    final folders = _folders;
    final picked = [
      for (final f in folders ?? const <_Folder>[])
        if (_picked.contains(f.path) && _state(f) == _Ready.ready) f,
    ];

    Widget body;
    if (setupAsync.hasError && setup == null) {
      body = ErrorView(
        message: setupAsync.error.toString(),
        onRetry: () => ref.invalidate(arrAddSetupProvider(widget.kind)),
      );
    } else if (folders == null) {
      body = const Center(child: AppSpinner());
    } else if (folders.isEmpty) {
      body = EmptyState(
        icon: Icons.library_add_check_rounded,
        title: l.arrLibraryImportNothing,
        message: l.arrLibraryImportNothingHint(app),
      );
    } else {
      final searching = folders.where((f) => f.searching).length;
      body = ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              l.arrLibraryImportHint(app),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          _Settings(
            shows: _shows,
            profiles: setup?.profiles ?? const [],
            profile: _profile,
            monitor: _monitor,
            seriesType: _seriesType,
            seasonFolder: _seasonFolder,
            availability: _availability,
            search: _search,
            onProfile: (v) => setState(() => _profile = v),
            onMonitor: (v) => setState(() => _monitor = v),
            onSeriesType: (v) => setState(() => _seriesType = v),
            onSeasonFolder: (v) => setState(() => _seasonFolder = v),
            onAvailability: (v) => setState(() => _availability = v),
            onSearch: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            child: Text(
              searching > 0
                  ? l.arrLibraryImportMatching(searching)
                  : l.arrFolderCount(folders.length),
              style: arrSectionStyle(theme),
            ),
          ),
          for (final f in folders)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FolderCard(
                client: _client,
                folder: f,
                state: _state(f),
                picked: _picked.contains(f.path),
                duplicate:
                    _state(f) == _Ready.ready &&
                    !_picked.contains(f.path) &&
                    folders.any(
                      (o) =>
                          o != f &&
                          _picked.contains(o.path) &&
                          o.titleKey == f.titleKey,
                    ),
                onPick: _importing ? null : () => _toggle(f),
                onChange: _importing || f.searching ? null : () => _change(f),
                onRetry: () => _lookUp(f),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.arrLibraryImport),
            Text(app, style: theme.textTheme.bodySmall),
          ],
        ),
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
                        child: Text(
                          _shows
                              ? l.arrCountShows(picked.length)
                              : l.arrCountMovies(picked.length),
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        icon: _importing
                            ? const AppSpinner.inline()
                            : const Icon(Icons.library_add_rounded),
                        label: Text(l.arrImport),
                        onPressed: _importing || _profile == null
                            ? null
                            : () => _import(picked),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

enum _Ready { searching, failed, noMatch, inLibrary, ready }

/// How the picked folders are added: the same choices as Add.
class _Settings extends StatelessWidget {
  final bool shows;
  final List<ArrQualityProfile> profiles;
  final int? profile;
  final String monitor;
  final String seriesType;
  final bool seasonFolder;
  final String availability;
  final bool search;
  final ValueChanged<int?> onProfile;
  final ValueChanged<String> onMonitor;
  final ValueChanged<String> onSeriesType;
  final ValueChanged<bool> onSeasonFolder;
  final ValueChanged<String> onAvailability;
  final ValueChanged<bool> onSearch;

  const _Settings({
    required this.shows,
    required this.profiles,
    required this.profile,
    required this.monitor,
    required this.seriesType,
    required this.seasonFolder,
    required this.availability,
    required this.search,
    required this.onProfile,
    required this.onMonitor,
    required this.onSeriesType,
    required this.onSeasonFolder,
    required this.onAvailability,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final monitors = shows ? arrMonitorOptions(l) : arrMovieMonitorOptions(l);
    // Folded to one line, so the folders stay in view on a phone.
    final summary = [
      ?profiles.where((p) => p.id == profile).firstOrNull?.name,
      ?monitors[monitor],
      if (shows) ?arrSeriesTypes(l)[seriesType] else
        ?arrAvailabilities(l)[availability],
      if (search) shows
          ? l.arrLibraryImportSearchShows
          : l.arrLibraryImportSearchMovies,
    ].join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(l.arrLibraryImportAddWith, style: theme.textTheme.titleSmall),
        subtitle: Text(
          summary,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        children: [
          LayoutBuilder(
          builder: (context, c) {
            // Two columns where there's room, one on a phone.
            final w = c.maxWidth >= 640 ? (c.maxWidth - 16) / 2 : c.maxWidth;
            Widget box(Widget child) => SizedBox(width: w, child: child);
            return Wrap(
              spacing: 16,
              children: [
                box(
                  ArrDropdownField<int>(
                    label: l.arrQualityProfile,
                    value: profile,
                    options: {for (final p in profiles) p.id: p.name},
                    onChanged: (v) => onProfile(v),
                  ),
                ),
                box(
                  ArrDropdownField<String>(
                    label: l.arrMonitor,
                    value: monitor,
                    options: shows
                        ? arrMonitorOptions(l)
                        : arrMovieMonitorOptions(l),
                    onChanged: (v) => onMonitor(v ?? monitor),
                  ),
                ),
                if (shows) ...[
                  box(
                    ArrDropdownField<String>(
                      label: l.arrSeriesType,
                      value: seriesType,
                      options: arrSeriesTypes(l),
                      onChanged: (v) => onSeriesType(v ?? seriesType),
                    ),
                  ),
                  box(
                    ArrDropdownField<bool>(
                      label: l.arrSeasonFolders,
                      value: seasonFolder,
                      options: {
                        true: l.arrSeasonFoldersYes,
                        false: l.arrSeasonFoldersNo,
                      },
                      onChanged: (v) => onSeasonFolder(v ?? seasonFolder),
                    ),
                  ),
                ] else
                  box(
                    ArrDropdownField<String>(
                      label: l.arrMinimumAvailability,
                      value: availability,
                      options: arrAvailabilities(l),
                      onChanged: (v) => onAvailability(v ?? availability),
                    ),
                  ),
                box(
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ArrCheck(
                      label: shows
                          ? l.arrLibraryImportSearchShows
                          : l.arrLibraryImportSearchMovies,
                      value: search,
                      onChanged: onSearch,
                    ),
                  ),
                ),
              ],
            );
          },
          ),
        ],
      ),
    );
  }
}

/// One folder: what it was matched to, or why it can't be added.
class _FolderCard extends StatelessWidget {
  final ArrClient? client;
  final _Folder folder;
  final _Ready state;
  final bool picked;
  final bool duplicate;
  final VoidCallback? onPick;
  final VoidCallback? onChange;
  final VoidCallback onRetry;

  const _FolderCard({
    required this.client,
    required this.folder,
    required this.state,
    required this.picked,
    required this.duplicate,
    required this.onPick,
    required this.onChange,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shows = client?.kind == ArrKind.sonarr;
    final (String? title, int? year, List<ArrImage> images) =
        switch (folder.match?.item) {
          final ArrSeries s => (s.title, s.year, s.images),
          final ArrMovie m => (m.title, m.year, m.images),
          _ => (null, null, const <ArrImage>[]),
        };
    final app = client?.kind.appName ?? '';
    final (String? note, Color noteColor) = switch (state) {
      _Ready.noMatch => (l.arrLibraryImportNoMatch, arrWarningColor),
      _Ready.failed => (folder.error.toString(), arrMissingColor),
      _Ready.inLibrary => (l.arrAlreadyInApp(app), scheme.onSurfaceVariant),
      _Ready.ready when duplicate => (
        l.arrLibraryImportDuplicate,
        scheme.onSurfaceVariant,
      ),
      _ => (null, scheme.onSurfaceVariant),
    };
    final ready = state == _Ready.ready;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: ready ? onPick : onChange,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: ready && picked,
                onChanged: ready && onPick != null ? (_) => onPick!() : null,
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 46,
                  height: 69,
                  child: ArrArt(
                    client: client,
                    images: images,
                    width: 185,
                    placeholderIcon: shows
                        ? Icons.live_tv_rounded
                        : Icons.movie_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state == _Ready.searching)
                      Row(
                        children: [
                          const AppSpinner.inline(),
                          const SizedBox(width: 8),
                          Text(l.arrLibraryImportLooking),
                        ],
                      )
                    else if (title != null)
                      Text(
                        [title, if (year != null && year > 0) '($year)']
                            .join(' '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.folder_rounded,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            folder.folder.path,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (note != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          note,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: noteColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (state == _Ready.failed)
                TextButton(
                  style: kInlineButtonStyle,
                  onPressed: onRetry,
                  child: Text(l.commonRetry),
                )
              else if (state != _Ready.searching)
                TextButton(
                  style: kInlineButtonStyle,
                  onPressed: onChange,
                  child: Text(
                    state == _Ready.noMatch
                        ? l.arrLibraryImportFind
                        : l.arrChange,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Searches for the right show or movie for a folder, starting from its
/// name. Returns the one picked.
class _MatchDialog extends StatefulWidget {
  final ArrClient client;
  final ArrFolder folder;
  const _MatchDialog({required this.client, required this.folder});

  @override
  State<_MatchDialog> createState() => _MatchDialogState();
}

class _MatchDialogState extends State<_MatchDialog> {
  late final _term = TextEditingController(text: widget.folder.name);
  List<ArrLookup<Object>>? _results;
  Object? _error;
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _term.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final term = _term.text.trim();
    if (term.isEmpty) return;
    final seq = ++_seq;
    setState(() {
      _results = null;
      _error = null;
    });
    try {
      final r = await _ArrLibraryImportScreenState._results(
        widget.client,
        term,
      );
      if (mounted && seq == _seq) setState(() => _results = r);
    } catch (e) {
      if (mounted && seq == _seq) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final results = _results;
    final app = widget.client.kind.appName;
    return AlertDialog(
      title: Text(l.arrLibraryImportMatchTitle),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 460,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.folder.path,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _term,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                border: const OutlineInputBorder(),
                isDense: true,
                hintText: widget.client.kind == ArrKind.sonarr
                    ? l.arrAddShowHint
                    : l.arrAddMovieHint,
              ),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 500), _run);
              },
              onSubmitted: (_) => _run(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _error != null
                  ? Center(child: Text(_error.toString()))
                  : results == null
                  ? const Center(child: AppSpinner(size: 24))
                  : results.isEmpty
                  ? Center(child: Text(l.arrNoMatches))
                  : ListView(
                      children: [
                        for (final r in results)
                          _ResultTile(
                            client: widget.client,
                            result: r,
                            inLibraryLabel: l.arrAlreadyInApp(app),
                            onTap: () => Navigator.pop(context, r),
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
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  final ArrClient client;
  final ArrLookup<Object> result;
  final String inLibraryLabel;
  final VoidCallback onTap;
  const _ResultTile({
    required this.client,
    required this.result,
    required this.inLibraryLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (String title, int? year, String? byline, List<ArrImage> images) =
        switch (result.item) {
          final ArrSeries s => (s.title, s.year, s.network, s.images),
          final ArrMovie m => (m.title, m.year, m.studio, m.images),
          _ => ('', null, null, const <ArrImage>[]),
        };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 34,
          height: 51,
          child: ArrArt(client: client, images: images, width: 185),
        ),
      ),
      title: Text(
        [title, if (year != null && year > 0) '($year)'].join(' '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [?byline, if (result.inLibrary) inLibraryLabel].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      onTap: onTap,
    );
  }
}
