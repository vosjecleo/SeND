import 'package:flutter/material.dart';

abstract final class MessageSpacing {
  static const double extraVerticalPadding = 1;
  static const double desktopPlainLineHeight = 1.28;
  static const double richLineHeight = 1.4;
  static bool _mobile(BuildContext context) =>
      Theme.of(context).platform == TargetPlatform.android ||
      Theme.of(context).platform == TargetPlatform.iOS;
  static double richLineHeightFor(BuildContext context) =>
      _mobile(context) ? 1.28 : richLineHeight;
  static double inheritedLineHeight(BuildContext context) =>
      (DefaultTextStyle.of(context).style.height ?? 1.28) +
      (_mobile(context) ? 0 : .12);
}
