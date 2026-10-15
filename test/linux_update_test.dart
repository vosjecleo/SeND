import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:deltiecord/services/appimage_delta.dart';
import 'package:deltiecord/services/linux_update.dart';
import 'package:deltiecord/services/update_checker.dart';

ReleaseArtifact artifact(List<int> bytes, [String suffix = '.AppImage']) =>
    ReleaseArtifact(
      'SeND-0.9.39+129-linux-appimage-x86_64$suffix',
      sha256.convert(bytes).toString(),
      bytes.length,
    );

/// Redirect only this test client's URLs to its owned local fixture server.
class MappedClient extends Fake implements HttpClient {
  MappedClient(this.server);
  final HttpServer server;
  final client = HttpClient();
  @override
  Future<HttpClientRequest> getUrl(Uri uri) =>
      client.getUrl(Uri.parse('http://127.0.0.1:${server.port}${uri.path}'));
  @override
  void close({bool force = false}) => client.close(force: force);
}

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('send-update-test-'),
  );
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'package command plans use fixed programs and no shell or system upgrade',
    () {
      expect(
        linuxPackageInstallArguments('-linux-debian-amd64.deb', '/tmp/a b.deb'),
        [
          '--disable-internal-agent',
          '/usr/bin/apt-get',
          '-y',
          '--no-remove',
          'install',
          '--',
          '/tmp/a b.deb',
        ],
      );
      expect(
        linuxPackageInstallArguments(
          '-linux-arch-x86_64.pkg.tar.zst',
          '/tmp/a.pkg.tar.zst',
        ),
        [
          '--disable-internal-agent',
          '/usr/bin/pacman',
          '-U',
          '--noconfirm',
          '--needed',
          '--',
          '/tmp/a.pkg.tar.zst',
        ],
      );
      expect(
        () => linuxPackageInstallArguments('unknown', 'a'),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'verification rejects oversized metadata, truncated and modified downloads',
    () async {
      final bytes = utf8.encode('verified package');
      final file = File('${directory.path}/download');
      await file.writeAsBytes(bytes);
      await verifyUpdateFile(file, artifact(bytes));
      await file.writeAsString('truncated');
      await expectLater(
        verifyUpdateFile(file, artifact(bytes)),
        throwsFormatException,
      );
      expect(
        () => validateUpdateArtifact(ReleaseArtifact('../bad', 'x' * 64, 1)),
        throwsFormatException,
      );
    },
  );

  test('cancelled authentication leaves installation unchanged', () async {
    final bytes = utf8.encode('package');
    final file = File('${directory.path}/package.deb');
    await file.writeAsBytes(bytes);
    var calls = 0;
    final update = PreparedLinuxUpdate(
      directory,
      file,
      artifact(bytes),
      '-linux-debian-amd64.deb',
      command: (exe, args, cwd) async {
        expect(exe, '/usr/bin/pkexec');
        calls++;
        return 126;
      },
    );
    await expectLater(update.install(), throwsStateError);
    expect(calls, 1);
    expect(update.installed, isFalse);
    expect(await file.exists(), isTrue);
  });

  test('tampered package never reaches the administrator prompt', () async {
    final file = File('${directory.path}/package.deb');
    await file.writeAsString('tampered');
    var calls = 0;
    final update = PreparedLinuxUpdate(
      directory,
      file,
      artifact([1, 2, 3]),
      '-linux-debian-amd64.deb',
      command: (_, _, _) async {
        calls++;
        return 0;
      },
    );
    await expectLater(update.install(), throwsFormatException);
    expect(calls, 0);
  });

  test(
    'AppImage replacement preserves a rollback copy and executable mode',
    () async {
      if (!Platform.isLinux) return;
      final old = File('${directory.path}/send.AppImage');
      await old.writeAsString('old image');
      await Process.run('/usr/bin/chmod', ['750', old.path]);
      final stage = await directory.createTemp('stage-');
      final bytes = utf8.encode('new image');
      final file = File('${stage.path}/new.AppImage');
      await file.writeAsBytes(bytes);
      final update = PreparedLinuxUpdate(
        stage,
        file,
        artifact(bytes),
        '-linux-appimage-x86_64.AppImage',
        original: old,
        originalHash: sha256.convert(utf8.encode('old image')).toString(),
      );
      await update.install();
      expect(await old.readAsBytes(), bytes);
      expect(await File(update.backupPath!).readAsString(), 'old image');
      expect((await old.stat()).mode & 511, 488); // 0750
      expect(update.installed, isTrue);
      expect(await stage.exists(), isFalse);
    },
  );

  test(
    'concurrent AppImage changes and chmod failure never replace the original',
    () async {
      final old = File('${directory.path}/send.AppImage');
      await old.writeAsString('other update');
      final stage = await directory.createTemp('stage-');
      final bytes = utf8.encode('new image');
      final file = File('${stage.path}/new.AppImage');
      await file.writeAsBytes(bytes);
      final update = PreparedLinuxUpdate(
        stage,
        file,
        artifact(bytes),
        '-linux-appimage-x86_64.AppImage',
        original: old,
        originalHash: 'stale',
        command: (_, _, _) async => 1,
      );
      await expectLater(update.install(), throwsStateError);
      expect(await old.readAsString(), 'other update');
      final same = PreparedLinuxUpdate(
        stage,
        file,
        artifact(bytes),
        '-linux-appimage-x86_64.AppImage',
        original: old,
        originalHash: sha256.convert(utf8.encode('other update')).toString(),
        command: (_, _, _) async => 1,
      );
      await expectLater(same.install(), throwsStateError);
      expect(await old.readAsString(), 'other update');
    },
  );

  test('zsync control cannot choose remote destinations or local paths', () {
    final header =
        'zsync: 0.6.2\nFilename: /etc/shadow\nBlocksize: 2048\nLength: 10\nHash-Lengths: 2,2,4\nURL: http://evil.invalid/\nURL: file:///etc/shadow\n\n';
    final local = Uri.parse('http://127.0.0.1:9999/capability');
    final rewritten = ascii.decode(
      localizeZsyncControl(ascii.encode(header), local, 10),
    );
    expect(rewritten, contains('URL: $local'));
    expect(rewritten, isNot(contains('evil')));
    expect(rewritten, isNot(contains('/etc/')));
    expect(
      () => localizeZsyncControl(ascii.encode(header), local, 11),
      throwsFormatException,
    );
    expect(
      () => localizeZsyncControl(
        ascii.encode(header.replaceAll('Blocksize: 2048', 'Blocksize: 3')),
        local,
        10,
      ),
      throwsFormatException,
    );
  });

  test('download rejects HTTP errors, truncation and wrong checksum', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    List<int> body = utf8.encode('good');
    var status = 200;
    server.listen((request) async {
      request.response.statusCode = status;
      request.response.add(body);
      await request.response.close();
    });
    final client = MappedClient(server);
    addTearDown(() => client.close(force: true));
    final expected = artifact(body);
    final file = File('${directory.path}/download');
    await downloadUpdateFile(client, expected, file);
    final stages = <String>[];
    await fetchLinuxUpdatePayload(
      client,
      expected,
      file,
      delta: () => file.writeAsString('bad delta'),
      progress: (value) => stages.add(value.message),
    );
    expect(await file.readAsString(), 'good');
    expect(stages.any((s) => s.contains('Delta update unavailable')), isTrue);
    body = utf8.encode('evil');
    await expectLater(
      downloadUpdateFile(client, expected, file),
      throwsFormatException,
    );
    body = [0];
    await expectLater(
      downloadUpdateFile(client, expected, file),
      throwsFormatException,
    );
    status = 500;
    await expectLater(
      downloadUpdateFile(client, expected, file),
      throwsA(isA<HttpException>()),
    );
  });

  test('real zsync engine reuses local bytes through the HTTP relay', () async {
    var bin =
        Platform.environment['SEND_ZSYNC_TEST_BIN'] ??
        '.dart_tool/update-test/root/usr/bin';
    if (!await File('$bin/zsync').exists()) bin = '/usr/bin';
    if (!await File('$bin/zsync').exists() ||
        !await File('$bin/zsyncmake').exists()) {
      markTestSkipped(
        'Install zsync or set SEND_ZSYNC_TEST_BIN for the native delta integration test.',
      );
      return;
    }
    final random = Random(42);
    final oldBytes = List.generate(2 * 1024 * 1024, (_) => random.nextInt(256));
    final newBytes = [...oldBytes];
    for (var i = 65536; i < 81920; i++) {
      newBytes[i] ^= 255;
    }
    final old = File('${directory.path}/old.AppImage');
    final fresh = File('${directory.path}/source.AppImage');
    await old.writeAsBytes(oldBytes);
    await fresh.writeAsBytes(newBytes);
    final controlFile = File('${directory.path}/source.zsync');
    final made = await Process.run('$bin/zsyncmake', [
      '-u',
      'http://unused.invalid/source',
      '-o',
      controlFile.path,
      fresh.path,
    ]);
    expect(made.exitCode, 0);
    final controlBytes = await controlFile.readAsBytes();
    final control = artifact(controlBytes, '.AppImage.zsync');
    final expected = artifact(newBytes);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var transferred = 0;
    server.listen((request) async {
      final response = request.response;
      if (request.uri.path.endsWith('.zsync')) {
        response.add(controlBytes);
      } else {
        final range = request.headers.value('range');
        final ranges = range?.substring(6).split(',') ?? [];
        if (ranges.isEmpty) {
          response.add(newBytes);
          transferred += newBytes.length;
        } else {
          response.statusCode = 206;
          response.headers.set('accept-ranges', 'bytes');
          if (ranges.length > 1) {
            response.headers.set(
              'content-type',
              'multipart/byteranges; boundary=fixture',
            );
          }
          for (final value in ranges) {
            final pair = value.trim().split('-');
            final start = int.parse(pair[0]);
            final end = pair[1].isEmpty
                ? newBytes.length - 1
                : int.parse(pair[1]);
            if (ranges.length > 1) {
              response.add(
                ascii.encode(
                  '--fixture\r\nContent-Type: application/octet-stream\r\nContent-Range: bytes $start-$end/${newBytes.length}\r\n\r\n',
                ),
              );
            } else {
              response.headers.set(
                'content-range',
                'bytes $start-$end/${newBytes.length}',
              );
            }
            response.add(newBytes.sublist(start, end + 1));
            transferred += end - start + 1;
            if (ranges.length > 1) response.add(ascii.encode('\r\n'));
          }
          if (ranges.length > 1) response.add(ascii.encode('--fixture--\r\n'));
        }
      }
      await response.close();
    });
    final client = MappedClient(server);
    addTearDown(() => client.close(force: true));
    final output = File('${directory.path}/output.AppImage');
    await applyAppImageDelta(
      client: client,
      artifact: expected,
      control: control,
      original: old,
      destination: output,
      helper: File('$bin/zsync').absolute,
      command: (exe, args, cwd) async {
        final env = Map<String, String>.of(Platform.environment)
          ..removeWhere((key, _) => key.toLowerCase().endsWith('_proxy'));
        final result = await Process.run(
          exe,
          args.where((a) => a != '-q').toList(),
          workingDirectory: cwd,
          environment: env,
          includeParentEnvironment: false,
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        return result.exitCode;
      },
    );
    await verifyUpdateFile(output, expected);
    final quiet = File('${directory.path}/quiet.AppImage');
    await applyAppImageDelta(
      client: client,
      artifact: expected,
      control: control,
      original: old,
      destination: quiet,
      helper: File('$bin/zsync').absolute,
    );
    await verifyUpdateFile(quiet, expected);
    expect(transferred, lessThan(newBytes.length ~/ 2));
    expect(transferred, greaterThan(0));
  });
}
