import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../l10n/generated/app_localizations.dart';
import '../models/seerr_result.dart';
import '../theme/app_theme.dart';
import 'cached_image.dart';
import 'context_menu.dart';
import 'media_cards.dart';
import 'seerr_request_dialog.dart';
import 'app_spinner.dart';

// Jellyseerr's card colours: blue for movies, purple for series, green for
// available, amber for requested/partial.
const seerrMovieColor = Color(0xFF3B82F6);
const seerrSeriesColor = Color(0xFF8B5CF6);
const seerrAvailableColor = Color(0xFF22C55E);
const seerrPendingColor = Color(0xFFF59E0B);

/// Fixed-width Seerr poster, for horizontal rows.
class SeerrPosterCard extends StatelessWidget {
  final SeerrResult result;
  const SeerrPosterCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The art flexes rather than pinning a 2:3 box: in a fixed-height row, the
    // title takes its space first and the poster absorbs the rest, so a
    // two-line title can't push the column past the row height.
    return SizedBox(
      width: 176,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: HoverPosterArt(
              onTap: () => context.push('/seerr-detail', extra: result),
              art: result.posterUrl != null
                  ? CachedImage(
                      url: result.posterUrl!,
                      cacheWidth: 220,
                      errorBuilder: (_) => _phBox(theme))
                  : _phBox(theme),
              overlay: SeerrCorners(result: result),
              hoverOverlay: result.canRequest
                  ? SeerrHoverRequestButton(result: result)
                  : null,
              onMenu: (at) => showSeerrPosterMenu(context, at, result),
            ),
          ),
          const SizedBox(height: 6),
          Text(result.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _phBox(ThemeData theme) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.movie_rounded,
            color: theme.colorScheme.onSurfaceVariant),
      );
}

/// A Discover poster's long-press / right-click menu, as every other poster
/// in the app has one: open it, or request it without opening it. A finger
/// has no hover, so this is its way to the Request button.
Future<void> showSeerrPosterMenu(
  BuildContext context,
  Offset at,
  SeerrResult result,
) {
  final l = AppLocalizations.of(context);
  return showContextMenu(
    context,
    at: at,
    title: result.title,
    actions: [
      ContextMenuAction(
        icon: Icons.info_outline_rounded,
        label: l.browseDetails,
        onTap: () => context.push('/seerr-detail', extra: result),
      ),
      if (result.canRequest)
        ContextMenuAction(
          icon: Icons.download_rounded,
          label: l.detailRequest,
          onTap: () => showSeerrRequestDialog(context, result),
        ),
    ],
  );
}

/// Flexible-height Seerr poster, for grids.
class SeerrGridCard extends StatelessWidget {
  final SeerrResult result;
  const SeerrGridCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: HoverPosterArt(
            onTap: () => context.push('/seerr-detail', extra: result),
            art: result.posterUrl != null
                ? CachedImage(
                url: result.posterUrl!,
                cacheWidth: 220,
                errorBuilder: (_) => _ph(theme))
                : _ph(theme),
            overlay: SeerrCorners(result: result),
            hoverOverlay: result.canRequest
                ? SeerrHoverRequestButton(result: result)
                : null,
            onMenu: (at) => showSeerrPosterMenu(context, at, result),
          ),
        ),
        const SizedBox(height: 6),
        Text(result.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _ph(ThemeData theme) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(Icons.movie_rounded,
            color: theme.colorScheme.onSurfaceVariant),
      );
}

/// A person result from search: a circular photo that opens their page, with
/// the same lift-and-ring hover as cast cards.
class SeerrPersonSearchCard extends StatefulWidget {
  final SeerrResult person; // mediaType == 'person'
  const SeerrPersonSearchCard({super.key, required this.person});

  @override
  State<SeerrPersonSearchCard> createState() => _SeerrPersonSearchCardState();
}

class _SeerrPersonSearchCardState extends State<SeerrPersonSearchCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.person;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.push('/seerr-person', extra: p.tmdbId),
        child: Column(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: AnimatedScale(
                  scale: _hover ? 1.06 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _hover
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: CircleAvatar(
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      foregroundImage: p.posterUrl != null
                          ? NetworkImage(p.posterUrl!)
                          : null,
                      child: p.posterUrl == null
                          ? const Icon(Icons.person_rounded, size: 40)
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(p.title,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

/// The corner markers on a Seerr poster, matching the official app: a
/// MOVIE/SERIES type badge top-left, and a status circle top-right.
class SeerrCorners extends StatelessWidget {
  final SeerrResult result;
  const SeerrCorners({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final isTv = result.mediaType == 'tv';
    return Stack(
      children: [
        Positioned(
          top: 6,
          left: 6,
          child: _Badge(
            text: isTv ? 'SERIES' : 'MOVIE',
            color: isTv ? seerrSeriesColor : seerrMovieColor,
          ),
        ),
        if (result.isAvailable)
          const Positioned(
            top: 6,
            right: 6,
            child: _StatusDot(
                color: seerrAvailableColor, icon: Icons.download_done_rounded),
          )
        else if (result.isRequested)
          const Positioned(
            top: 6,
            right: 6,
            child: _StatusDot(
                color: seerrPendingColor, icon: Icons.schedule_rounded),
          ),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  final IconData icon;
  const _StatusDot({required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration:
          BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 4),
      ]),
      child: Icon(icon, size: 15, color: Colors.white),
    );
  }
}

/// The Request button revealed on hover, for a title that's neither requested
/// nor available. Opens Jellyseerr's confirm-and-configure dialog.
class SeerrHoverRequestButton extends ConsumerStatefulWidget {
  final SeerrResult result;
  const SeerrHoverRequestButton({super.key, required this.result});

  @override
  ConsumerState<SeerrHoverRequestButton> createState() =>
      _SeerrHoverRequestButtonState();
}

class _SeerrHoverRequestButtonState
    extends ConsumerState<SeerrHoverRequestButton> {
  bool _busy = false;
  bool _done = false;

  Future<void> _request() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await showSeerrRequestDialog(context, widget.result);
    if (mounted) {
      setState(() {
        _busy = false;
        if (ok) _done = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(6),
      child: FilledButton.icon(
        onPressed: _done ? null : _request,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(34),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(
              fontFamily: kAppFontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w700),
        ),
        icon: _busy
            ? AppSpinner.inline()
            : Icon(_done ? Icons.check_rounded : Icons.download_rounded,
                size: 16),
        label: Text(_done ? l.browseRequested : l.detailRequest),
      ),
    );
  }
}
