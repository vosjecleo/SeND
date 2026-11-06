import 'package:matrix/matrix.dart';

String notificationEventBody(Event event) {
  if (event.type == EventTypes.Sticker) return 'Sticker';
  if (event.type != EventTypes.Message) return 'New room activity';
  return event.calcUnlocalizedBody(
    hideReply: true,
    hideEdit: true,
    plaintextBody: true,
  );
}
