import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../state/arr_providers.dart';
import '../widgets/app_spinner.dart';
import '../widgets/arr_actions.dart';
import '../widgets/arr_delete_files.dart';
import '../widgets/arr_file_edit.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';

/// A show's files, by season: tap one to correct it (which episodes it
/// holds, its quality, languages, release group), or pick several to edit or
/// delete together, as in Sonarr's own Manage Episodes.
class ArrSeriesFilesScreen extends ConsumerStatefulWidget {
  final int id;
  const ArrSeriesFilesScreen({super.key, required this.id});

  @override
  ConsumerState<ArrSeriesFilesScreen> createState() =>
      _ArrSeriesFilesScreenState();
}

class _ArrSeriesFilesScreenState extends ConsumerState<ArrSeriesFilesScreen> {
  final Set<int> _picked = {};

  void _refresh() => arrSeriesChanged(ref, widget.id);

  /// One file: a change of episodes re-imports it in place (how Sonarr's
  /// own page does it); anything else is a plain edit.
  Future<void> _editOne(ArrFile f, List<ArrEpisode> eps) async {
    final l = AppLocalizations.of(context);
    final client = ref.read(sonarrClientProvider);
    if (client == null) return;
    final changes = await showArrFileEditDialog(
      context,
      kind: ArrKind.sonarr,
      subtitle: _fileTitle(eps, f),
      episodeChoice: true,
      seriesId: widget.id,
      seasonNumber: eps.firstOrNull?.seasonNumber ?? f.seasonNumber,
      episodeIds: [for (final e in eps) e.id],
      qualityId: arrQualityId(f.qualityModel),
      languages: f.languageItems,
      releaseGroup: f.releaseGroup,
    );
    if (changes == null || changes.isEmpty || !mounted) return;
    final ok = await arrRun(context, () async {
      if (changes.episodes != null) {
        final item = changes.applyTo(
          ArrImportItem(
            kind: ArrKind.sonarr,
            id: f.id,
            path: f.path ?? '',
            seriesId: widget.id,
            seasonNumber: eps.firstOrNull?.seasonNumber,
            episodes: eps,
            fileId: f.id,
            releaseGroup: f.releaseGroup,
            quality: f.qualityModel,
            languages: f.languageItems,
            indexerFlags: f.indexerFlags,
            releaseType: f.releaseType,
          ),
        );
        await client.manualImport([
          item.copyWith(
            releaseType: item.episodes.length > 1
                ? 'multiEpisode'
                : 'singleEpisode',
          ),
        ], 'auto');
      } else {
        await client.updateFiles([_fileChanges(f, changes)]);
      }
    }, done: changes.episodes != null ? l.arrFileMoving : l.arrSaved);
    if (!ok || !mounted) return;
    _refresh();
    // A re-import runs as a task: look again once it's had a moment.
    if (changes.episodes != null) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _refresh();
      });
    }
  }

  Future<void> _editPicked(
    List<ArrFile> picked,
    Map<int, List<ArrEpisode>> byFile,
  ) async {
    // One file: its own edit, with what it is now filled in.
    if (picked.length == 1) {
      return _editOne(picked.single, byFile[picked.single.id] ?? const []);
    }
    final l = AppLocalizations.of(context);
    final client = ref.read(sonarrClientProvider);
    if (client == null) return;
    final changes = await showArrFileEditDialog(
      context,
      kind: ArrKind.sonarr,
      subtitle: '',
      count: picked.length,
    );
    if (changes == null || changes.isEmpty || !mounted) return;
    if (await arrRun(
      context,
      () => client.updateFiles([for (final f in picked) _fileChanges(f, changes)]),
      done: l.arrSaved,
    )) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final series = ref.watch(sonarrSeriesProvider(widget.id));
    final filesAsync = ref.watch(sonarrEpisodeFilesProvider(widget.id));
    final episodesAsync = ref.watch(sonarrEpisodesProvider(widget.id));
    final episodes = episodesAsync.asData?.value ?? const <ArrEpisode>[];
    final client = ref.watch(sonarrClientProvider);
    final files = filesAsync.asData?.value.values.toList() ?? const <ArrFile>[];
    // A file can hold more than one episode (a double episode).
    final byFile = <int, List<ArrEpisode>>{};
    for (final e in episodes) {
      if (e.episodeFileId != null) {
        (byFile[e.episodeFileId!] ??= []).add(e);
      }
    }
    for (final list in byFile.values) {
      list.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    }
    int season(ArrFile f) =>
        f.seasonNumber ?? byFile[f.id]?.first.seasonNumber ?? 0;
    int firstEp(ArrFile f) => byFile[f.id]?.first.episodeNumber ?? 0;
    // Newest season first, specials last, as on the show's page.
    final seasons =
        {for (final f in files) season(f)}.toList()..sort((a, b) {
          if (a == 0) return 1;
          if (b == 0) return -1;
          return b.compareTo(a);
        });
    final bySeason = {
      for (final s in seasons)
        s: [for (final f in files) if (season(f) == s) f]
          ..sort((a, b) => firstEp(a).compareTo(firstEp(b))),
    };
    final picked = [for (final f in files) if (_picked.contains(f.id)) f];
    final pickedSize = picked.fold<int>(0, (t, f) => t + f.size);
    final all = files.isNotEmpty && picked.length == files.length;

    Widget body;
    if (filesAsync.hasError) {
      body = ErrorView(
        message: filesAsync.error.toString(),
        onRetry: _refresh,
      );
    } else if (!filesAsync.hasValue) {
      body = const Center(child: AppSpinner());
    } else if (files.isEmpty) {
      body = EmptyState(
        icon: Icons.folder_off_rounded,
        title: l.arrNoFilesYet,
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          for (final s in seasons) ...[
            _SeasonHeader(
              label: s == 0 ? l.arrSpecials : l.arrSeason(s),
              files: bySeason[s]!,
              picked: _picked,
              onChanged: (on) => setState(() {
                for (final f in bySeason[s]!) {
                  on ? _picked.add(f.id) : _picked.remove(f.id);
                }
              }),
            ),
            for (final f in bySeason[s]!)
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.only(left: 24, right: 0),
                secondary: IconButton(
                  tooltip: l.arrEditFile,
                  icon: const Icon(Icons.edit_rounded),
                  onPressed: client == null || !episodesAsync.hasValue
                      ? null
                      : () => _editOne(f, byFile[f.id] ?? const []),
                ),
                value: _picked.contains(f.id),
                onChanged: (v) => setState(
                  () => v == true ? _picked.add(f.id) : _picked.remove(f.id),
                ),
                title: Text(
                  _fileTitle(byFile[f.id], f),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    if (f.quality != null) f.quality!,
                    if (f.languages.isNotEmpty) f.languages.join(', '),
                    ?f.releaseGroup,
                    arrSize(f.size),
                  ].join(' · '),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.arrManageFiles),
            if (series.asData?.value.title case final t?)
              Text(
                t,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          if (files.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                if (all) {
                  _picked.clear();
                } else {
                  _picked.addAll(files.map((f) => f.id));
                }
              }),
              child: Text(all ? l.arrSelectNoFiles : l.arrSelectAllFiles),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: body,
      bottomNavigationBar: picked.isEmpty || client == null
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
                          l.arrFilesSelected(picked.length, arrSize(pickedSize)),
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: !episodesAsync.hasValue
                            ? null
                            : () => _editPicked(picked, byFile),
                        child: Text(l.arrEdit),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                          foregroundColor: theme.colorScheme.onError,
                          minimumSize: const Size(0, 44),
                        ),
                        icon: const Icon(Icons.delete_rounded),
                        label: Text(l.commonDelete),
                        // Waits for the episodes, so the dialog can offer to
                        // unmonitor them.
                        onPressed: !episodesAsync.hasValue
                            ? null
                            : () async {
                          final s = series.asData?.value;
                          if (s == null) return;
                          final ok = await showArrDeleteFilesDialog(
                            context,
                            client: client,
                            series: s,
                            files: picked,
                            episodeIds: [
                              for (final f in picked)
                                for (final e in byFile[f.id] ?? const [])
                                  e.id,
                            ],
                          );
                          if (ok && mounted) {
                            setState(_picked.clear);
                            _refresh();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  /// What [changes] sends for [f] in Sonarr's file edit: only what changed.
  static Map<String, dynamic> _fileChanges(ArrFile f, ArrFileChanges changes) => {
    'id': f.id,
    if (changes.quality != null)
      'quality': arrQualityModel(changes.quality!, f.qualityModel),
    if (changes.languages != null)
      'languages': [for (final l in changes.languages!) l.toJson()],
    if (changes.releaseGroup != null) 'releaseGroup': changes.releaseGroup,
  };

  /// "S02E03 · Title", or the file name when the episode isn't known.
  static String _fileTitle(List<ArrEpisode>? eps, ArrFile f) {
    if (eps == null || eps.isEmpty) {
      return (f.relativePath ?? '').split('/').last;
    }
    final code = eps.length == 1
        ? eps.first.code
        : '${eps.first.code}-E${eps.last.episodeNumber.toString().padLeft(2, '0')}';
    final title = eps.first.title;
    return title == null || title.isEmpty ? code : '$code · $title';
  }
}

/// A season's heading: ticks or clears all of its files at once.
class _SeasonHeader extends StatelessWidget {
  final String label;
  final List<ArrFile> files;
  final Set<int> picked;
  final ValueChanged<bool> onChanged;
  const _SeasonHeader({
    required this.label,
    required this.files,
    required this.picked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final n = files.where((f) => picked.contains(f.id)).length;
    final size = files.fold<int>(0, (t, f) => t + f.size);
    return CheckboxListTile(
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      tristate: true,
      value: n == 0 ? false : (n == files.length ? true : null),
      // A part-ticked season ticks the rest first, like a file manager.
      onChanged: (_) => onChanged(n < files.length),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        [l.arrFilesCountShort(files.length), arrSize(size)].join(' · '),
      ),
    );
  }
}
