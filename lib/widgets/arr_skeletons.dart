import 'package:flutter/material.dart';

import 'arr_widgets.dart';
import 'shimmer.dart';

/// The Manage section's lists while they load: the shape of what's coming,
/// as the rest of Fathom shows it, instead of a spinner on an empty page.

const _line = BorderRadius.all(Radius.circular(5));

/// The library grid: the same cells as the posters that replace them.
class ArrPosterGridSkeleton extends StatelessWidget {
  final SliverGridDelegate gridDelegate;
  final EdgeInsets padding;

  const ArrPosterGridSkeleton({
    super.key,
    required this.gridDelegate,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: padding,
    sliver: SliverGrid.builder(
      gridDelegate: gridDelegate,
      itemCount: 24,
      itemBuilder: (context, i) => const ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: ShimmerBox()),
            SizedBox(height: 8),
            ShimmerBox(width: 110, height: 12, borderRadius: _line),
            SizedBox(height: 6),
            ShimmerBox(width: 60, height: 10, borderRadius: _line),
          ],
        ),
      ),
    ),
  );
}

/// Rows with a small poster, a title, a line under it and a chip: the
/// Calendar, Wanted, History and Blocklist. With [cards], the queue's cards.
/// Never scrolls: it fills what's there and is cut off at the bottom.
class ArrRowsSkeleton extends StatelessWidget {
  final bool cards;

  /// A day heading above the rows, as on the Calendar.
  final bool heading;

  const ArrRowsSkeleton({super.key, this.cards = false, this.heading = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget row(int i) {
      final art = ShimmerBox(
        width: cards ? 52 : 46,
        height: cards ? 78 : 69,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      );
      final text = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Not all one length: a column of equal bars reads as a table.
          ShimmerBox(width: 150.0 + (i * 53) % 110, height: 14, borderRadius: _line),
          const SizedBox(height: 8),
          ShimmerBox(width: 90.0 + (i * 37) % 80, height: 11, borderRadius: _line),
          const SizedBox(height: 10),
          if (cards)
            const ShimmerBox(height: 6, borderRadius: _line)
          else
            const ShimmerBox(
              width: 76,
              height: 18,
              borderRadius: BorderRadius.all(Radius.circular(9)),
            ),
        ],
      );
      final body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [art, const SizedBox(width: 14), Expanded(child: text)],
      );
      if (!cards) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: body,
        );
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(padding: const EdgeInsets.all(12), child: body),
        ),
      );
    }

    return ExcludeSemantics(
      child: ArrListColumn(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: cards ? 12 : 8),
              if (heading)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: ShimmerBox(width: 96, height: 16, borderRadius: _line),
                ),
              for (var i = 0; i < 12; i++) row(i),
            ],
          ),
        ),
      ),
    );
  }
}

/// A show's or movie's page: the picture at the top, then what's said about
/// it. [headerHeight] is the height the real header takes.
class ArrDetailSkeleton extends StatelessWidget {
  final double headerHeight;
  const ArrDetailSkeleton({super.key, required this.headerHeight});

  @override
  Widget build(BuildContext context) {
    Widget fact(double w) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          const ShimmerBox(width: 110, height: 12, borderRadius: _line),
          const SizedBox(width: 24),
          ShimmerBox(width: w, height: 12, borderRadius: _line),
        ],
      ),
    );
    return ExcludeSemantics(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: headerHeight,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: ShimmerBox(borderRadius: BorderRadius.zero),
                  ),
                  Positioned(
                    left: 16,
                    bottom: 16,
                    child: Container(
                      width: 132,
                      height: 198,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: arrListMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ShimmerBox(height: 12, borderRadius: _line),
                    const SizedBox(height: 10),
                    const ShimmerBox(height: 12, borderRadius: _line),
                    const SizedBox(height: 10),
                    const FractionallySizedBox(
                      widthFactor: 0.6,
                      child: ShimmerBox(height: 12, borderRadius: _line),
                    ),
                    const SizedBox(height: 28),
                    fact(120),
                    fact(60),
                    fact(220),
                    fact(80),
                    const SizedBox(height: 14),
                    const ShimmerBox(
                      width: 90,
                      height: 16,
                      borderRadius: _line,
                    ),
                    const SizedBox(height: 14),
                    const ShimmerBox(height: 84),
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
