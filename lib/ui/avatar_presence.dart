import 'package:flutter/material.dart';
import '../models/chat_models.dart';
import 'activity_widgets.dart';

double presenceBadgeSize(double originalSize, {bool phone = false}) =>
    originalSize * (phone ? 1.5 : 1.25);

bool showsMobilePresence(
  BuildContext context,
  String? userId,
  UserPresence presence,
) =>
    presence == UserPresence.online &&
    userId != null &&
    (ActivityScope.of(context)?.mobileOnlineFor(userId) ?? false);

class AvatarPresence extends StatelessWidget {
  const AvatarPresence({
    required this.child,
    required this.presence,
    required this.userId,
    required this.badgeSize,
    this.badgeKey,
    this.right = 0,
    this.bottom = 0,
    super.key,
  });
  final Widget child;
  final UserPresence presence;
  final String? userId;
  final double badgeSize, right, bottom;
  final Key? badgeKey;

  @override
  Widget build(BuildContext context) {
    final phone = showsMobilePresence(context, userId, presence);
    final dimension = presenceBadgeSize(badgeSize, phone: phone);
    final insetRight = right.clamp(0.0, double.infinity).toDouble();
    final insetBottom = bottom.clamp(0.0, double.infinity).toDouble();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipPath(
          clipper: AvatarPresenceCutout(
            phone: phone,
            badgeSize: dimension,
            right: insetRight,
            bottom: insetBottom,
          ),
          child: child,
        ),
        Positioned(
          right: insetRight,
          bottom: insetBottom,
          child: PresenceBadge(
            key: badgeKey,
            presence: presence,
            phone: phone,
            size: dimension,
          ),
        ),
      ],
    );
  }
}

class PresenceBadge extends StatelessWidget {
  const PresenceBadge({
    required this.presence,
    required this.phone,
    required this.size,
    super.key,
  });
  final UserPresence presence;
  final bool phone;
  final double size;
  @override
  Widget build(BuildContext context) => Semantics(
    label: phone ? 'Online on mobile' : null,
    child: SizedBox.square(
      dimension: size,
      child: phone
          ? const CustomPaint(painter: _PhonePresencePainter())
          : Padding(
              // Leave the badge footprint/cutout unchanged; inset only the face.
              padding: EdgeInsets.all(size * .05),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: switch (presence) {
                    UserPresence.online => const Color(0xff23c483),
                    UserPresence.away => const Color(0xffe3a53a),
                    UserPresence.doNotDisturb => const Color(0xffe5484d),
                    UserPresence.offline => const Color(0xff70737d),
                  },
                ),
                child: presence == UserPresence.offline
                    ? const Center(
                        child: FractionallySizedBox(
                          widthFactor: .58,
                          heightFactor: .58,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xff303238),
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
    ),
  );
}

// Align the phone to the badge's right edge. Keeping it centred leaves a thin
// sliver of the circular avatar beyond the cutout at some avatar sizes.
Rect _phoneRect(Size size) =>
    Rect.fromLTRB(size.width * .36, 0, size.width, size.height);

/// Cuts through the avatar pixels instead of painting a solid patch over a
/// potentially animated or gradient background.
class AvatarPresenceCutout extends CustomClipper<Path> {
  const AvatarPresenceCutout({
    required this.badgeSize,
    required this.phone,
    this.right = 0,
    this.bottom = 0,
  });
  final bool phone;
  final double badgeSize, right, bottom;
  @override
  Path getClip(Size size) {
    final rect =
        (phone
                ? _phoneRect(Size.square(badgeSize))
                : (Offset.zero & Size.square(badgeSize)))
            .shift(
              Offset(
                size.width - right - badgeSize,
                size.height - bottom - badgeSize,
              ),
            );
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      phone
          ? (Path()..addRRect(
              RRect.fromRectAndRadius(
                rect.inflate(2),
                const Radius.circular(3),
              ),
            ))
          : (Path()..addOval(rect.inflate(2))),
    );
  }

  @override
  bool shouldReclip(AvatarPresenceCutout oldClipper) =>
      phone != oldClipper.phone ||
      badgeSize != oldClipper.badgeSize ||
      right != oldClipper.right ||
      bottom != oldClipper.bottom;
}

class PhonePresenceCutout extends AvatarPresenceCutout {
  const PhonePresenceCutout({
    required super.badgeSize,
    super.right,
    super.bottom,
  }) : super(phone: true);
}

class _PhonePresencePainter extends CustomPainter {
  const _PhonePresencePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final outer = _phoneRect(size);
    final screen = Rect.fromLTRB(
      outer.left + size.width * .12,
      outer.top + size.height * .14,
      outer.right - size.width * .12,
      outer.bottom - size.height * .25,
    );
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRRect(
        RRect.fromRectAndRadius(outer, Radius.circular(size.width * .14)),
      )
      ..addRRect(
        RRect.fromRectAndRadius(screen, Radius.circular(size.width * .035)),
      );
    canvas.drawPath(path, Paint()..color = const Color(0xff23c483));
  }

  @override
  bool shouldRepaint(_PhonePresencePainter oldDelegate) => false;
}
