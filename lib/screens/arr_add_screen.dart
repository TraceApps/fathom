import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/arr_client.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../state/arr_providers.dart';
import '../state/preferences.dart';
import '../theme/app_theme.dart';
import '../widgets/app_spinner.dart';
import '../widgets/arr_actions.dart';
import '../widgets/arr_tags.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/search_field.dart';

/// One search result to add: what the add form needs to know about it.
class _Found {
  final ArrKind kind;
  final String title;
  final int? year;
  final String? overview;
  final String? byline; // network or studio
  final List<ArrImage> images;
  final ArrLookup<Object> lookup;
  const _Found({
    required this.kind,
    required this.title,
    required this.year,
    required this.overview,
    required this.byline,
    required this.images,
    required this.lookup,
  });

  String get heading =>
      [title, if (year != null && year! > 0) '($year)'].join(' ');
}

/// Which apps a search goes to. TMDB numbers mean a different title in each
/// app (tmdb:603 is The Matrix in Radarr, a sitcom in Sonarr), so with both
/// asked, `tmdb:` goes to Radarr and `tvdb:` to Sonarr; a name or `imdb:`
/// goes to both. One app on its own gets every search.
List<ArrKind> arrAddKindsFor(String term, List<ArrKind> asked) {
  if (asked.length < 2) return asked;
  final t = term.trim().toLowerCase();
  return [
    for (final k in asked)
      if (!(t.startsWith('tmdb:') && k == ArrKind.sonarr) &&
          !(t.startsWith('tvdb:') && k == ArrKind.radarr))
        k,
  ];
}

/// Finds movies (Radarr) and shows (Sonarr) online and adds them. With no
/// [kind] it searches every connected app at once.
class ArrAddScreen extends ConsumerStatefulWidget {
  final ArrKind? kind;

  /// What to search for first, such as `tmdb:603` from a Jellyfin page.
  final String? term;

  /// The title's folder name on disk, when Jellyfin knows it, so Add can
  /// point the app at that folder instead of making a second one.
  final String? folder;
  const ArrAddScreen({super.key, this.kind, this.term, this.folder});

  @override
  ConsumerState<ArrAddScreen> createState() => _ArrAddScreenState();
}

class _ArrAddScreenState extends ConsumerState<ArrAddScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  Map<ArrKind, Future<List<_Found>>> _results = const {};
  String _asked = '';
  late ArrKind? _only = widget.kind; // null: both apps
  // Opening from a Jellyfin page goes straight to the form once, when the
  // lookup finds exactly that one title.
  bool _autoOpen = false;

  List<ArrKind> get _connected => [
    if (ref.read(radarrClientProvider) != null) ArrKind.radarr,
    if (ref.read(sonarrClientProvider) != null) ArrKind.sonarr,
  ];

  List<ArrKind> get _kinds => _only == null ? _connected : [_only!];

  /// Jellyfin's folder name belongs to the title Add was opened for; once
  /// the search changes it says nothing about the results.
  String? get _hint => _asked == widget.term?.trim() ? widget.folder : null;

  @override
  void initState() {
    super.initState();
    final term = widget.term;
    if (term != null && term.isNotEmpty) {
      _search.text = term;
      _autoOpen =
          widget.kind != null &&
          RegExp(r'^(tmdb|tvdb|imdb):', caseSensitive: false).hasMatch(term);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run();
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _run);
  }

  Future<List<_Found>> _lookup(ArrKind kind, String term) async {
    final c = arrClient(ref, kind);
    if (c is SonarrClient) {
      return [
        for (final x in await c.lookup(term))
          _Found(
            kind: kind,
            title: x.item.title,
            year: x.item.year,
            overview: x.item.overview,
            byline: x.item.network,
            images: x.item.images,
            lookup: x,
          ),
      ];
    }
    if (c is RadarrClient) {
      return [
        for (final x in await c.lookup(term))
          _Found(
            kind: kind,
            title: x.item.title,
            year: x.item.year,
            overview: x.item.overview,
            byline: x.item.studio,
            images: x.item.images,
            lookup: x,
          ),
      ];
    }
    return const [];
  }

  void _run({bool force = false}) {
    final term = _search.text.trim();
    if (term == _asked && !force) return;
    _asked = term;
    if (term.isEmpty) {
      setState(() => _results = const {});
      return;
    }
    final results = {
      for (final k in arrAddKindsFor(term, _kinds)) k: _lookup(k, term),
    };
    setState(() => _results = results);
    if (_autoOpen && results.length == 1) {
      _autoOpen = false;
      results.values.first.then((list) {
        if (!mounted || list.length != 1) return;
        _pick(list.first);
      }, onError: (_) {});
    }
  }

  void _setOnly(ArrKind? k) {
    setState(() => _only = k);
    _run(force: true);
  }

  Future<void> _pick(_Found f) async {
    final kindPath = f.kind == ArrKind.sonarr ? 'series' : 'movie';
    if (f.lookup.inLibrary) {
      context.push('/arr/$kindPath/${f.lookup.existingId}');
      return;
    }
    final client = arrClient(ref, f.kind);
    if (client == null) return;
    final id = await showDialog<int>(
      context: context,
      builder: (_) => _AddDialog(client: client, found: f, folderHint: _hint),
    );
    if (id == null || !mounted) return;
    if (f.kind == ArrKind.sonarr) {
      ref.invalidate(sonarrSeriesListProvider);
    } else {
      ref.invalidate(radarrMoviesProvider);
    }
    ref.invalidate(arrRootFoldersProvider(f.kind));
    ref.invalidate(arrCalendarProvider);
    // The search is done with; land on what was added.
    context.pushReplacement('/arr/$kindPath/$id');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final both = _connected.length > 1;
    final title = switch (_only) {
      ArrKind.radarr => l.arrAddMovie,
      ArrKind.sonarr => l.arrAddShow,
      null => l.arrAddTitle,
    };
    final hint = switch (_only) {
      ArrKind.radarr => l.arrAddMovieHint,
      ArrKind.sonarr => l.arrAddShowHint,
      null => l.arrAddAnyHint,
    };
    final tip = switch (_only) {
      ArrKind.radarr => l.arrAddMovieTip,
      ArrKind.sonarr => l.arrAddShowTip,
      null => l.arrAddAnyTip,
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              controller: _search,
              hint: hint,
              autofocus: widget.term == null,
              onChanged: _changed,
              onSubmitted: (_) {
                _debounce?.cancel();
                _run();
              },
            ),
          ),
          if (both)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<ArrKind?>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: null, label: Text(l.browseAll)),
                    ButtonSegment(
                      value: ArrKind.radarr,
                      icon: const Icon(Icons.movie_rounded),
                      label: Text(l.arrMovies),
                    ),
                    ButtonSegment(
                      value: ArrKind.sonarr,
                      icon: const Icon(Icons.live_tv_rounded),
                      label: Text(l.arrShows),
                    ),
                  ],
                  selected: {_only},
                  onSelectionChanged: (s) => _setOnly(s.first),
                ),
              ),
            ),
          Expanded(
            child: _results.isEmpty
                ? EmptyState(
                    icon: switch (_only) {
                      ArrKind.sonarr => Icons.live_tv_rounded,
                      ArrKind.radarr => Icons.movie_rounded,
                      null => Icons.add_circle_outline_rounded,
                    },
                    title: title,
                    message: tip,
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      for (final e in _results.entries)
                        _ResultSection(
                          key: ValueKey('${e.key}-$_asked'),
                          kind: e.key,
                          future: e.value,
                          titled: _results.length > 1,
                          folderHint: _hint,
                          onPick: _pick,
                          onRetry: () => _run(force: true),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// One app's search results, under its own heading when both apps were asked.
class _ResultSection extends ConsumerWidget {
  final ArrKind kind;
  final Future<List<_Found>> future;
  final bool titled;
  final String? folderHint;
  final ValueChanged<_Found> onPick;
  final VoidCallback onRetry;
  const _ResultSection({
    super.key,
    required this.kind,
    required this.future,
    required this.titled,
    required this.folderHint,
    required this.onPick,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final shows = kind == ArrKind.sonarr;
    final roots =
        ref.watch(arrRootFoldersProvider(kind)).asData?.value ??
        const <ArrRootFolder>[];
    final client = arrClient(ref, kind);
    return FutureBuilder<List<_Found>>(
      future: future,
      builder: (context, snap) {
        final heading = titled
            ? Padding(
                padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
                child: Row(
                  children: [
                    Icon(
                      shows ? Icons.live_tv_rounded : Icons.movie_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      shows ? l.arrShows : l.arrMovies,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (snap.hasData) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${snap.data!.length}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              )
            : const SizedBox(height: 4);
        Widget body;
        if (snap.connectionState != ConnectionState.done) {
          body = const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: AppSpinner()),
          );
        } else if (snap.hasError) {
          body = ErrorView(message: snap.error.toString(), onRetry: onRetry);
        } else if (snap.data!.isEmpty) {
          body = titled
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
                  child: Text(
                    l.arrNothingIn(kind.appName),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: l.arrNoMatches,
                  ),
                );
        } else {
          body = Column(
            children: [
              for (final f in snap.data!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ResultCard(
                    found: f,
                    client: client,
                    onDisk:
                        !f.lookup.inLibrary &&
                        (arrExistingFolder(
                              roots,
                              title: f.title,
                              year: f.year,
                              hint: folderHint,
                            )?.sure ??
                            false),
                    onTap: () => onPick(f),
                  ),
                ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [heading, body],
        );
      },
    );
  }
}

class _ResultCard extends StatelessWidget {
  final _Found found;
  final ArrClient? client;
  final bool onDisk;
  final VoidCallback onTap;
  const _ResultCard({
    required this.found,
    required this.client,
    required this.onDisk,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final f = found;
    final shows = f.kind == ArrKind.sonarr;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 68,
                  height: 102,
                  child: ArrArt(
                    client: client,
                    images: f.images,
                    width: 185,
                    placeholderIcon: shows
                        ? Icons.live_tv_rounded
                        : Icons.movie_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.heading,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (f.byline?.isNotEmpty ?? false)
                      Text(
                        f.byline!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (f.lookup.inLibrary || onDisk)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: f.lookup.inLibrary
                            ? ArrChip(
                                label: l.arrInLibrary,
                                color: arrDownloadedColor,
                                icon: Icons.check_rounded,
                              )
                            : ArrChip(
                                label: l.arrOnDisk,
                                color: arrContinuingColor,
                                icon: Icons.folder_rounded,
                              ),
                      ),
                    if (f.overview?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 6),
                      Text(
                        f.overview!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The add form: where the title goes and how it downloads.
class _AddDialog extends ConsumerStatefulWidget {
  final ArrClient client;
  final _Found found;
  final String? folderHint;
  const _AddDialog({
    required this.client,
    required this.found,
    required this.folderHint,
  });

  @override
  ConsumerState<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends ConsumerState<_AddDialog> {
  ArrChoiceDraft? _draft;
  ArrFolderMatch? _match;
  ArrFolder? get _existing => _match?.folder;
  bool _useExisting = false;
  bool _busy = false;

  ArrKind get _kind => widget.client.kind;
  bool get _shows => _kind == ArrKind.sonarr;

  /// Fills the form once, the first time everything it needs has loaded.
  void _start(ArrAddSetup setup) {
    if (_draft != null) return;
    final f = widget.found;
    final draft = ArrChoiceDraft.from(setup.choice);
    // Sonarr knows when a show is anime or daily; that beats the default.
    final looked = f.lookup.raw['seriesType'] as String?;
    if (_shows && looked != null && looked != 'standard') {
      draft.seriesType = looked;
    }
    _match = arrExistingFolder(
      setup.roots,
      title: f.title,
      year: f.year,
      hint: widget.folderHint,
    );
    // A name-only match may be another film of the same name: shown, but
    // left off for the person to confirm.
    _useExisting = _match?.sure ?? false;
    // Files are already there: searching straight away would only look for
    // an upgrade, so it starts off and is the person's call.
    if (_useExisting) draft.search = false;
    _draft = draft;
  }

  Future<void> _add(ArrAddSetup setup) async {
    final l = AppLocalizations.of(context);
    final c = widget.client;
    final d = _draft!;
    final existing = _useExisting ? _existing : null;
    final root = existing != null
        ? arrRootOf(existing.path, [for (final r in setup.roots) r.path]) ??
              d.rootFolder!
        : d.rootFolder!;
    // Saved defaults may name a tag deleted since; send only live ones,
    // once the server's list is known (not loaded yet: send them as they
    // are rather than drop them all).
    final known = ref.read(arrTagsProvider(_kind)).asData?.value;
    final live = known == null ? null : {for (final t in known) t.id};
    final tags = [
      for (final t in d.tags)
        if (live == null || live.contains(t)) t,
    ];
    setState(() => _busy = true);
    var id = 0;
    final ok = await arrRun(context, () async {
      if (c is SonarrClient) {
        id = (await c.addSeries(
          widget.found.lookup.raw,
          qualityProfileId: d.qualityProfileId!,
          rootFolderPath: root,
          monitor: d.monitor,
          seriesType: d.seriesType,
          seasonFolder: d.seasonFolder,
          search: d.search,
          searchCutoff: d.searchCutoff,
          monitorNewSeasons: d.monitorNewSeasons,
          tags: tags,
          path: existing?.path,
        )).id;
      } else {
        id = (await (c as RadarrClient).addMovie(
          widget.found.lookup.raw,
          qualityProfileId: d.qualityProfileId!,
          rootFolderPath: root,
          monitor: d.monitor,
          minimumAvailability: d.minimumAvailability,
          search: d.search,
          tags: tags,
          path: existing?.path,
        )).id;
      }
    }, done: l.arrAddedTo(widget.found.title, c.kind.appName));
    if (!mounted) return;
    if (ok) {
      // What was picked is where the next add starts, the way Sonarr's and
      // Radarr's own pages do it. An add into an existing folder says nothing
      // about where new titles go or whether to search, so those stay.
      final saved = arrSavedDefaults(
        ref.read(preferencesProvider).asData?.value ?? const Prefs(),
        _kind,
      );
      await saveArrAddDefaults(
        ref,
        _kind,
        d.toDefaults(kind: _kind, keep: existing != null ? saved : null),
      );
      if (mounted) Navigator.pop(context, id);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final setupAsync = ref.watch(arrAddSetupProvider(_kind));
    final setup = setupAsync.asData?.value;
    if (setup != null) _start(setup);
    final f = widget.found;
    Widget body;
    if (setupAsync.hasError && setup == null) {
      body = Text(
        setupAsync.error.toString(),
        style: TextStyle(color: theme.colorScheme.error),
      );
    } else if (setup == null) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: AppSpinner()),
      );
    } else if (setup.roots.isEmpty) {
      body = Text(l.arrNoRootFolder(_kind.appName));
    } else {
      final existing = _existing;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (f.overview?.isNotEmpty ?? false) ...[
            Text(
              f.overview!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (existing != null) ...[
            _ExistingFolderCard(
              app: _kind.appName,
              folder: existing,
              use: _useExisting,
              sure: _match!.sure,
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      _useExisting = v;
                      _draft!.search = !v && _draft!.searchDefault;
                    }),
            ),
            const SizedBox(height: 16),
          ],
          ArrChoiceFields(
            kind: _kind,
            setup: setup,
            draft: _draft!,
            showRoot: !_useExisting,
            enabled: !_busy,
            explainProfile: true,
            client: widget.client,
            onChanged: () => setState(() {}),
          ),
        ],
      );
    }
    final d = _draft;
    return ArrDialogFrame(
      client: widget.client,
      images: f.images,
      heading: _shows ? l.arrAddShow : l.arrAddMovie,
      title: f.heading,
      body: body,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          style: kInlineButtonStyle,
          onPressed:
              _busy ||
                  setup == null ||
                  d == null ||
                  d.rootFolder == null ||
                  d.qualityProfileId == null
              ? null
              : () => _add(setup),
          child: _busy ? const AppSpinner.inline() : Text(l.arrAdd),
        ),
      ],
    );
  }
}

/// "Already on disk": the folder Add found for this title, and the choice
/// to use it.
class _ExistingFolderCard extends StatelessWidget {
  final String app;
  final ArrFolder folder;
  final bool use;
  final bool sure;
  final ValueChanged<bool>? onChanged;
  const _ExistingFolderCard({
    required this.app,
    required this.folder,
    required this.use,
    required this.sure,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = arrContinuingColor;
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.folder_rounded, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sure ? l.arrExistingFolder : l.arrExistingFolderMaybe,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  folder.path,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  use
                      ? l.arrExistingFolderUse(app)
                      : sure
                      ? l.arrExistingFolderSkip(app)
                      : l.arrExistingFolderCheck,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: use, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// The choices being made in Add, or for the defaults in Settings.
class ArrChoiceDraft {
  String? rootFolder;
  int? qualityProfileId;
  String monitor;
  String minimumAvailability;
  String seriesType;
  bool seasonFolder;
  bool search;
  bool monitorNewSeasons;
  bool searchCutoff;
  List<int> tags;

  /// The search setting Add started with, to go back to when "use the
  /// existing folder" is switched off again.
  final bool searchDefault;
  final ArrChoiceSource profileSource;

  ArrChoiceDraft.from(ArrAddChoice c)
    : rootFolder = c.rootFolder,
      qualityProfileId = c.qualityProfileId,
      monitor = c.monitor,
      minimumAvailability = c.minimumAvailability,
      seriesType = c.seriesType,
      seasonFolder = c.seasonFolder,
      search = c.search,
      monitorNewSeasons = c.monitorNewSeasons,
      searchCutoff = c.searchCutoff,
      tags = [...c.tags],
      searchDefault = c.search,
      profileSource = c.profileSource;

  /// What to save as the next starting point. With [keep] (an add into an
  /// existing folder), the root folder and search are left as [keep] has
  /// them, even unset: that add said nothing about where new titles go or
  /// whether to search.
  ArrAddDefaults toDefaults({required ArrKind kind, ArrAddDefaults? keep}) {
    final shows = kind == ArrKind.sonarr;
    return ArrAddDefaults(
      rootFolder: keep != null ? keep.rootFolder : rootFolder,
      qualityProfileId: qualityProfileId,
      monitor: monitor,
      minimumAvailability: shows ? null : minimumAvailability,
      seriesType: shows ? seriesType : null,
      seasonFolder: shows ? seasonFolder : null,
      search: keep != null ? keep.search : search,
      monitorNewSeasons: shows ? monitorNewSeasons : null,
      searchCutoff: shows ? (keep != null ? keep.searchCutoff : searchCutoff) : null,
      tags: [...tags]..sort(),
    );
  }
}

/// Root folder, monitoring, quality profile, the app's own options, and
/// whether to search right away. Shared by Add and by Settings' defaults.
class ArrChoiceFields extends StatelessWidget {
  final ArrKind kind;
  final ArrAddSetup setup;
  final ArrChoiceDraft draft;
  final bool showRoot;
  final bool enabled;

  /// Says under the quality profile where it came from, in Add.
  final bool explainProfile;
  final VoidCallback onChanged;

  /// For the tags (the server's list, and making new ones).
  final ArrClient? client;

  const ArrChoiceFields({
    super.key,
    required this.kind,
    required this.setup,
    required this.draft,
    required this.onChanged,
    this.showRoot = true,
    this.enabled = true,
    this.explainProfile = false,
    this.client,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final shows = kind == ArrKind.sonarr;
    final d = draft;
    void set(VoidCallback f) {
      f();
      onChanged();
    }

    final profileHelper = !explainProfile
        ? null
        : switch (d.profileSource) {
            ArrChoiceSource.saved => l.arrProfileFromDefaults,
            ArrChoiceSource.library =>
              shows ? l.arrProfileFromShows : l.arrProfileFromMovies,
            ArrChoiceSource.first => null,
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showRoot)
          ArrDropdownField<String>(
            label: l.arrRootFolder,
            value: d.rootFolder,
            options: {
              for (final r in setup.roots)
                r.path: r.freeSpace == null
                    ? r.path
                    : '${r.path}  ·  ${l.arrFree(arrSize(r.freeSpace!))}',
            },
            onChanged: enabled ? (v) => set(() => d.rootFolder = v) : null,
          ),
        ArrDropdownField<int>(
          label: l.arrQualityProfile,
          value: d.qualityProfileId,
          options: {for (final p in setup.profiles) p.id: p.name},
          helper: profileHelper,
          onChanged: enabled ? (v) => set(() => d.qualityProfileId = v) : null,
        ),
        ArrDropdownField<String>(
          label: l.arrMonitor,
          value: d.monitor,
          options: shows ? arrMonitorOptions(l) : arrMovieMonitorOptions(l),
          onChanged: enabled
              ? (v) => set(() => d.monitor = v ?? d.monitor)
              : null,
        ),
        if (shows) ...[
          ArrDropdownField<String>(
            label: l.arrSeriesType,
            value: d.seriesType,
            options: arrSeriesTypes(l),
            onChanged: enabled
                ? (v) => set(() => d.seriesType = v ?? d.seriesType)
                : null,
          ),
          ArrCheck(
            label: l.arrSeasonFolders,
            value: d.seasonFolder,
            onChanged: enabled ? (v) => set(() => d.seasonFolder = v) : null,
          ),
          ArrCheck(
            label: l.arrMonitorNewSeasons,
            hint: l.arrMonitorNewSeasonsHint,
            value: d.monitorNewSeasons,
            onChanged: enabled
                ? (v) => set(() => d.monitorNewSeasons = v)
                : null,
          ),
        ] else
          ArrDropdownField<String>(
            label: l.arrMinimumAvailability,
            value: d.minimumAvailability,
            options: arrAvailabilities(l),
            onChanged: enabled
                ? (v) => set(
                    () => d.minimumAvailability = v ?? d.minimumAvailability,
                  )
                : null,
          ),
        if (client case final c?)
          ArrTagPicker(
            client: c,
            selected: d.tags,
            onChanged: enabled ? (ids) => set(() => d.tags = ids) : null,
          ),
        ArrCheck(
          label: shows ? l.arrSearchMissingNow : l.arrSearchMovieNow,
          value: d.search,
          onChanged: enabled ? (v) => set(() => d.search = v) : null,
        ),
        if (shows)
          ArrCheck(
            label: l.arrSearchCutoffNow,
            value: d.searchCutoff,
            onChanged: enabled ? (v) => set(() => d.searchCutoff = v) : null,
          ),
      ],
    );
  }
}

/// Sonarr's choices for which episodes of a new show to monitor.
Map<String, String> arrMonitorOptions(AppLocalizations l) => {
  'all': l.arrMonitorAll,
  'future': l.arrMonitorFuture,
  'missing': l.arrMonitorMissing,
  'existing': l.arrMonitorExisting,
  'recent': l.arrMonitorRecent,
  'pilot': l.arrMonitorPilot,
  'firstSeason': l.arrMonitorFirstSeason,
  'lastSeason': l.arrMonitorLastSeason,
  'none': l.arrMonitorNone,
};

/// Radarr's choices for a new movie.
Map<String, String> arrMovieMonitorOptions(AppLocalizations l) => {
  'movieOnly': l.arrMonitorMovieOnly,
  'movieAndCollection': l.arrMonitorMovieAndCollection,
  'none': l.arrMonitorNone,
};
