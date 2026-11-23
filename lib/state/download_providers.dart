import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/download_clients.dart';
import '../models/download_client.dart';
import 'preferences.dart';

/// qBittorrent, when connected. One client for as long as the settings
/// stay the same, so its sign-in is kept between requests.
final qbitClientProvider = Provider<QbitClient?>((ref) {
  final c = ref.watch(
    preferencesProvider.select((p) {
      final v = p.asData?.value;
      return (v?.qbitUrl ?? '', v?.qbitUsername ?? '', v?.qbitPassword ?? '');
    }),
  );
  // A username without its password (as a backup brings it back: the
  // password stays out of backups) would only be refused.
  if (c.$1.isEmpty || (c.$2.isNotEmpty && c.$3.isEmpty)) return null;
  return QbitClient(c.$1, c.$2, c.$3);
});

/// SABnzbd, when connected.
final sabClientProvider = Provider<SabClient?>((ref) {
  final c = ref.watch(
    preferencesProvider.select((p) {
      final v = p.asData?.value;
      return (v?.sabUrl ?? '', v?.sabApiKey ?? '');
    }),
  );
  if (c.$1.isEmpty || c.$2.isEmpty) return null;
  return SabClient(c.$1, c.$2);
});

/// The connected download clients, qBittorrent first.
final downloadClientsProvider = Provider<List<DownloadClient>>(
  (ref) => [?ref.watch(qbitClientProvider), ?ref.watch(sabClientProvider)],
);

/// The connected client of [kind].
DownloadClient? downloadClientOf(Ref ref, DownloadClientKind kind) =>
    switch (kind) {
      DownloadClientKind.qbittorrent => ref.watch(qbitClientProvider),
      DownloadClientKind.sabnzbd => ref.watch(sabClientProvider),
    };

/// A client's downloads and how it's doing, asked again by the page while
/// it shows.
final downloadClientStateProvider = FutureProvider.autoDispose
    .family<DownloadClientState?, DownloadClientKind>((ref, kind) async {
      final c = downloadClientOf(ref, kind);
      if (c == null) return null;
      return c.load();
    });

/// SABnzbd's newest [limit] finished jobs.
final sabHistoryProvider = FutureProvider.autoDispose
    .family<List<DownloadHistoryItem>, int>((ref, limit) async {
      final c = ref.watch(sabClientProvider);
      if (c == null) return const [];
      return c.history(limit: limit);
    });

/// The categories a client has for a new download.
final downloadCategoriesProvider = FutureProvider.autoDispose
    .family<List<String>, DownloadClientKind>((ref, kind) async {
      final c = downloadClientOf(ref, kind);
      if (c == null) return const [];
      return c.categories();
    });
