import 'package:flutter/material.dart';

/// An animated shimmering rectangle used to build loading skeletons.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final highlight =
        Color.alphaBlend(scheme.onSurface.withValues(alpha: 0.06), base);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
              transform: _SlideTransform(_controller.value * 2 - 1),
            ),
          ),
        );
      },
    );
  }
}

class _SlideTransform extends GradientTransform {
  final double slide;
  const _SlideTransform(this.slide);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * slide, 0, 0);
}

/// Loading skeleton for the browse/search poster grid.
class PosterGridSkeleton extends StatelessWidget {
  /// Matches the grid it stands in for, so content doesn't change shape when it
  /// lands. The defaults are the app's poster spec; landscape tiles (Libraries)
  /// and circular avatars (Artists) pass their own.
  final double maxExtent;
  final double aspectRatio;

  /// Round tile with a centred label below, for avatar grids.
  final bool circular;

  const PosterGridSkeleton({
    super.key,
    this.maxExtent = 184,
    this.aspectRatio = 0.54,
    this.circular = false,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent,
        mainAxisSpacing: 18,
        crossAxisSpacing: 14,
        childAspectRatio: aspectRatio,
      ),
      itemCount: 12,
      itemBuilder: (_, _) => Column(
        crossAxisAlignment:
            circular ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ShimmerBox(
              borderRadius: circular
                  ? const BorderRadius.all(Radius.circular(500))
                  : const BorderRadius.all(Radius.circular(12)),
            ),
          ),
          const SizedBox(height: 8),
          const ShimmerBox(
              height: 12,
              width: 90,
              borderRadius: BorderRadius.all(Radius.circular(6))),
        ],
      ),
    );
  }
}

/// Loading skeleton for a page that is a header over a poster grid (a
/// person's appearances, a film series): Back stays where it will be, a
/// block stands in for the header, and the posters below it.
///
/// The rule for loading: a page that will show posters loads as their
/// shapes; a list or a form loads behind the spinner.
class HeaderGridSkeleton extends StatelessWidget {
  /// The header's height, near enough that the grid doesn't jump.
  final double headerHeight;
  const HeaderGridSkeleton({super.key, this.headerHeight = 200});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BackButton(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: ShimmerBox(
            height: headerHeight,
            borderRadius: const BorderRadius.all(Radius.circular(16)),
          ),
        ),
        const Expanded(child: PosterGridSkeleton()),
      ],
    ),
  );
}

/// Loading placeholder for a Wrap of chips (Genres, Studios).
class ChipWrapSkeleton extends StatelessWidget {
  const ChipWrapSkeleton({super.key});

  // Varied widths so it reads as a cloud of chips, not a grid.
  static const _widths = [72.0, 96.0, 60.0, 110.0, 84.0, 68.0, 120.0, 90.0,
    76.0, 100.0, 64.0, 88.0, 108.0, 70.0];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final w in _widths)
            ShimmerBox(
              width: w,
              height: 34,
              borderRadius: const BorderRadius.all(Radius.circular(10)),
            ),
        ],
      ),
    );
  }
}

/// Loading skeleton for a horizontal home row.
/// Full-bleed skeleton for the Home hero banner, so the top of Home isn't blank
/// while the featured items load. Height matches FeaturedHero.
class HomeHeroSkeleton extends StatelessWidget {
  const HomeHeroSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final height = (width / 2.6).clamp(360.0, 760.0);
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Stack(
        children: [
          const Positioned.fill(
              child: ShimmerBox(borderRadius: BorderRadius.zero)),
          Positioned(
            left: 40,
            bottom: 48,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                ShimmerBox(
                    width: 300,
                    height: 34,
                    borderRadius: BorderRadius.all(Radius.circular(8))),
                SizedBox(height: 14),
                ShimmerBox(
                    width: 200,
                    height: 13,
                    borderRadius: BorderRadius.all(Radius.circular(6))),
                SizedBox(height: 10),
                ShimmerBox(
                    width: 380,
                    height: 12,
                    borderRadius: BorderRadius.all(Radius.circular(6))),
                SizedBox(height: 22),
                Row(children: [
                  ShimmerBox(
                      width: 130,
                      height: 44,
                      borderRadius: BorderRadius.all(Radius.circular(22))),
                  SizedBox(width: 12),
                  ShimmerBox(
                      width: 120,
                      height: 44,
                      borderRadius: BorderRadius.all(Radius.circular(22))),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical skeleton for an episode list (landscape still + two text lines).
class EpisodeListSkeleton extends StatelessWidget {
  final int count;
  const EpisodeListSkeleton({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerBox(
                      width: 96,
                      height: 54,
                      borderRadius: BorderRadius.all(Radius.circular(8))),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerBox(
                            width: double.infinity,
                            height: 13,
                            borderRadius:
                                BorderRadius.all(Radius.circular(6))),
                        SizedBox(height: 8),
                        ShimmerBox(
                            width: 160,
                            height: 11,
                            borderRadius:
                                BorderRadius.all(Radius.circular(6))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class SectionSkeleton extends StatelessWidget {
  final double height;
  const SectionSkeleton({super.key, required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (_, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: ShimmerBox(width: height * 0.62)),
            const SizedBox(height: 8),
            ShimmerBox(
                width: height * 0.5,
                height: 12,
                borderRadius: const BorderRadius.all(Radius.circular(6))),
          ],
        ),
      ),
    );
  }
}
