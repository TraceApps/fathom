import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../widgets/search_field.dart';

/// One search result to add: what the add form needs to know about it.
class _Found {
  final String title;
  final int? year;
  final String? overview;
  final String? byline; // network or studio
  final List<ArrImage> images;
  final ArrLookup<Object> lookup;
  const _Found({
    required this.title,
    required this.year,
    required this.overview,
    required this.byline,
    required this.images,
    required this.lookup,
  });
}

/// Finds a movie (Radarr) or show (Sonarr) online and adds it.
class ArrAddScreen extends ConsumerStatefulWidget {
  final ArrKind kind;
  const ArrAddScreen({super.key, required this.kind});

  @override
  ConsumerState<ArrAddScreen> createState() => _ArrAddScreenState();
}

class _ArrAddScreenState extends ConsumerState<ArrAddScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  Future<List<_Found>>? _results;
  String _asked = '';

  bool get _shows => widget.kind == ArrKind.sonarr;

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

  void _run() {
    final term = _search.text.trim();
    if (term == _asked) return;
    _asked = term;
    if (term.isEmpty) {
      setState(() => _results = null);
      return;
    }
    final c = arrClient(ref, widget.kind);
    if (c == null) return;
    setState(() {
      _results = c is SonarrClient
          ? c
                .lookup(term)
                .then(
                  (list) => [
                    for (final x in list)
                      _Found(
                        title: x.item.title,
                        year: x.item.year,
                        overview: x.item.overview,
                        byline: x.item.network,
                        images: x.item.images,
                        lookup: x,
                      ),
                  ],
                )
          : (c as RadarrClient)
                .lookup(term)
                .then(
                  (list) => [
                    for (final x in list)
                      _Found(
                        title: x.item.title,
                        year: x.item.year,
                        overview: x.item.overview,
                        byline: x.item.studio,
                        images: x.item.images,
                        lookup: x,
                      ),
                  ],
                );
    });
  }

  Future<void> _pick(_Found f) async {
    final kindPath = _shows ? 'series' : 'movie';
    if (f.lookup.inLibrary) {
      context.push('/arr/$kindPath/${f.lookup.existingId}');
      return;
    }
    final client = arrClient(ref, widget.kind);
    if (client == null) return;
    final id = await showDialog<int>(
      context: context,
      builder: (_) => _AddDialog(client: client, found: f),
    );
    if (id == null || !mounted) return;
    if (_shows) {
      ref.invalidate(sonarrSeriesListProvider);
    } else {
      ref.invalidate(radarrMoviesProvider);
    }
    ref.invalidate(arrCalendarProvider);
    // The search is done with; land on what was added.
    context.pushReplacement('/arr/$kindPath/$id');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_shows ? l.arrAddShow : l.arrAddMovie)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              controller: _search,
              hint: _shows ? l.arrAddShowHint : l.arrAddMovieHint,
              autofocus: true,
              onChanged: _changed,
              onSubmitted: (_) {
                _debounce?.cancel();
                _run();
              },
            ),
          ),
          Expanded(
            child: _results == null
                ? EmptyState(
                    icon: _shows ? Icons.live_tv_rounded : Icons.movie_rounded,
                    title: _shows ? l.arrAddShow : l.arrAddMovie,
                    message: _shows ? l.arrAddShowTip : l.arrAddMovieTip,
                  )
                : FutureBuilder<List<_Found>>(
                    future: _results,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) {
                        return const Center(child: AppSpinner());
                      }
                      if (snap.hasError) {
                        return ErrorView(
                          message: snap.error.toString(),
                          onRetry: () {
                            _asked = '';
                            _run();
                          },
                        );
                      }
                      final list = snap.data ?? const <_Found>[];
                      if (list.isEmpty) {
                        return EmptyState(
                          icon: Icons.search_off_rounded,
                          title: l.arrNoMatches,
                        );
                      }
                      final client = arrClient(ref, widget.kind);
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final f = list[i];
                          return Card(
                            margin: EdgeInsets.zero,
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => _pick(f),
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
                                          placeholderIcon: _shows
                                              ? Icons.live_tv_rounded
                                              : Icons.movie_rounded,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            [
                                              f.title,
                                              if (f.year != null && f.year! > 0)
                                                '(${f.year})',
                                            ].join(' '),
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          if (f.byline?.isNotEmpty ?? false)
                                            Text(
                                              f.byline!,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: theme
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          if (f.lookup.inLibrary)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 6,
                                              ),
                                              child: ArrChip(
                                                label: l.arrInLibrary,
                                                color: arrDownloadedColor,
                                                icon: Icons.check_rounded,
                                              ),
                                            ),
                                          if (f.overview?.isNotEmpty ??
                                              false) ...[
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
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// The last choices made in the add form, kept while Fathom runs so adding
/// several titles in a row doesn't mean picking them all again.
final _lastChoices = <ArrKind, Map<String, Object>>{};

class _AddDialog extends ConsumerStatefulWidget {
  final ArrClient client;
  final _Found found;
  const _AddDialog({required this.client, required this.found});

  @override
  ConsumerState<_AddDialog> createState() => _AddDialogState();
}

class _AddDialogState extends ConsumerState<_AddDialog> {
  late final Map<String, Object> _last =
      _lastChoices[widget.client.kind] ?? const {};
  String? _root;
  int? _profile;
  late String _monitor =
      _last['monitor'] as String? ?? (_shows ? 'all' : 'movieOnly');
  late String _seriesType =
      widget.found.lookup.raw['seriesType'] as String? ?? 'standard';
  late bool _seasonFolder = _last['seasonFolder'] as bool? ?? true;
  late String _availability = _last['availability'] as String? ?? 'released';
  late bool _searchNow = _last['search'] as bool? ?? true;
  bool _busy = false;

  bool get _shows => widget.client.kind == ArrKind.sonarr;

  Future<void> _add() async {
    final l = AppLocalizations.of(context);
    final c = widget.client;
    setState(() => _busy = true);
    _lastChoices[c.kind] = {
      'root': _root!,
      'profile': _profile!,
      'monitor': _monitor,
      'seasonFolder': _seasonFolder,
      'availability': _availability,
      'search': _searchNow,
    };
    var id = 0;
    final ok = await arrRun(context, () async {
      if (c is SonarrClient) {
        id = (await c.addSeries(
          widget.found.lookup.raw,
          qualityProfileId: _profile!,
          rootFolderPath: _root!,
          monitor: _monitor,
          seriesType: _seriesType,
          seasonFolder: _seasonFolder,
          search: _searchNow,
        )).id;
      } else {
        id = (await (c as RadarrClient).addMovie(
          widget.found.lookup.raw,
          qualityProfileId: _profile!,
          rootFolderPath: _root!,
          monitor: _monitor,
          minimumAvailability: _availability,
          search: _searchNow,
        )).id;
      }
    }, done: l.arrAddedTo(widget.found.title, c.kind.appName));
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, id);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final kind = widget.client.kind;
    final roots = ref.watch(arrRootFoldersProvider(kind));
    final profiles = ref.watch(arrQualityProfileListProvider(kind));
    final rootList = roots.asData?.value ?? const <ArrRootFolder>[];
    final profileList = profiles.asData?.value ?? const <ArrQualityProfile>[];
    // Start on the last choice when it still exists, else the first.
    if (_root == null && rootList.isNotEmpty) {
      final last = _last['root'];
      _root = rootList.any((r) => r.path == last)
          ? last as String
          : rootList.first.path;
    }
    if (_profile == null && profileList.isNotEmpty) {
      final last = _last['profile'];
      _profile = profileList.any((p) => p.id == last)
          ? last as int
          : profileList.first.id;
    }
    final loading = !roots.hasValue || !profiles.hasValue;
    final error = roots.error ?? profiles.error;
    Widget body;
    if (error != null) {
      body = Text(
        error.toString(),
        style: TextStyle(color: theme.colorScheme.error),
      );
    } else if (loading) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: AppSpinner()),
      );
    } else if (rootList.isEmpty) {
      body = Text(l.arrNoRootFolder(kind.appName));
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.found.overview?.isNotEmpty ?? false) ...[
            Text(
              widget.found.overview!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
          ],
          ArrDropdownField<String>(
            label: l.arrRootFolder,
            value: _root,
            options: {
              for (final r in rootList)
                r.path: r.freeSpace == null
                    ? r.path
                    : '${r.path}  ·  ${l.arrFree(arrSize(r.freeSpace!))}',
            },
            onChanged: _busy ? null : (v) => setState(() => _root = v),
          ),
          ArrDropdownField<String>(
            label: l.arrMonitor,
            value: _monitor,
            options: _shows ? arrMonitorOptions(l) : arrMovieMonitorOptions(l),
            onChanged: _busy
                ? null
                : (v) => setState(() => _monitor = v ?? _monitor),
          ),
          ArrDropdownField<int>(
            label: l.arrQualityProfile,
            value: _profile,
            options: {for (final p in profileList) p.id: p.name},
            onChanged: _busy ? null : (v) => setState(() => _profile = v),
          ),
          if (_shows) ...[
            ArrDropdownField<String>(
              label: l.arrSeriesType,
              value: _seriesType,
              options: arrSeriesTypes(l),
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _seriesType = v ?? _seriesType),
            ),
            ArrCheck(
              label: l.arrSeasonFolders,
              value: _seasonFolder,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _seasonFolder = v),
            ),
          ] else
            ArrDropdownField<String>(
              label: l.arrMinimumAvailability,
              value: _availability,
              options: arrAvailabilities(l),
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _availability = v ?? _availability),
            ),
          ArrCheck(
            label: _shows ? l.arrSearchMissingNow : l.arrSearchMovieNow,
            value: _searchNow,
            onChanged: _busy ? null : (v) => setState(() => _searchNow = v),
          ),
        ],
      );
    }
    final f = widget.found;
    return ArrDialogFrame(
      client: widget.client,
      images: f.images,
      heading: _shows ? l.arrAddShow : l.arrAddMovie,
      title: [
        f.title,
        if (f.year != null && f.year! > 0) '(${f.year})',
      ].join(' '),
      body: body,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          style: kInlineButtonStyle,
          onPressed: _busy || _root == null || _profile == null ? null : _add,
          child: _busy ? const AppSpinner.inline() : Text(l.arrAdd),
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
