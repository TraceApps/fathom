import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/base_item.dart';
import 'providers.dart';
import 'session_controller.dart';
import '../api/jellyfin_client.dart';

typedef _JsonList = List<Map<String, dynamic>>;

final adminUsersProvider = FutureProvider.autoDispose<_JsonList>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const [];
  return ref
      .watch(jellyfinClientProvider)
      .getUsers(baseUrl: s.baseUrl, token: s.accessToken);
});

final adminLibrariesProvider =
    FutureProvider.autoDispose<_JsonList>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const [];
  return ref
      .watch(jellyfinClientProvider)
      .getVirtualFolders(baseUrl: s.baseUrl, token: s.accessToken);
});

final adminServerConfigProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const {};
  return ref
      .watch(jellyfinClientProvider)
      .getServerConfiguration(baseUrl: s.baseUrl, token: s.accessToken);
});

final adminNetworkConfigProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const {};
  return ref.watch(jellyfinClientProvider).getNamedConfiguration(
      baseUrl: s.baseUrl, token: s.accessToken, key: 'network');
});

final adminEncodingConfigProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const {};
  return ref.watch(jellyfinClientProvider).getNamedConfiguration(
      baseUrl: s.baseUrl, token: s.accessToken, key: 'encoding');
});

/// The server's backups; null when it has no backup API (before Jellyfin 12).
final adminBackupsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>?>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const [];
  return ref
      .watch(jellyfinClientProvider)
      .getBackups(baseUrl: s.baseUrl, token: s.accessToken);
});

final adminApiKeysProvider = FutureProvider.autoDispose<_JsonList>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const [];
  return ref
      .watch(jellyfinClientProvider)
      .getApiKeys(baseUrl: s.baseUrl, token: s.accessToken);
});

final adminPackagesProvider = FutureProvider.autoDispose<_JsonList>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const [];
  return ref
      .watch(jellyfinClientProvider)
      .getPackages(baseUrl: s.baseUrl, token: s.accessToken);
});

final adminRepositoriesProvider =
    FutureProvider.autoDispose<_JsonList>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const [];
  return ref
      .watch(jellyfinClientProvider)
      .getRepositories(baseUrl: s.baseUrl, token: s.accessToken);
});

/// The server's Live TV setup: tuners, guide providers, recording paths.
///
/// This reads the `livetv` configuration section, NOT /LiveTv/Info. That
/// endpoint returns LiveTvInfo — {Services, IsEnabled, EnabledUsers} — and has
/// never carried TunerHosts or ListingProviders, so reading them from it
/// silently yielded an empty list and hid whatever was already set up on the
/// server. TunerHosts has no GET of its own; this section is the only read.
final adminLiveTvInfoProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const {};
  return ref.watch(jellyfinClientProvider).getNamedConfiguration(
      baseUrl: s.baseUrl, token: s.accessToken, key: 'livetv');
});

final adminTimersProvider = FutureProvider.autoDispose<_JsonList>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const [];
  return ref
      .watch(jellyfinClientProvider)
      .getTimers(baseUrl: s.baseUrl, token: s.accessToken);
});

/// Whether a given program has a recording timer, for the passive REC badge
/// shown while watching a live channel. Derives from [adminTimersProvider], so
/// starting or stopping a recording (which invalidates that) updates the badge.
final programRecordingProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, programId) async {
  final timers = await ref.watch(adminTimersProvider.future);
  return timers.any((t) => '${t['ProgramId']}' == programId);
});

final adminSeriesTimersProvider =
    FutureProvider.autoDispose<_JsonList>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const [];
  return ref
      .watch(jellyfinClientProvider)
      .getSeriesTimers(baseUrl: s.baseUrl, token: s.accessToken);
});

final adminRecordingsProvider =
    FutureProvider.autoDispose<List<BaseItemDto>>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const [];
  return ref.watch(jellyfinClientProvider).getRecordings(
      baseUrl: s.baseUrl, token: s.accessToken, userId: s.userId);
});

final adminDevicesProvider = FutureProvider.autoDispose<_JsonList>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const [];
  return ref
      .watch(jellyfinClientProvider)
      .getDevices(baseUrl: s.baseUrl, token: s.accessToken);
});

final adminLogFilesProvider = FutureProvider.autoDispose<_JsonList>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const [];
  return ref
      .watch(jellyfinClientProvider)
      .getLogFiles(baseUrl: s.baseUrl, token: s.accessToken);
});

final adminPluginsProvider = FutureProvider.autoDispose<_JsonList>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const [];
  return ref
      .watch(jellyfinClientProvider)
      .getPlugins(baseUrl: s.baseUrl, token: s.accessToken);
});

final adminTasksProvider = FutureProvider.autoDispose<_JsonList>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const [];
  final tasks = await ref
      .watch(jellyfinClientProvider)
      .getScheduledTasks(baseUrl: s.baseUrl, token: s.accessToken);
  // While one is running (one just started, or the server's own schedule),
  // look again every few seconds: its progress moves, and when it's done the
  // row says so. It stayed on "Running" until the page was opened again.
  if (tasks.any((t) => '${t['State']}' == 'Running' || '${t['State']}' == 'Cancelling')) {
    final again = Timer(const Duration(seconds: 3), ref.invalidateSelf);
    ref.onDispose(again.cancel);
  }
  return tasks;
});

final adminSessionsProvider =
    FutureProvider.autoDispose<_JsonList>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const [];
  return ref
      .watch(jellyfinClientProvider)
      .getSessions(baseUrl: s.baseUrl, token: s.accessToken);
});

final adminActivityProvider =
    FutureProvider.autoDispose<_JsonList>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const [];
  return ref
      .watch(jellyfinClientProvider)
      .getActivityLog(baseUrl: s.baseUrl, token: s.accessToken);
});

final adminSystemProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return const {};
  return ref
      .watch(jellyfinClientProvider)
      .getSystemInfo(baseUrl: s.baseUrl, token: s.accessToken);
});
