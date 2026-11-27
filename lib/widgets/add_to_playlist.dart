import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/error_text.dart';
import '../l10n/generated/app_localizations.dart';
import '../state/playlist_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import 'tv_keyboard.dart';
import 'app_snack.dart';
import 'app_spinner.dart';
import '../api/jellyfin_client.dart';

/// Shows a sheet to add [itemIds] to an existing playlist or a new one.
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  WidgetRef ref, {
  required List<String> itemIds,
  required String label,
}) {
  return showModalBottomSheet<void>(
    context: context,
      useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _AddToPlaylistSheet(itemIds: itemIds, label: label),
  );
}

class _AddToPlaylistSheet extends ConsumerWidget {
  final List<String> itemIds;
  final String label;
  const _AddToPlaylistSheet({required this.itemIds, required this.label});

  Future<void> _addTo(BuildContext context, WidgetRef ref, String playlistId,
      String playlistName) async {
    final l = AppLocalizations.of(context);
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(jellyfinClientProvider).addToPlaylist(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
            playlistId: playlistId,
            itemIds: itemIds,
          );
      ref.invalidate(playlistsProvider);
      ref.invalidate(playlistItemsProvider(playlistId));
      if (context.mounted) Navigator.pop(context);
      showSnackOn(messenger, l.appAddedToNamed(playlistName),
          kind: SnackKind.success);
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  Future<void> _createNew(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: label);
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
    if (!isPlaylistNameFree(name)) {
      showSnackOn(messenger, l.errPlaylistNameReserved, kind: SnackKind.error);
      return;
    }
    try {
      await ref.read(jellyfinClientProvider).createPlaylist(
            baseUrl: session.baseUrl,
            userId: session.userId,
            token: session.accessToken,
            name: name,
            itemIds: itemIds,
          );
      ref.invalidate(playlistsProvider);
      if (context.mounted) Navigator.pop(context);
      showSnackOn(messenger, l.appCreatedNamed(name), kind: SnackKind.success);
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final playlists = ref.watch(playlistsProvider);
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.appAddToPlaylist,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: const Icon(Icons.add_rounded),
              ),
              title: Text(l.appNewPlaylist),
              onTap: () => _createNew(context, ref),
            ),
            const Divider(height: 8),
            Flexible(
              child: playlists.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: AppSpinner()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(errorText(e),
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
                data: (list) => list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(l.appNoPlaylistsYet),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final p in list)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(
                                  child: Icon(Icons.playlist_play_rounded)),
                              title: Text(p.name),
                              subtitle: p.childCount != null
                                  ? Text(l.appItemsCount(p.childCount!))
                                  : null,
                              onTap: () =>
                                  _addTo(context, ref, p.id, p.name),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
