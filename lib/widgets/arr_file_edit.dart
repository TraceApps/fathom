import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/arr.dart';
import '../state/arr_providers.dart';
import '../theme/app_theme.dart';
import 'arr_actions.dart';
import 'arr_widgets.dart';

/// What a file edit changes. A null field stays as it is.
class ArrFileChanges {
  final ArrSeries? series;
  final ArrMovie? movie;
  final int? seasonNumber;
  final List<ArrEpisode>? episodes;
  final ArrQualityChoice? quality;
  final List<ArrLanguage>? languages;
  final String? releaseGroup;

  const ArrFileChanges({
    this.series,
    this.movie,
    this.seasonNumber,
    this.episodes,
    this.quality,
    this.languages,
    this.releaseGroup,
  });

  bool get isEmpty =>
      series == null &&
      movie == null &&
      seasonNumber == null &&
      episodes == null &&
      quality == null &&
      languages == null &&
      releaseGroup == null;

  /// [item] with these changes. A new show starts over on its season and
  /// episodes, and a new season on its episodes, for the app to work out.
  ArrImportItem applyTo(ArrImportItem item) {
    var i = item;
    if (series != null) {
      i = i.copyWith(
        seriesId: series!.id,
        seriesTitle: series!.title,
        seasonNumber: null,
        episodes: const [],
      );
    }
    if (movie != null) {
      i = i.copyWith(
        movieId: movie!.id,
        movieTitle: movie!.title,
        movieYear: movie!.year,
      );
    }
    if (seasonNumber != null) {
      i = i.copyWith(seasonNumber: seasonNumber, episodes: const []);
    }
    if (episodes != null && episodes!.isNotEmpty) {
      i = i.copyWith(
        seasonNumber: episodes!.first.seasonNumber,
        episodes: episodes,
      );
    }
    if (quality != null) {
      i = i.copyWith(quality: arrQualityModel(quality!, i.quality));
    }
    if (languages != null) i = i.copyWith(languages: languages);
    if (releaseGroup != null) {
      i = i.copyWith(
        releaseGroup: releaseGroup!.trim().isEmpty ? null : releaseGroup!.trim(),
      );
    }
    return i;
  }
}

/// Edits one file, or several at once ([count] above 1: every field starts
/// on No Change and only the ones changed apply, as in the apps' own
/// pickers). [titleChoice] offers the show or movie (Manual Import), and
/// [episodeChoice] the season and episodes (Sonarr). Null when cancelled.
Future<ArrFileChanges?> showArrFileEditDialog(
  BuildContext context, {
  required ArrKind kind,
  required String subtitle,
  int count = 1,
  bool titleChoice = false,
  bool episodeChoice = false,
  int? seriesId,
  int? movieId,
  int? seasonNumber,
  List<int> episodeIds = const [],
  int? qualityId,
  List<ArrLanguage> languages = const [],
  String? releaseGroup,
}) => showDialog<ArrFileChanges>(
  context: context,
  builder: (_) => _FileEditDialog(
    kind: kind,
    subtitle: subtitle,
    count: count,
    titleChoice: titleChoice,
    episodeChoice: episodeChoice,
    seriesId: seriesId,
    movieId: movieId,
    seasonNumber: seasonNumber,
    episodeIds: episodeIds,
    qualityId: qualityId,
    languages: languages,
    releaseGroup: releaseGroup,
  ),
);

class _FileEditDialog extends ConsumerStatefulWidget {
  final ArrKind kind;
  final String subtitle;
  final int count;
  final bool titleChoice;
  final bool episodeChoice;
  final int? seriesId;
  final int? movieId;
  final int? seasonNumber;
  final List<int> episodeIds;
  final int? qualityId;
  final List<ArrLanguage> languages;
  final String? releaseGroup;

  const _FileEditDialog({
    required this.kind,
    required this.subtitle,
    required this.count,
    required this.titleChoice,
    required this.episodeChoice,
    required this.seriesId,
    required this.movieId,
    required this.seasonNumber,
    required this.episodeIds,
    required this.qualityId,
    required this.languages,
    required this.releaseGroup,
  });

  @override
  ConsumerState<_FileEditDialog> createState() => _FileEditDialogState();
}

class _FileEditDialogState extends ConsumerState<_FileEditDialog> {
  late int? _seriesId = widget.seriesId;
  late int? _movieId = widget.movieId;
  late int? _season = widget.seasonNumber;
  late Set<int> _episodes = {...widget.episodeIds};
  late int? _quality = _bulk ? null : widget.qualityId;
  late List<ArrLanguage>? _languages = _bulk ? null : widget.languages;
  late final _group = TextEditingController(
    text: _bulk ? '' : widget.releaseGroup ?? '',
  );

  bool get _bulk => widget.count > 1;
  bool get _shows => widget.kind == ArrKind.sonarr;

  @override
  void dispose() {
    _group.dispose();
    super.dispose();
  }

  bool _sameEpisodes() =>
      _episodes.length == widget.episodeIds.length &&
      _episodes.containsAll(widget.episodeIds);

  ArrFileChanges _changes(
    List<ArrSeries> shows,
    List<ArrMovie> movies,
    List<ArrEpisode> episodes,
    List<ArrQualityChoice> qualities,
  ) {
    final group = _group.text.trim();
    return ArrFileChanges(
      series: _seriesId != widget.seriesId
          ? shows.where((s) => s.id == _seriesId).firstOrNull
          : null,
      movie: _movieId != widget.movieId
          ? movies.where((m) => m.id == _movieId).firstOrNull
          : null,
      seasonNumber: _season != widget.seasonNumber ? _season : null,
      episodes: widget.episodeChoice && !_bulk && !_sameEpisodes()
          ? [for (final e in episodes) if (_episodes.contains(e.id)) e]
          : null,
      quality: _quality != null && _quality != widget.qualityId
          ? qualities.where((q) => q.id == _quality).firstOrNull
          : null,
      languages:
          _languages != null &&
              !(_languages!.length == widget.languages.length &&
                  _languages!.toSet().containsAll(widget.languages)) &&
              (!_bulk || _languages!.isNotEmpty)
          ? _languages
          : null,
      releaseGroup: _bulk
          ? (group.isEmpty ? null : group)
          : (group == (widget.releaseGroup ?? '') ? null : group),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final client = arrClient(ref, widget.kind);
    final shows = _shows && (widget.titleChoice || widget.episodeChoice)
        ? ref.watch(sonarrSeriesListProvider).asData?.value ?? const []
        : const <ArrSeries>[];
    final movies = !_shows && widget.titleChoice
        ? ref.watch(radarrMoviesProvider).asData?.value ?? const []
        : const <ArrMovie>[];
    final show = shows.where((s) => s.id == _seriesId).firstOrNull;
    final movie = movies.where((m) => m.id == _movieId).firstOrNull;
    final allEpisodes = _shows && widget.episodeChoice && _seriesId != null
        ? ref.watch(sonarrEpisodesProvider(_seriesId!))
        : null;
    final seasonEpisodes = [
      for (final e in allEpisodes?.asData?.value ?? const <ArrEpisode>[])
        if (e.seasonNumber == _season) e,
    ]..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    final qualitiesAsync = ref.watch(arrQualitiesProvider(widget.kind));
    final qualities = qualitiesAsync.asData?.value ?? const [];
    final changes = _changes(shows, movies, seasonEpisodes, qualities);
    // A file needs at least one episode. In Manual Import, Sonarr works the
    // season and episodes out from the file name when given just the show;
    // once a season is chosen it waits for the episodes too.
    final episodesOk =
        !widget.episodeChoice ||
        _bulk ||
        (widget.titleChoice && _season == null) ||
        _episodes.isNotEmpty ||
        _sameEpisodes();
    // A file needs a language, unless it had none and that's untouched.
    final languagesOk =
        _bulk ||
        (_languages?.isNotEmpty ?? false) ||
        (widget.languages.isEmpty && (_languages?.isEmpty ?? true));

    final seasons = [
      for (final s in show?.seasons ?? const <ArrSeason>[]) s.seasonNumber,
    ]..sort((a, b) {
        if (a == 0) return 1;
        if (b == 0) return -1;
        return a.compareTo(b);
      });

    return ArrDialogFrame(
      client: client,
      images: show?.images ?? movie?.images ?? const [],
      heading: _bulk ? l.arrEdit : l.arrEditFile,
      title: _bulk ? l.arrFilesCountShort(widget.count) : widget.subtitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.titleChoice)
            _PickerField(
              label: _shows ? l.arrShow : l.arrMovie,
              value: _shows
                  ? show?.title
                  : movie == null
                  ? null
                  : [movie.title, if (movie.year != null) '(${movie.year})']
                        .join(' '),
              empty: _bulk
                  ? l.arrNoChange
                  : (_shows ? l.arrChooseShow : l.arrChooseMovie),
              onTap: () async {
                final picked = _shows
                    ? await _pickTitle<ArrSeries>(
                        context,
                        hint: l.arrSearchShows,
                        items: shows,
                        label: (s) => s.title,
                        year: (s) => s.year,
                        id: (s) => s.id,
                      )
                    : await _pickTitle<ArrMovie>(
                        context,
                        hint: l.arrSearchMovies,
                        items: movies,
                        label: (m) => m.title,
                        year: (m) => m.year,
                        id: (m) => m.id,
                      );
                if (picked == null || !mounted) return;
                setState(() {
                  if (_shows) {
                    if (picked != _seriesId) {
                      _seriesId = picked;
                      // The app works the season and episodes out again.
                      _season = null;
                      _episodes = {};
                    }
                  } else {
                    _movieId = picked;
                  }
                });
              },
            ),
          if (_shows && widget.episodeChoice && _seriesId != null) ...[
            ArrDropdownField<int>(
              label: l.arrSeasonLabel,
              value: _season,
              helper: widget.titleChoice && !_bulk && _season == null
                  ? l.arrSeasonAuto(widget.kind.appName)
                  : null,
              options: {
                for (final s in seasons)
                  s: s == 0 ? l.arrSpecials : l.arrSeason(s),
              },
              onChanged: (v) => setState(() {
                if (v != _season) {
                  _season = v;
                  _episodes = {};
                }
              }),
            ),
            // Episodes as one field that opens its own list, so a long
            // season doesn't push quality and languages off the screen.
            if (!_bulk && _season != null)
              _PickerField(
                label: l.arrEpisodes,
                value: allEpisodes == null || !allEpisodes.hasValue
                    ? null
                    : _episodesLabel(seasonEpisodes),
                empty: l.arrChooseEpisodes,
                onTap: allEpisodes == null || !allEpisodes.hasValue
                    ? null
                    : () async {
                        final picked = await showDialog<Set<int>>(
                          context: context,
                          builder: (_) => _EpisodePicker(
                            episodes: seasonEpisodes,
                            chosen: _episodes,
                            ownIds: widget.episodeIds,
                          ),
                        );
                        if (picked != null && mounted) {
                          setState(() => _episodes = picked);
                        }
                      },
              ),
          ],
          ArrDropdownField<int>(
            label: l.arrSortQuality,
            value: _quality ?? (_bulk ? -1 : null),
            options: {
              if (_bulk) -1: l.arrNoChange,
              for (final q in qualities) q.id: q.name,
              // A quality the list doesn't have still shows as itself.
              if (_quality != null && !qualities.any((q) => q.id == _quality))
                _quality!: '…',
            },
            onChanged: (v) => setState(() => _quality = v == -1 ? null : v),
          ),
          _LanguagesField(
            kind: widget.kind,
            value: _languages,
            empty: _bulk ? l.arrNoChange : l.arrChooseLanguages,
            onChanged: (v) => setState(() => _languages = v),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(l.arrReleaseGroup, style: theme.textTheme.labelLarge),
          ),
          TextField(
            controller: _group,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: _bulk ? l.arrNoChange : null,
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
          onPressed: changes.isEmpty || !episodesOk || !languagesOk
              ? null
              : () => Navigator.pop(context, changes),
          child: Text(l.commonSave),
        ),
      ],
    );
  }
}

extension on _FileEditDialogState {
  /// "S02E03 · Title", "S02E03-E04", or null when none is ticked.
  String? _episodesLabel(List<ArrEpisode> season) {
    final picked = [for (final e in season) if (_episodes.contains(e.id)) e];
    if (picked.isEmpty) return null;
    if (picked.length == 1) {
      final e = picked.single;
      return [e.code, if (e.title?.isNotEmpty ?? false) e.title!].join(' · ');
    }
    return picked.map((e) => e.code).join(', ');
  }
}

/// The season's episodes, to tick the ones a file holds.
class _EpisodePicker extends StatefulWidget {
  final List<ArrEpisode> episodes;
  final Set<int> chosen;

  /// The file's own episodes now (they don't count as "has a file").
  final List<int> ownIds;
  const _EpisodePicker({
    required this.episodes,
    required this.chosen,
    required this.ownIds,
  });

  @override
  State<_EpisodePicker> createState() => _EpisodePickerState();
}

class _EpisodePickerState extends State<_EpisodePicker> {
  late final Set<int> _picked = {...widget.chosen};

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l.arrEpisodes),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: SizedBox(
        width: 420,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.arrEpisodesHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: widget.episodes.isEmpty
                  ? Center(child: Text(l.arrNoEpisodesInSeason))
                  : ListView(
                      children: [
                        for (final e in widget.episodes)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _picked.contains(e.id),
                            onChanged: (v) => setState(
                              () => v == true
                                  ? _picked.add(e.id)
                                  : _picked.remove(e.id),
                            ),
                            title: Text(
                              [
                                e.code,
                                if (e.title?.isNotEmpty ?? false) e.title!,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // Taking an episode that has a file replaces it.
                            subtitle:
                                e.episodeFileId != null &&
                                    !widget.ownIds.contains(e.id)
                                ? Text(l.arrEpisodeHasFile)
                                : null,
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
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.pop(context, _picked),
          child: Text(l.commonDone),
        ),
      ],
    );
  }
}

/// A field that opens a picker: its label, and the choice or a prompt.
class _PickerField extends StatelessWidget {
  final String label;
  final String? value;
  final String empty;
  final VoidCallback? onTap;
  const _PickerField({
    required this.label,
    required this.value,
    required this.empty,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label, style: theme.textTheme.labelLarge),
          ),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: InputDecorator(
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.arrow_drop_down_rounded),
              ),
              child: Text(
                value ?? empty,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: value == null
                    ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The file's languages as chips, with Change to pick them.
class _LanguagesField extends ConsumerWidget {
  final ArrKind kind;
  final List<ArrLanguage>? value;
  final String empty;
  final ValueChanged<List<ArrLanguage>> onChanged;
  const _LanguagesField({
    required this.kind,
    required this.value,
    required this.empty,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final all = ref.watch(arrLanguagesProvider(kind)).asData?.value;
    final chosen = value ?? const <ArrLanguage>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l.arrLanguages, style: theme.textTheme.labelLarge),
              ),
              TextButton(
                style: kInlineButtonStyle,
                onPressed: all == null
                    ? null
                    : () async {
                        final picked = await showDialog<List<ArrLanguage>>(
                          context: context,
                          builder: (_) =>
                              _LanguagePicker(all: all, chosen: chosen),
                        );
                        if (picked != null) onChanged(picked);
                      },
                child: Text(l.arrChange),
              ),
            ],
          ),
          if (chosen.isEmpty)
            Text(
              empty,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final lang in chosen)
                  ArrChip(label: lang.name, color: theme.colorScheme.primary),
              ],
            ),
        ],
      ),
    );
  }
}

/// Every language, searchable, to tick the ones a file has.
class _LanguagePicker extends StatefulWidget {
  final List<ArrLanguage> all;
  final List<ArrLanguage> chosen;
  const _LanguagePicker({required this.all, required this.chosen});

  @override
  State<_LanguagePicker> createState() => _LanguagePickerState();
}

class _LanguagePickerState extends State<_LanguagePicker> {
  late final Set<int> _picked = {for (final l in widget.chosen) l.id};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final q = _q.trim().toLowerCase();
    // Ticked ones first, so they're easy to untick.
    final shown = [
      for (final lang in widget.all)
        if (q.isEmpty || lang.name.toLowerCase().contains(q)) lang,
    ]..sort((a, b) {
        final pa = _picked.contains(a.id), pb = _picked.contains(b.id);
        if (pa != pb) return pa ? -1 : 1;
        return 0;
      });
    return AlertDialog(
      title: Text(l.arrLanguages),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 400,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: l.commonSearch,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  for (final lang in shown)
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      value: _picked.contains(lang.id),
                      title: Text(lang.name),
                      onChanged: (v) => setState(
                        () => v == true
                            ? _picked.add(lang.id)
                            : _picked.remove(lang.id),
                      ),
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
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.pop(context, [
                  for (final lang in widget.all)
                    if (_picked.contains(lang.id)) lang,
                ]),
          child: Text(l.commonDone),
        ),
      ],
    );
  }
}

/// Picks a show or movie from the library by name. Returns its id.
Future<int?> _pickTitle<T>(
  BuildContext context, {
  required String hint,
  required List<T> items,
  required String Function(T) label,
  required int? Function(T) year,
  required int Function(T) id,
}) => showDialog<int>(
  context: context,
  builder: (context) => _TitlePicker<T>(
    hint: hint,
    items: items,
    label: label,
    year: year,
    id: id,
  ),
);

class _TitlePicker<T> extends StatefulWidget {
  final String hint;
  final List<T> items;
  final String Function(T) label;
  final int? Function(T) year;
  final int Function(T) id;
  const _TitlePicker({
    required this.hint,
    required this.items,
    required this.label,
    required this.year,
    required this.id,
  });

  @override
  State<_TitlePicker<T>> createState() => _TitlePickerState<T>();
}

class _TitlePickerState<T> extends State<_TitlePicker<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final q = _q.trim().toLowerCase();
    final shown = [
      for (final t in widget.items)
        if (q.isEmpty || widget.label(t).toLowerCase().contains(q)) t,
    ]..sort(
        (a, b) => widget.label(a).toLowerCase().compareTo(
          widget.label(b).toLowerCase(),
        ),
      );
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 420,
        height: 460,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: widget.hint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: shown.isEmpty
                  ? Center(child: Text(l.arrNoMatches))
                  : ListView(
                      children: [
                        for (final t in shown)
                          ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            title: Text(widget.label(t)),
                            trailing: widget.year(t) == null
                                ? null
                                : Text(
                                    '${widget.year(t)}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                            onTap: () => Navigator.pop(context, widget.id(t)),
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
