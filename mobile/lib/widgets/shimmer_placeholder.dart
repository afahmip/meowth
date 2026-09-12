import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Wraps a skeleton layout (built from [ShimmerBox]es) with the sweeping
/// highlight animation, so a loading screen shows the shape of its real
/// content instead of a bare spinner.
class ShimmerPlaceholder extends StatelessWidget {
  final Widget child;

  const ShimmerPlaceholder({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE5E7EB),
      highlightColor: const Color(0xFFF3F4F6),
      child: child,
    );
  }
}

/// A single skeleton block — stands in for a line of text, an avatar, a
/// chip, etc. Its own color is irrelevant once painted over by the
/// enclosing [ShimmerPlaceholder], but must be opaque for that to work.
class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(4)),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: borderRadius,
      ),
    );
  }
}
