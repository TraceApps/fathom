import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/error_text.dart';
import '../l10n/generated/app_localizations.dart';
import '../routing/app_shell.dart';
import '../services/tv_mode.dart';
import '../state/playlist_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_view.dart';
import '../widgets/media_cards.dart';
import '../widgets/motion.dart';
import '../widgets/shimmer.dart';
import '../widgets/tv_keyboard.dart';
import '../widgets/app_snack.dart';
import '../api/jellyfin_client.dart';

/// Lists the user's playlists and lets them create a new (empty) one.
class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.appNewPlaylist),
        content: TvTextField(
          controller: controller,
          autofocus: true,
          label: l.appPlaylistName,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(l.appCreate)),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await ref.read(jellyfinClientProvider).createPlaylist(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
            name: name,
          );
      ref.invalidate(playlistsProvider);
      showSnackOn(messenger, l.appCreatedNamed(name), kind: SnackKind.success);
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final async = ref.watch(playlistsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: mobileLeading(context),
        title: Text(l.appPlaylists),
        actions: [
          IconButton(
            tooltip: l.appNewPlaylist,
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _create(context, ref),
          ),
        ],
      ),
      body: async.when(
        loading: () => const PosterGridSkeleton(aspectRatio: 0.62),
        error: (e, _) => ErrorView(message: errorText(e), onRetry: () => ref.invalidate(playlistsProvider)),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.playlist_play_rounded,
              title: l.appNoPlaylists,
              message: l.appNoPlaylistsMessage,
              action: FilledButton.icon(
                onPressed: () => _create(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: Text(l.appNewPlaylist),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(playlistsProvider),
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 184,
                mainAxisSpacing: 18,
                crossAxisSpacing: 14,
                childAspectRatio: 0.62,
              ),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final p = list[i];
                return EntranceFade(
                  index: i,
                  onceKey: p.id,
                  child: PosterTile(
                    item: p,
                    autofocus: isTvDevice && i == 0,
                    onTap: () => context.push('/playlist', extra: p),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
