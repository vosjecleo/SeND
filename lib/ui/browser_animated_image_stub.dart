import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';

bool get prefersBrowserAnimation => false;
Widget browserAnimatedImage({
  required Uint8List bytes,
  required BoxFit fit,
  required double intrinsicWidth,
  required double intrinsicHeight,
  double? width,
  double? height,
}) => const SizedBox.shrink();
