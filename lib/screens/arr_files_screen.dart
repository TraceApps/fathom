import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../state/arr_providers.dart';
import '../widgets/app_spinner.dart';
import '../widgets/arr_delete_files.dart';
import '../widgets/arr_widgets.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';

/// A show's files, by season, to pick and delete together: whole seasons at
/// once or single episodes, which Sonarr's own Manage Episodes does too.
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
                contentPadding: const EdgeInsets.only(left: 24, right: 8),
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
