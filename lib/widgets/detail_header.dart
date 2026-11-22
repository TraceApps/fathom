import 'package:flutter/material.dart';

import '../services/tv_mode.dart';

/// A circular action button for the detail header, over the backdrop. At rest
/// it's an icon-only circle (accent for the primary action, translucent dark
/// for the rest); on hover it expands into a pill that reveals the label beside
/// the icon.
class HeaderActionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;

  /// The word shown when the button expands on hover; defaults to [tooltip].
  final String? label;
  final VoidCallback? onTap;
  final bool primary;

  /// Grabs focus on mount — used on Android TV so the hero's Play button is the
  /// D-pad landing spot when a browse screen opens.
  final bool autofocus;

  /// An external focus node, so the detail screen can pull the remote back onto
  /// this button (its UP-from-body handler focuses the header Play).
  final FocusNode? focusNode;

  /// Replaces the icon (e.g. a progress spinner).
  final Widget? iconOverride;

  const HeaderActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.label,
    this.onTap,
    this.primary = false,
    this.autofocus = false,
    this.focusNode,
    this.iconOverride,
  });

  @override
  State<HeaderActionButton> createState() => _HeaderActionButtonState();
}

class _HeaderActionButtonState extends State<HeaderActionButton>
    with SingleTickerProviderStateMixin {
  bool _hover = false;
  // Touch has no hover, so a press (and hold) expands the label instead.
  bool _pressed = false;
  // A D-pad/remote focus reads the same as a mouse hover: the pill expands to
  // show its label and gains an accent ring, so it's obvious which action the
  // remote is on.
  bool _focused = false;
  // Focus ring/expand/scale is a TV (D-pad) affordance; off TV, hover (desktop)
  // or a press (touch) drives the label expand.
  bool get _active => _hover || _pressed || (_focused && isTvDevice);

  // A quick pop on the icon when the button is pressed, for tactile feedback.
  late final AnimationController _tapController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _tapScale = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.32).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40),
    TweenSequenceItem(
        tween: Tween(begin: 1.32, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60),
  ]).animate(_tapController);

  @override
  void dispose() {
    _tapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = widget.onTap != null;
    final h = widget.primary ? 54.0 : 46.0;
    final fg = widget.primary ? scheme.onPrimary : Colors.white;
    final label = widget.label ?? widget.tooltip;
    final icon = ScaleTransition(
      scale: _tapScale,
      child: widget.iconOverride ??
          Icon(widget.icon, size: widget.primary ? 26 : 22, color: fg),
    );

    return Listener(
      // Raw pointer events (not InkWell's deferred highlight) so holding a
      // finger expands the label immediately, even inside a scroll view.
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) {
        if (_pressed) setState(() => _pressed = false);
      },
      onPointerCancel: (_) {
        if (_pressed) setState(() => _pressed = false);
      },
      child: MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: (_focused && isTvDevice) ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color:
              widget.primary ? scheme.primary : Colors.black.withValues(alpha: 0.5),
          shape: StadiumBorder(
            side: (_focused && isTvDevice)
                ? BorderSide(color: scheme.primary, width: 3)
                : widget.primary
                    ? BorderSide.none
                    : BorderSide(color: Colors.white.withValues(alpha: 0.25)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            autofocus: widget.autofocus,
            focusNode: widget.focusNode,
            onFocusChange: (v) => setState(() => _focused = v),
            focusColor: Colors.transparent,
            // Pop on press so the feedback fires even when the tap navigates
            // away a moment later.
            onTapDown:
                enabled ? (_) => _tapController.forward(from: 0) : null,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 170),
              curve: Curves.easeOutCubic,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                height: h,
                child: _active
                    ? Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: widget.primary ? 20 : 18),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            icon,
                            const SizedBox(width: 9),
                            Text(label,
                                style: TextStyle(
                                    color: fg,
                                    fontSize: widget.primary ? 15 : 14,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      )
                    : SizedBox(width: h, child: Center(child: icon)),
              ),
            ),
          ),
        ),
      ),
      ),
      ),
    );
  }
}

/// The shared detail-header overlay: the poster overlapping the bottom-left of
/// the backdrop, with an optional status chip, the title, a meta line
/// (cert badge + type · year · runtime) and the score pills beside it. Used by
/// the Jellyfin and Seerr detail pages so both present the same marquee.
///
/// Sits inside the backdrop Stack; the caller supplies the backdrop image and a
/// scrim behind it for contrast.
class DetailHeaderOverlay extends StatelessWidget {
  /// The poster image (fills its box). Null hides the poster column.
  final Widget? poster;

  /// The title, already styled for a dark backdrop (white text, or a logo).
  final Widget title;

  /// A small chip shown above the title, e.g. Seerr's availability status.
  final Widget? status;

  /// The content-rating badge (R / TV-MA), shown boxed before the meta text.
  final Widget? cert;

  /// "Movie · 2026 · 1h 51m" — the type, year and runtime.
  final String metaLine;

  /// How many lines [metaLine] may take before it's cut short.
  final int metaMaxLines;

  /// Score pills (Rotten Tomatoes, IMDb, community).
  final List<Widget> ratings;

  /// The circular action buttons, shown at the bottom-right over the backdrop.
  final Widget? actions;

  const DetailHeaderOverlay({
    super.key,
    required this.title,
    this.poster,
    this.status,
    this.cert,
    this.metaLine = '',
    this.metaMaxLines = 1,
    this.ratings = const [],
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final hasMeta = metaLine.isNotEmpty || cert != null;
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (poster != null) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(width: 132, height: 198, child: poster),
              ),
            ),
            const SizedBox(width: 18),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (status != null) ...[
                  status!,
                  const SizedBox(height: 8),
                ],
                title,
                if (hasMeta) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (cert != null) ...[
                        cert!,
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          metaLine,
                          maxLines: metaMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            shadows: [
                              Shadow(blurRadius: 6, color: Colors.black87)
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (ratings.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 6, children: ratings),
                ],
              ],
            ),
          ),
          if (actions != null) ...[
            const SizedBox(width: 16),
            actions!,
          ],
        ],
      ),
    );
  }
}
