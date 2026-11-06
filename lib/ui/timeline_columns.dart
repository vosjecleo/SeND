/// Shared horizontal coordinates for messages and the typing strip.
abstract final class TimelineColumns {
  static const double desktopAvatarInset = 10;
  static const double desktopAvatarSize = 38;
  static const double desktopAvatarSlot = 40;
  static const double desktopGap = 10;
  static const double desktopTextInset =
      desktopAvatarInset + desktopAvatarSlot + desktopGap;
  static const double mobileAvatarInset = 8;
  static const double mobileAvatarSize = 40;
  static const double mobileGap = 8;
  static const double mobileTextInset =
      mobileAvatarInset + mobileAvatarSize + mobileGap;
}
