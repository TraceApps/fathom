import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/tv_mode.dart';

/// An action that rests as an icon-only pill and expands to reveal its label,
/// with a small pop on press. On desktop it expands on hover; on touch (no
/// hover) it expands while pressed, so a single tap still fires the action.
/// This is the on-a-page counterpart to the detail header/hero's
/// [HeaderActionButton] (which is styled for over an image).
///
/// [primary] fills the pill with the accent (a call to action, e.g. Subscribe);
/// [tinted] gives a soft accent wash (an active/"done" state, e.g. Subscribed);
/// otherwise it's a neutral surface pill.
class HoverPillButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool tinted;
  final bool primary;

  /// Fills the pill with this exact colour (white foreground), for semantic
  /// actions like Approve (green) / Decline (red). Overrides [primary]/[tinted].
  final Color? color;

  /// Keeps the label showing at rest. For the one main action of a page on a
  /// narrow window, where a touch has no hover to name an icon.
  final bool showLabel;

  /// Replaces the [icon] glyph (e.g. a small progress spinner for a download in
  /// flight). Still gets the tap-pop scale and the expand-on-hover/press label.
  final Widget? iconWidget;

  /// Grabs focus on mount — used on TV so the remote lands on the primary
  /// action (e.g. Play on an album).
  final bool autofocus;

  final FocusNode? focusNode;

  const HoverPillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tinted = false,
    this.primary = false,
    this.color,
    this.showLabel = false,
    this.iconWidget,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  State<HoverPillButton> createState() => _HoverPillButtonState();
}

class _HoverPillButtonState extends State<HoverPillButton>
    with SingleTickerProviderStateMixin {
  bool _hover = false;
  bool _pressed = false;
  // A D-pad/remote focus reads like a hover (expands to the label) and adds a
  // ring, so the remote always shows which action it's on.
  bool _focused = false;

  // Touch platforms have no hover, so the label expands on press instead.
  static final bool _isTouch =
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  late final AnimationController _tap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _tapScale = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.28)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40),
    TweenSequenceItem(
        tween: Tween(begin: 1.28, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60),
  ]).animate(_tap);

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color fg;
    final Color bg;
    if (widget.color != null) {
      fg = Colors.white;
      bg = widget.color!;
    } else if (widget.primary) {
      fg = scheme.onPrimary;
      bg = scheme.primary;
    } else if (widget.tinted) {
      fg = scheme.primary;
      bg = scheme.primary.withValues(alpha: 0.14);
    } else {
      fg = scheme.onSurfaceVariant;
      bg = scheme.surfaceContainerHighest;
    }
    const h = 38.0;
    // The focus ring/expand is a TV affordance only; off TV this keeps the
    // original hover/press behaviour (desktop keyboard focus untouched).
    final showFocus = _focused && isTvDevice;
    // Desktop reveals the label on hover; touch reveals it while pressed. A
    // remote focus always reveals it, so the focused action names itself.
    final expanded =
        widget.showLabel || (_isTouch ? _pressed : _hover) || showFocus;
    final icon = ScaleTransition(
      scale: _tapScale,
      child: widget.iconWidget ?? Icon(widget.icon, size: 20, color: fg),
    );

    // Tooltip so the label is reachable without a hover (touch, quick glance).
    return Tooltip(
      message: widget.label,
      waitDuration: const Duration(milliseconds: 500),
      child: Opacity(
        opacity: widget.onTap == null ? 0.5 : 1,
        // Raw pointer events drive the touch press-to-expand: InkWell's
        // highlight is deferred inside a scroll view, so holding wouldn't
        // expand. onPointerDown fires immediately.
        child: Listener(
          // Press-to-expand works even when the action is disabled, so a
          // "done"/inert pill (e.g. Requested, Downloading) can still expand on
          // touch to reveal its label, matching the hover behaviour on desktop.
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
            child: Material(
              color: bg,
              shape: StadiumBorder(
                side: showFocus
                    ? BorderSide(
                        // A primary ring vanishes on a primary/coloured fill,
                        // so filled pills get a white ring instead.
                        color: (widget.primary || widget.color != null)
                            ? Colors.white
                            : scheme.primary,
                        width: 2.5)
                    : BorderSide.none,
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                autofocus: widget.autofocus,
                focusNode: widget.focusNode,
                onFocusChange: (v) => setState(() => _focused = v),
                // The ring (drawn on the Material shape) is the focus cue; the
                // accent-tinted default overlay is invisible over a primary fill.
                focusColor: Colors.transparent,
                onTap: widget.onTap,
                onTapDown:
                    widget.onTap == null ? null : (_) => _tap.forward(from: 0),
                child: AnimatedSize(
                duration: const Duration(milliseconds: 170),
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  height: h,
                  child: expanded
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              icon,
                              const SizedBox(width: 8),
                              Text(widget.label,
                                  style: TextStyle(
                                      color: fg,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
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
