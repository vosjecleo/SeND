part of 'matrix_backend.dart';

const _profileBioField = 'net.deltiecord.bio';
const _profilePronounsField = 'net.deltiecord.pronouns';
const _profileBannerField = 'net.deltiecord.banner';

extension _MatrixProfiles on MatrixBackend {
  Future<UserProfileSummary> _getUserProfile(String userId) async {
    final profile = await _matrix.getUserProfile(
      userId,
      maxCacheAge: Duration.zero,
    );
    final avatarBytes = await _profileMedia(profile.avatarUrl, 256, 256);
    final bannerUri = Uri.tryParse(
      profile.additionalProperties[_profileBannerField] as String? ?? '',
    );
    final bannerBytes = await _profileMedia(bannerUri, 800, 240);
    // The endpoint itself is the compatibility probe. Older homeservers return
    // M_UNRECOGNIZED; the base display name/avatar remain fully usable.
    var extensible = true;
    try {
      await _matrix.getProfileField(userId, 'm.tz');
    } catch (_) {
      extensible = false;
    }
    // ignore: deprecated_member_use
    final presence = _matrix.presences[userId]?.presence;
    return UserProfileSummary(
      userId: userId,
      displayName:
          profile.displayname ?? userId.split(':').first.replaceFirst('@', ''),
      avatarBytes: avatarBytes,
      bannerBytes: bannerBytes,
      presence: switch (presence) {
        PresenceType.online => UserPresence.online,
        PresenceType.unavailable => UserPresence.away,
        _ => UserPresence.offline,
      },
      bio: profile.additionalProperties[_profileBioField] as String?,
      pronouns: profile.additionalProperties[_profilePronounsField] as String?,
      timezone: profile.mTz,
      extensibleFieldsSupported: extensible,
      blocked: _matrix.ignoredUsers.contains(userId),
    );
  }

  Future<Uint8List?> _profileMedia(Uri? mxc, int width, int height) async {
    if (mxc == null || !mxc.isScheme('mxc')) return null;
    try {
      final response = await _matrix.getContentThumbnail(
        mxc.host,
        mxc.pathSegments.join('/'),
        width,
        height,
        method: Method.crop,
      );
      return response.data;
    } catch (_) {
      return null;
    }
  }

  Future<void> _updateOwnProfileFields({
    String? bio,
    String? pronouns,
    String? timezone,
    Uint8List? bannerBytes,
    required bool removeBanner,
  }) async {
    final userId = _matrix.userID;
    if (userId == null) return;
    Future<void> setText(String key, String? value) async {
      if (value == null) return;
      if (value.trim().isEmpty) {
        await _matrix.deleteProfileField(userId, key);
      } else {
        await _matrix.setProfileField(userId, key, {key: value.trim()});
      }
    }

    try {
      await setText(_profileBioField, bio);
      await setText(_profilePronounsField, pronouns);
      await setText('m.tz', timezone);
      if (removeBanner) {
        await _matrix.deleteProfileField(userId, _profileBannerField);
      } else if (bannerBytes != null) {
        final mxc = await _matrix.uploadContent(
          bannerBytes,
          filename: 'profile-banner.png',
          contentType: 'image/png',
        );
        await _matrix.setProfileField(userId, _profileBannerField, {
          _profileBannerField: mxc.toString(),
        });
      }
      _notifyBackendListeners();
    } catch (exception) {
      _error = _friendlyError(exception);
      _notifyBackendListeners();
      rethrow;
    }
  }

  Future<void> _startDirectChat(String userId) async {
    final roomId = await _matrix.startDirectChat(userId);
    _selectSpace(null);
    await _selectRoom(roomId);
  }

  Future<void> _setUserBlocked(String userId, bool blocked) async {
    if (blocked) {
      await _matrix.ignoreUser(userId);
    } else {
      await _matrix.unignoreUser(userId);
    }
    _notifyBackendListeners();
  }
}
