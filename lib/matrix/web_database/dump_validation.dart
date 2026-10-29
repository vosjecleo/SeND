import 'dart:convert';

/// Validate the entire snapshot before any persistent writes are scheduled.
/// The shape stays compatible with SDK 10.1 exports. The two collections its
/// exporter omitted are optional for old dumps; absent collections are kept.
Map<String, Map<String, Object?>> validateMatrixDump(
  String dump, {
  required int version,
}) {
  const strings = {
    'box_client',
    'box_inbound_group_sessions_upload_queue',
    'box_seen_device_ids',
    'box_seen_device_keys',
  };
  const maps = {
    'box_account_data',
    'box_rooms',
    'box_preload_room_states',
    'box_non_preload_room_states',
    'box_room_members',
    'box_to_device_queue',
    'box_room_account_data',
    'box_inbound_group_session',
    'box_outbound_group_session',
    'box_olm_session',
    'box_user_device_keys',
    'box_cross_signing_keys',
    'box_ssss_cache',
    'box_presences',
    'box_events',
    'box_user_profiles',
    'box_read_receipts',
  };
  const optional = {'box_user_profiles', 'box_read_receipts'};
  const all = {
    ...strings,
    ...maps,
    'box_user_device_keys_outdated',
    'box_timeline_fragments',
  };
  final decoded = jsonDecode(dump);
  if (decoded is! Map ||
      decoded.keys.any((key) => !all.contains(key)) ||
      all.difference(optional).any((key) => !decoded.containsKey(key))) {
    throw const FormatException('Incomplete or unsupported database dump.');
  }
  final result = <String, Map<String, Object?>>{};
  for (final entry in decoded.entries) {
    final name = entry.key as String;
    final rows = entry.value;
    if (rows is! Map<String, dynamic>) {
      throw const FormatException('Invalid database collection.');
    }
    for (final value in rows.values) {
      final valid = strings.contains(name)
          ? value is String
          : maps.contains(name)
          ? value is Map<String, dynamic>
          : name == 'box_timeline_fragments'
          ? value is List && value.every((id) => id is String)
          : value is bool;
      if (!valid) throw const FormatException('Invalid database record.');
    }
    result[name] = Map<String, Object?>.from(rows);
  }
  if (result['box_client']?['version'] != '$version') {
    throw const FormatException('Unsupported database schema version.');
  }
  return result;
}
