import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/tv_mode.dart';
import '../state/preferences.dart';
import '../state/updates.dart';
import '../theme/app_theme.dart';

/// A floating, dismissible card near the top of the app when a newer release is
/// available, mirroring the TraceApps update banner: an accent-tinted rounded
/// card (icon, headline + CTA subtitle, a View button, and a close), fading in
/// over the content. Complements the persistent nav-rail indicator (which stays,
/// so the reminder isn't lost after a dismiss). Renders nothing when up to date,
/// dismissed for this version, or on TV. Meant to overlay the content Stack.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isTvDevice) return const SizedBox.shrink();
    final status = ref.watch(updateControllerProvider).asData?.value;
    if (status == null || !status.updateAvailable) return const SizedBox.shrink();
    final prefs = ref.watch(preferencesProvider).asData?.value;
    final version = status.latest!.version;
    if (prefs != null && prefs.updateBannerDismissedVersion == version) {
      return const SizedBox.shrink();
    }

    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    void dismiss() => ref
        .read(preferencesProvider.notifier)
        .edit((p) => p.copyWith(updateBannerDismissedVersion: version));

    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        // Accent-tinted surface + accent border, like TraceApps'
        // color-mix(accent 15%, surface) / color-mix(accent 30%, border).
        color: Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.15), scheme.surface),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.system_update_rounded, color: scheme.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.updateAvailableHeadline(version),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  l.updateBannerCta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: const Size(0, 36),
              textStyle: const TextStyle(
                  fontFamily: kAppFontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            onPressed: () {
              context.push('/updates');
              dismiss();
            },
            child: Text(l.updateBannerAction),
          ),
          IconButton(
            tooltip: l.updateBannerDismiss,
            iconSize: 20,
            color: scheme.onSurfaceVariant,
            icon: const Icon(Icons.close_rounded),
            onPressed: dismiss,
          ),
        ],
      ),
    );

    // Float the card at the top with margins, over the content, and fade it in.
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          // Edge-to-edge across the content width with a small inset, like the
          // TraceApps banner (no max-width cap).
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 200),
            builder: (_, t, child) => Opacity(opacity: t, child: child),
            child: Material(color: Colors.transparent, child: card),
          ),
        ),
      ),
    );
  }
}
