Deltiecord v0.4.2 test bundle
================================

Linux AppImage:
  chmod +x Deltiecord-0.4.2-x86_64.AppImage
  ./Deltiecord-0.4.2-x86_64.AppImage

Debian/Ubuntu package:
  sudo apt install ./deltiecord_0.4.2_amd64.deb

Verify files:
  sha256sum -c SHA256SUMS

The source archive excludes Git history, build caches, local app data, login
sessions, encryption keys, and generated packaging tools. A desktop Secret
Service is required for secure session/E2EE storage. PipeWire-Pulse or
PulseAudio is required for voice-room audio.
