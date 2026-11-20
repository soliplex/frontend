import 'package:flutter/rendering.dart';

/// Lays out an SVG picture of [size] as flutter_svg's `FittedBox` does:
/// [box] is [size] kept to its shape within [constraints], and [picture] is
/// [size] scaled to fit inside [box], centred in it by the caller.
///
/// [picture] is fitted by ratio rather than with [applyBoxFit], whose
/// `contain` multiplies before it divides: an SVG 1e308 on each side, in an
/// 800 x 600 box, would come out infinitely wide. Divided first, each side is
/// at most the box's, so a [box] that is finite gives a [picture] that is
/// finite and inside it.
({Size box, Size picture}) fitSvg(Size size, BoxConstraints constraints) {
  if (size.isEmpty) {
    return (box: constraints.constrain(Size.zero), picture: Size.zero);
  }
  final box = constraints.constrainSizeAndAttemptToPreserveAspectRatio(size);
  if (box.isEmpty) return (box: box, picture: Size.zero);
  final aspectRatio = size.width / size.height;
  final picture = box.width / box.height > aspectRatio
      ? Size(box.height * aspectRatio, box.height)
      : Size(box.width, box.width / aspectRatio);
  return (box: box, picture: picture);
}
