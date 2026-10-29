'use strict';
// Leave legacy manifests and binary URLs untouched: old clients do not follow
// redirects for release checks. Only the old human-facing page redirects.
if (/^\/cord(?:\/|\/index\.html)?$/.test(location.pathname)) {
  location.replace('/SeND/' + location.search + location.hash);
}
const formats = [
  ['-windows-x64-setup.exe', 'Windows installer (recommended)'],
  ['-windows-x64-portable.zip', 'Windows portable ZIP'],
  ['-linux-appimage-x86_64.AppImage', 'Linux AppImage'],
  ['-linux-x86_64.flatpak', 'Linux Flatpak'],
  ['-linux-arch-x86_64.pkg.tar.zst', 'Arch Linux package'],
  ['-linux-debian-amd64.deb', 'Debian / Ubuntu package'],
  ['-android-arm64-v8a.apk', 'Android ARM64 (most phones)'],
  ['-android-armeabi-v7a.apk', 'Android ARMv7 (older phones)'],
  ['-android-x86_64.apk', 'Android x86-64'],
  ['-android.aab', 'Android App Bundle (distribution only)'],
];
function addDownloads(body, title, files) {
  if (!Array.isArray(files) || !files.length) return;
  const heading = document.createElement('h3');
  heading.textContent = title;
  body.append(heading);
  const list = document.createElement('ul');
  for (const file of files) {
    if (!/^[a-zA-Z0-9+_.-]{1,180}$/.test(file.name || '')) continue;
    const label = formats.find(([suffix]) => file.name.endsWith(suffix));
    if (!label) continue;
    const item = document.createElement('li'), link = document.createElement('a');
    link.href = '/SeND/' + encodeURIComponent(file.name);
    link.textContent = label[1];
    link.download = file.name;
    item.append(link);
    if (Number.isFinite(file.size) && file.size > 0) {
      item.append(document.createTextNode(' · ' + (file.size / 1048576).toFixed(1) + ' MiB'));
    }
    list.append(item);
  }
  body.append(list);
}
const ua = navigator.userAgent;
function releaseLabel(data, channel) {
  const title = channel === 'stable' ? 'Stable' : 'Latest';
  const version = channel === 'stable' ? data.stable_version : data.version;
  const build = channel === 'stable' ? data.stable_build : data.build;
  if (typeof version !== 'string' || !/^\d+\.\d+\.\d+$/.test(version) ||
      !Number.isSafeInteger(build) || build < 1) return title;
  return title + ': version ' + version + ' build ' + build;
}
const suggested = /Android/i.test(ua) ? 'android' : /Windows/i.test(ua) ? 'windows' : /Linux/i.test(ua) ? 'linux' : null;
if (suggested) document.querySelector('[data-platform="' + suggested + '"]').open = true;
if (/iPhone|iPad|Macintosh/i.test(ua)) {
  document.getElementById('suggestion').textContent = 'On Apple devices, use SeND Web above. No App Store installation is needed.';
}
fetch('/SeND/releases.json', {cache: 'no-store'})
  .then(response => { if (!response.ok) throw new Error('manifest'); return response.json(); })
  .then(data => {
    const summary = document.getElementById('release-channels');
    summary.replaceChildren();
    for (const channel of ['stable', 'latest']) {
      const label = document.createElement('span');
      const available = ['windows', 'linux', 'android'].some(system =>
        Array.isArray(data.platforms?.[system]?.[channel]) && data.platforms[system][channel].length > 0);
      label.textContent = available ? releaseLabel(data, channel) :
        (channel === 'stable' ? 'Stable' : 'Latest') + ': not published yet';
      if (summary.children.length) summary.append(document.createElement('br'));
      summary.append(label);
    }
    for (const system of ['windows', 'linux', 'android']) {
      const body = document.querySelector('[data-platform="' + system + '"] .download-body');
      body.textContent = '';
      const platform = data.platforms?.[system] || {};
      addDownloads(body, releaseLabel(data, 'stable'), platform.stable);
      addDownloads(body, releaseLabel(data, 'latest'), platform.latest);
      if (!body.children.length) body.textContent = 'No build is available for this platform yet.';
    }
  }).catch(() => {
    document.getElementById('release-channels').textContent = 'Release versions unavailable.';
    document.getElementById('release-error').hidden = false;
  });
