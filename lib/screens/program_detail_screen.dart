import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../widgets/cached_image.dart';
import '../widgets/hover_pill_button.dart';
import '../models/base_item.dart';
import '../services/image_cache.dart';
import '../state/library_providers.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import '../widgets/record_dialog.dart';
import '../widgets/app_snack.dart';
import '../api/jellyfin_client.dart';
import '../widgets/format.dart';

typedef ProgramArgs = ({BaseItemDto channel, BaseItemDto program, bool isNow});

/// Re-fetches a single program WITH its images. The guide grid requests programs
/// with images off (for speed), so `args.program` carries no artwork; this pulls
/// the program's real Primary/Backdrop art on demand for the detail banner.
final _programArtProvider =
    FutureProvider.autoDispose.family<BaseItemDto?, String>((ref, id) async {
  final s = ref.watch(sessionControllerProvider).asData?.value;
  if (s == null) return null;
  try {
    return await ref.watch(jellyfinClientProvider).getItem(
        baseUrl: s.baseUrl, userId: s.userId, token: s.accessToken, itemId: id);
  } catch (_) {
    return null;
  }
});

/// Details for a single EPG program: title, channel/time, overview, and watch /
/// record actions. A pushed route (modals don't display from the guide grid).
class ProgramDetailScreen extends ConsumerWidget {
  final ProgramArgs args;
  const ProgramDetailScreen({super.key, required this.args});

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final session = ref.read(sessionControllerProvider).asData?.value;
    if (session == null || args.program.timerId == null) return;
    final client = ref.read(jellyfinClientProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await client.cancelTimer(
          baseUrl: session.baseUrl,
          token: session.accessToken,
          timerId: args.program.timerId!);
      ref.invalidate(guideProvider);
      ref.invalidate(recordingsProvider);
      if (context.mounted) {
        showSnackOn(messenger, l.detailRecordingCanceled);
        context.pop();
      }
    } catch (e) {
      showErrorOn(messenger, e);
    }
  }

  static String _range(BuildContext context, DateTime? a, DateTime? b) {
    if (a == null || b == null) return '';
    return '${clockTime(context, a)} – ${clockTime(context, b)}';
  }

  static double? _progress(DateTime? start, DateTime? end) {
    if (start == null || end == null) return null;
    final total = end.difference(start).inSeconds;
    if (total <= 0) return null;
    return (DateTime.now().difference(start).inSeconds / total)
        .clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = args.program;
    final scheduled = p.timerId != null;
    // The guide fetch omits images, so pull the program's real art on demand;
    // fall back to args.program until it resolves. The banner reserves its 16:9
    // box only when the image actually loads — many EPG programs advertise an
    // image tag whose URL then 500s on the server, and a full-width placeholder
    // box just wastes the screen (worse on desktop). The live progress bar shows
    // as a slim standalone bar regardless.
    final art = ref.watch(_programArtProvider(p.id)).asData?.value ?? p;
    final prog = args.isNow ? _progress(p.startDate, p.endDate) : null;

    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      // Keep the content in a readable centered column rather than stretching it
      // edge-to-edge across a wide desktop window.
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          // Program artwork banner. It renders the 16:9 box only if the image
          // truly loads, and collapses to nothing on a load failure so a broken
          // image never leaves an empty placeholder box behind.
          _ProgramBanner(art: art),
          Text(p.name,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          if (p.episodeTitle != null && p.episodeTitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(p.episodeTitle!,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 6),
          Text('${args.channel.name}  ·  ${_range(context, p.startDate, p.endDate)}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          // Live progress as a slim standalone bar under the channel/time line.
          if (prog != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: prog,
                minHeight: 5,
                backgroundColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
              ),
            ),
          ],
          if (p.overview != null && p.overview!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(p.overview!,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
          ],
          if (p.genres.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in p.genres)
                  Chip(
                    label: Text(g),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              HoverPillButton(
                primary: true,
                icon: args.isNow
                    ? Icons.play_arrow_rounded
                    : Icons.live_tv_rounded,
                label: args.isNow ? l.detailWatchNow : l.detailWatchChannel,
                onTap: () => context.push('/player', extra: args.channel),
              ),
              if (scheduled)
                HoverPillButton(
                  color: Colors.redAccent,
                  icon: Icons.cancel_rounded,
                  label: l.detailCancelRecording,
                  onTap: () => _cancel(context, ref),
                )
              else
                HoverPillButton(
                  color: Colors.redAccent,
                  icon: Icons.fiber_manual_record_rounded,
                  label: l.detailRecord,
                  onTap: () => showRecordDialog(context, ref,
                      programId: p.id, allowSeries: true),
                ),
            ],
          ),
        ],
          ),
        ),
      ),
    );
  }
}

/// The 16:9 program artwork banner that only occupies space once its image is
/// actually decoded. EPG programs frequently advertise a Primary/Backdrop tag
/// whose URL then 500s on the server; rather than reserve an empty box (or flash
/// a skeleton) while it loads or fails, this shows nothing until the image is
/// truly ready and the box simply pops in on success.
class _ProgramBanner extends ConsumerWidget {
  final BaseItemDto art;
  const _ProgramBanner({required this.art});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Landscape pick for a banner: a real Backdrop first, else the Primary tag.
    final String type;
    final String? tag;
    if (art.backdropImageTags.isNotEmpty) {
      type = 'Backdrop';
      tag = art.backdropImageTags.first;
    } else if (art.primaryImageTag != null) {
      type = 'Primary';
      tag = art.primaryImageTag;
    } else {
      return const SizedBox.shrink();
    }

    final session = ref.watch(sessionControllerProvider).asData?.value;
    if (session == null) return const SizedBox.shrink();
    final client = ref.watch(jellyfinClientProvider);
    final headers = ref.watch(imageHeadersProvider);

    final url = client.imageUrl(
      baseUrl: session.baseUrl,
      itemId: art.id,
      type: type,
      tag: tag,
      maxWidth: 960,
    );

    // imageBuilder fires only after a successful decode, so the 16:9 box (and
    // its bottom spacing) exists only when there's real art to fill it. While
    // loading and on failure we render nothing at all.
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: fathomImageCache,
      httpHeaders: headers,
      fadeInDuration: const Duration(milliseconds: 180),
      placeholder: (_, _) => const SizedBox.shrink(),
      // A saved copy that can't be read is thrown out, so the next visit
      // fetches it again.
      errorListener: (_) => forgetBrokenImage(url),
      errorWidget: (_, _, _) => const SizedBox.shrink(),
      imageBuilder: (context, imageProvider) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Image(
              image: imageProvider,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
        ),
      ),
    );
  }
}
