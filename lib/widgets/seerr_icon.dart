import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The Seerr logo as a navigation icon: the flattened Seerr swirl, tinted to
/// [color] so it tracks the theme and accent exactly like the line icons
/// beside it. It marks the Discover section.
class SeerrIcon extends StatelessWidget {
  final Color color;
  final double size;
  const SeerrIcon({super.key, required this.color, this.size = 23});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/seerr.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
