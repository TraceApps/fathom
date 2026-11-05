import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/arr_client.dart';
import '../models/arr.dart';
import 'preferences.dart';

/// The Sonarr server, when one is connected (an address and an API key).
final sonarrClientProvider = Provider<SonarrClient?>((ref) {
  final c = ref.watch(
    preferencesProvider.select((p) {
      final v = p.asData?.value;
      return (v?.sonarrUrl ?? '', v?.sonarrApiKey ?? '');
    }),
  );
  if (c.$1.isEmpty || c.$2.isEmpty) return null;
  return SonarrClient(c.$1, c.$2);
});

/// The Radarr server, when one is connected.
final radarrClientProvider = Provider<RadarrClient?>((ref) {
  final c = ref.watch(
    preferencesProvider.select((p) {
      final v = p.asData?.value;
      return (v?.radarrUrl ?? '', v?.radarrApiKey ?? '');
    }),
  );
  if (c.$1.isEmpty || c.$2.isEmpty) return null;
  return RadarrClient(c.$1, c.$2);
});

/// Whether the Arr section shows: Sonarr, Radarr or both connected.
final arrConfiguredProvider = Provider<bool>(
  (ref) =>
      ref.watch(sonarrClientProvider) != null ||
      ref.watch(radarrClientProvider) != null,
);

/// Results gathered from both apps. One app being unreachable doesn't hide
/// the other's: its error is kept beside what did arrive.
class ArrMerged<T> {
  final List<T> items;
  final Map<ArrKind, String> errors;
  const ArrMerged(this.items, this.errors);
}

Future<ArrMerged<T>> _both<T>(
  SonarrClient? sonarr,
  RadarrClient? radarr,
  Future<List<T>> Function(ArrClient c) load,
) async {
  final items = <T>[];
  final errors = <ArrKind, String>{};
  await Future.wait([
    for (final c in <ArrClient?>[sonarr, radarr])
      if (c != null)
        load(c).then(items.addAll).catchError((Object e) {
          errors[c.kind] = e.toString();
        }),
  ]);
  return ArrMerged(items, errors);
}

/// The calendar window: from the start of yesterday, four weeks ahead.
({DateTime start, DateTime end}) arrCalendarWindow(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  return (
    start: today.subtract(const Duration(days: 1)),
    end: today.add(const Duration(days: 29)),
  );
}

final arrCalendarProvider =
    FutureProvider.autoDispose<ArrMerged<ArrCalendarEntry>>((ref) async {
      final w = arrCalendarWindow(DateTime.now());
      final merged = await _both<ArrCalendarEntry>(
        ref.watch(sonarrClientProvider),
        ref.watch(radarrClientProvider),
        (c) => c.calendar(w.start, w.end),
      );
      merged.items.sort((a, b) => a.date.compareTo(b.date));
      return merged;
    });

final arrQueueProvider = FutureProvider.autoDispose<ArrMerged<ArrQueueItem>>((
  ref,
) async {
  final merged = await _both<ArrQueueItem>(
    ref.watch(sonarrClientProvider),
    ref.watch(radarrClientProvider),
    (c) => c.queue(),
  );
  // Problems first, then the closest to finishing.
  merged.items.sort((a, b) {
    if (a.hasProblem != b.hasProblem) return a.hasProblem ? -1 : 1;
    return b.progress.compareTo(a.progress);
  });
  return merged;
});

final radarrMoviesProvider = FutureProvider.autoDispose<List<ArrMovie>>((
  ref,
) async {
  final c = ref.watch(radarrClientProvider);
  if (c == null) return const [];
  return c.movies();
});

final sonarrSeriesListProvider = FutureProvider.autoDispose<List<ArrSeries>>((
  ref,
) async {
  final c = ref.watch(sonarrClientProvider);
  if (c == null) return const [];
  return c.series();
});

/// Quality profile names by id, for one app.
final arrQualityProfilesProvider = FutureProvider.autoDispose
    .family<Map<int, String>, ArrKind>((ref, kind) async {
      final ArrClient? c = kind == ArrKind.sonarr
          ? ref.watch(sonarrClientProvider)
          : ref.watch(radarrClientProvider);
      if (c == null) return const {};
      try {
        return {for (final p in await c.qualityProfiles()) p.id: p.name};
      } catch (_) {
        return const {};
      }
    });

final radarrMovieProvider = FutureProvider.autoDispose.family<ArrMovie, int>((
  ref,
  id,
) async {
  final c = ref.watch(radarrClientProvider);
  if (c == null) throw ArrException('Radarr is not connected.');
  return c.movie(id);
});

final radarrMovieHistoryProvider = FutureProvider.autoDispose
    .family<List<ArrHistoryItem>, int>((ref, id) async {
      final c = ref.watch(radarrClientProvider);
      if (c == null) return const [];
      return c.history(id);
    });

final sonarrSeriesProvider = FutureProvider.autoDispose.family<ArrSeries, int>((
  ref,
  id,
) async {
  final c = ref.watch(sonarrClientProvider);
  if (c == null) throw ArrException('Sonarr is not connected.');
  return c.seriesById(id);
});

final sonarrEpisodesProvider = FutureProvider.autoDispose
    .family<List<ArrEpisode>, int>((ref, seriesId) async {
      final c = ref.watch(sonarrClientProvider);
      if (c == null) return const [];
      return c.episodes(seriesId);
    });

final sonarrEpisodeFilesProvider = FutureProvider.autoDispose
    .family<Map<int, ArrFile>, int>((ref, seriesId) async {
      final c = ref.watch(sonarrClientProvider);
      if (c == null) return const {};
      return {for (final f in await c.episodeFiles(seriesId)) f.id: f};
    });

final sonarrSeriesHistoryProvider = FutureProvider.autoDispose
    .family<List<ArrHistoryItem>, int>((ref, seriesId) async {
      final c = ref.watch(sonarrClientProvider);
      if (c == null) return const [];
      return c.history(seriesId);
    });

ArrClient? arrClientOf(Ref ref, ArrKind kind) => kind == ArrKind.sonarr
    ? ref.watch(sonarrClientProvider)
    : ref.watch(radarrClientProvider);

/// The client for [kind], read once (for actions, not for rebuilding).
ArrClient? arrClient(WidgetRef ref, ArrKind kind) => kind == ArrKind.sonarr
    ? ref.read(sonarrClientProvider)
    : ref.read(radarrClientProvider);

/// Root folders for one app, for adding a title.
final arrRootFoldersProvider = FutureProvider.autoDispose
    .family<List<ArrRootFolder>, ArrKind>((ref, kind) async {
      final c = arrClientOf(ref, kind);
      if (c == null) return const [];
      return c.rootFolders();
    });

/// Quality profiles for one app, in the app's order, for pickers.
final arrQualityProfileListProvider = FutureProvider.autoDispose
    .family<List<ArrQualityProfile>, ArrKind>((ref, kind) async {
      final c = arrClientOf(ref, kind);
      if (c == null) return const [];
      return c.qualityProfiles();
    });

/// After a change to a movie: everything that shows it reloads.
void arrMovieChanged(WidgetRef ref, int id) {
  ref.invalidate(radarrMovieProvider(id));
  ref.invalidate(radarrMovieHistoryProvider(id));
  ref.invalidate(radarrMoviesProvider);
  ref.invalidate(arrCalendarProvider);
}

/// After a change to a show: everything that shows it reloads.
void arrSeriesChanged(WidgetRef ref, int id) {
  ref.invalidate(sonarrSeriesProvider(id));
  ref.invalidate(sonarrEpisodesProvider(id));
  ref.invalidate(sonarrEpisodeFilesProvider(id));
  ref.invalidate(sonarrSeriesHistoryProvider(id));
  ref.invalidate(sonarrSeriesListProvider);
  ref.invalidate(arrCalendarProvider);
}
