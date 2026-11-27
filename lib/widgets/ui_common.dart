import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';

/// The section-header label used inside settings and admin forms.
///
/// One definition so the whole app's grouping labels look identical. Previously
/// three styles coexisted (small-uppercase in preferences, large title-case in
/// admin, ad-hoc elsewhere), which read as three different apps. Small,
/// upper-cased, accent-coloured — the settings convention, applied everywhere.
///
/// Distinct from content-row headers (e.g. "Continue Watching"), which are large
/// title-case; this is only for form/settings groups.
class SettingsSectionHeader extends StatelessWidget {
  final String text;

  /// Trims the top gap when the header is the first thing in a list.
  final bool first;

  const SettingsSectionHeader(this.text, {super.key, this.first = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, first ? 8 : 22, 20, 6),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

/// The icon for a Jellyfin library/collection type.
///
/// One mapping so a library shows the same glyph everywhere. The sidebar and
/// the Libraries hub had drifted — a TV Shows library rendered as `tv_rounded`
/// in one and `live_tv_rounded` (the Live TV destination's own icon) in the
/// other. `tv_rounded` is kept for TV Shows so nothing collides with Live TV.
IconData collectionTypeIcon(String? type) => switch (type) {
      'movies' => Icons.movie_rounded,
      'tvshows' => Icons.tv_rounded,
      'music' => Icons.library_music_rounded,
      'musicvideos' => Icons.music_video_rounded,
      'books' => Icons.menu_book_rounded,
      'homevideos' || 'photos' => Icons.photo_library_rounded,
      'boxsets' => Icons.collections_bookmark_rounded,
      'livetv' => Icons.live_tv_rounded,
      'playlists' => Icons.playlist_play_rounded,
      _ => Icons.folder_rounded,
    };

/// The app's one confirmation dialog.
///
/// Returns true only if the user confirmed. Twenty-three of these were written
/// by hand, which is how they drifted: some styled the destructive action red
/// and some didn't, and the confirm button was sometimes the one focus landed
/// on and sometimes not. [destructive] paints the confirm button in the error
/// colour, for anything that deletes or removes.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final l = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          // Focus starts on Cancel for anything destructive, so a stray Enter
          // (or a D-pad OK on TV) can't delete something.
          autofocus: destructive,
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel ?? l.commonCancel),
        ),
        FilledButton(
          autofocus: !destructive,
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Disposes what a dialog's fields were using (text controllers, focus
/// nodes) once the dialog has finished leaving.
///
/// The future from showDialog completes as the dialog STARTS to close; it
/// is still on screen, fading out, for a moment after. Disposing right then
/// broke the screen whenever the dialog redrew during that moment (the
/// keyboard coming back for a field behind it does that): "A
/// TextEditingController was used after being disposed", then a red page.
void disposeAfterDialog(List<ChangeNotifier> used) {
  Future<void>.delayed(const Duration(seconds: 1), () {
    for (final u in used) {
      u.dispose();
    }
  });
}
