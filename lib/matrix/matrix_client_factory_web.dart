import 'package:matrix/matrix.dart';
import 'package:universal_io/universal_io.dart' show Directory;

import 'matrix_state_types.dart';
import 'rtc/rtc_matrix_client.dart';
import 'rtc/rtc_protocol.dart';

/// The SDK owns IndexedDB session and crypto persistence on browsers, just as
/// it owns SQLite persistence on native. Never create a second token store.
Future<Client> createMatrixClient() async => RtcMatrixClient(
  'Deltiecord', // Persistent SDK client ID; preserve existing browser sessions.
  database: await MatrixSdkDatabase.init('deltiecord'),
  importantStateEvents: {
    rtcCallMemberType,
    deltiecordRoomPresentationEventType,
    deltiecordSpaceChannelsEventType,
    deltiecordSpaceRolesEventType,
    'net.deltiecord.space.policy',
  },
  shareKeysWith: ShareKeysWith.all,
);

Future<Directory> getDeltiecordDataDirectory() =>
    Future.error(UnsupportedError('Browser data is stored in IndexedDB.'));
