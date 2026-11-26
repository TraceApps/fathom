import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/tv_mode.dart';
import 'tv_focus.dart';

/// Shared section header: an accent bar + bold title, optionally with a
/// trailing action. Used across Home + Discover so rows read consistently.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 24, trailing == null ? 20 : 12, 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // A heading, so screen-reader users can jump row to row.
          Semantics(
            header: true,
            child: Text(title,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (trailing != null) ...[const Spacer(), trailing!],
        ],
      ),
    );
  }
}

/// A titled horizontal row of cards (Continue Watching, Recently Added, ...).
/// On desktop, hovering reveals left/right scroll affordances.
class MediaSection extends StatefulWidget {
  final String title;
  final double height;
  final List<Widget> children;
  final VoidCallback? onSeeAll;

  const MediaSection({
    super.key,
    required this.title,
    required this.height,
    required this.children,
    this.onSeeAll,
  });

  @override
  State<MediaSection> createState() => _MediaSectionState();
}

class _MediaSectionState extends State<MediaSection> {
  final _sc = ScrollController();
  bool _hover = false;
  bool _canLeft = false;
  bool _canRight = false;

  @override
  void initState() {
    super.initState();
    _sc.addListener(_updateArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  // Each arrow shows only when the row can actually scroll that way.
  void _updateArrows() {
    if (!_sc.hasClients) return;
    final pos = _sc.position;
    final left = pos.pixels > pos.minScrollExtent + 1;
    final right = pos.pixels < pos.maxScrollExtent - 1;
    if (left != _canLeft || right != _canRight) {
      setState(() {
        _canLeft = left;
        _canRight = right;
      });
    }
  }

  void _scrollBy(double delta) {
    if (!_sc.hasClients) return;
    final target =
        (_sc.offset + delta).clamp(0.0, _sc.position.maxScrollExtent);
    _sc.animateTo(target,
        duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  // On TV the row becomes a self-contained D-pad group (LEFT/RIGHT walk cards,
  // LEFT-past-first jumps to the nav rail, UP/DOWN move between rows).
  Widget _maybeTvRow(Widget list) =>
      isTvDevice ? TvFocusRow(child: list) : list;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: widget.title,
          trailing: widget.onSeeAll == null
              ? null
              : TextButton(
                  onPressed: widget.onSeeAll,
                  child: Text(AppLocalizations.of(context).extraSeeAll),
                ),
        ),
        MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: SizedBox(
            height: widget.height,
            // Clip.none lets a hovered card scale up past the row bounds
            // without being cropped.
            child: NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                _updateArrows();
                return false;
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _maybeTvRow(ListView.separated(
                    controller: _sc,
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: widget.children.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (_, i) => widget.children[i],
                  )),
                  ScrollAffordance(
                    visible: _hover && _canLeft,
                    left: true,
                    onTap: () => _scrollBy(-widget.height * 2.2),
                  ),
                  ScrollAffordance(
                    visible: _hover && _canRight,
                    left: false,
                    onTap: () => _scrollBy(widget.height * 2.2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A hover-revealed chevron button that scrolls a row left or right.
class ScrollAffordance extends StatelessWidget {
  final bool visible;
  final bool left;
  final VoidCallback onTap;
  const ScrollAffordance(
      {super.key,
      required this.visible,
      required this.left,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: Container(
            width: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: left ? Alignment.centerLeft : Alignment.centerRight,
                end: left ? Alignment.centerRight : Alignment.centerLeft,
                colors: [
                  scheme.surface.withValues(alpha: 0.9),
                  scheme.surface.withValues(alpha: 0.0),
                ],
              ),
            ),
            child: Material(
              color: scheme.surfaceContainerHigh.withValues(alpha: 0.9),
              shape: const CircleBorder(),
              child: Semantics(button: true, label: left ? AppLocalizations.of(context).commonPrevious : AppLocalizations.of(context).commonNext, child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    left
                        ? Icons.chevron_left_rounded
                        : Icons.chevron_right_rounded,
                    size: 26,
                  ),
                ),
              )),
            ),
          ),
        ),
      ),
    );
  }
}
