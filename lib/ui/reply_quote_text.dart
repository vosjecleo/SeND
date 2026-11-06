import 'package:flutter/material.dart';
import '../models/chat_models.dart';
import 'json_theme.dart';

/// One stable line for both local echoes and hydrated replies. Font fallback
/// in quoted emoji must not change the row height when the echo is replaced.
class ReplyQuoteText extends StatelessWidget {
  const ReplyQuoteText({
    required this.reply,
    required this.fontSize,
    required this.muted,
    super.key,
  });

  final ReplyPreview reply;
  final double fontSize;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          if (reply.senderId != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ThemeAvatar(
                  key: const ValueKey('reply-mini-avatar'),
                  radius: 7,
                  autoplay: false,
                  backgroundImage: reply.avatarBytes == null
                      ? null
                      : MemoryImage(reply.avatarBytes!),
                  child: reply.avatarBytes == null
                      ? Text(
                          reply.sender.characters.firstOrNull ?? '?',
                          style: const TextStyle(fontSize: 9, height: 1),
                        )
                      : null,
                ),
              ),
            ),
          TextSpan(
            text: '${reply.sender}  ',
            style: TextStyle(
              color: reply.senderColor == null
                  ? null
                  : Color(reply.senderColor!),
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(
            text: reply.body.replaceAll('\n', ' '),
            style: TextStyle(color: muted),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: fontSize, height: 1.2),
      strutStyle: StrutStyle(
        fontSize: fontSize,
        height: 1.2,
        forceStrutHeight: true,
      ),
    );
  }
}
