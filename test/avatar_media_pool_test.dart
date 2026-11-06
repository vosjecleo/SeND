import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:crypto/crypto.dart';

import 'package:deltiecord/services/avatar_media_pool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory cacheDirectory;

  setUp(() async {
    cacheDirectory = await Directory.systemTemp.createTemp(
      'deltiecord-avatar-pool-',
    );
  });

  tearDown(() async {
    if (await cacheDirectory.exists()) {
      await cacheDirectory.delete(recursive: true);
    }
  });
  test(
    'background originals are serial and coalesced while thumbnails remain free',
    () async {
      final pool = AvatarMediaPool(directory: cacheDirectory);
      final first = Completer<Uint8List?>();
      var active = 0, maximum = 0, starts = 0;
      final a = Uri.parse('mxc://example.org/one');
      final b = Uri.parse('mxc://example.org/two');
      Future<Uint8List?> loadFirst() async {
        starts++;
        active++;
        maximum = active;
        final result = await first.future;
        active--;
        return result;
      }

      final one = pool.queueOriginal(a, 512, loadFirst);
      final same = pool.queueOriginal(a, 512, loadFirst);
      final two = pool.queueOriginal(b, 512, () async {
        starts++;
        active++;
        if (active > maximum) maximum = active;
        active--;
        return Uint8List.fromList([2]);
      });
      await Future<void>.delayed(Duration.zero);
      expect(starts, 1);
      expect(
        await pool.load(
          Uri.parse('mxc://example.org/thumbnail'),
          128,
          () async => Uint8List.fromList([3]),
        ),
        [3],
      );
      first.complete(Uint8List.fromList([1]));
      expect(await one, [1]);
      expect(await same, [1]);
      expect(await two, [2]);
      expect(starts, 2);
      expect(maximum, 1);
      await pool.clear();
    },
  );
  test(
    'clearing invalidates an active original and cancels queued original work',
    () async {
      final pool = AvatarMediaPool(directory: cacheDirectory);
      final pending = Completer<Uint8List?>();
      final first = pool.queueOriginal(
        Uri.parse('mxc://example.org/one'),
        512,
        () => pending.future,
      );
      var secondStarted = false;
      final second = pool.queueOriginal(
        Uri.parse('mxc://example.org/two'),
        512,
        () async {
          secondStarted = true;
          return Uint8List.fromList([2]);
        },
      );
      await Future<void>.delayed(Duration.zero);
      await pool.clear(disk: false);
      pending.complete(Uint8List.fromList([1]));
      expect(await first, isNull);
      expect(await second, isNull);
      expect(secondStarted, false);
    },
  );

  test('coalesces concurrent requests for one MXC thumbnail', () async {
    final pool = AvatarMediaPool(directory: cacheDirectory);
    final uri = Uri.parse('mxc://example.org/alice');
    var loads = 0;
    Future<Uint8List?> loader() async {
      loads++;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return Uint8List.fromList([1, 2, 3]);
    }

    final results = await Future.wait([
      pool.load(uri, AvatarMediaPool.rowDimension, loader),
      pool.load(uri, AvatarMediaPool.rowDimension, loader),
    ]);

    expect(loads, 1);
    expect(results[0], [1, 2, 3]);
    expect(results[1], [1, 2, 3]);
    await pool.clear();
  });

  test(
    'legacy still thumbnails are not reused as animated originals',
    () async {
      final uri = Uri.parse('mxc://example.org/animated');
      final oldName = '${sha256.convert(utf8.encode(uri.toString()))}-512.bin';
      await File('${cacheDirectory.path}/$oldName').writeAsBytes([1, 2, 3]);
      final pool = AvatarMediaPool(directory: cacheDirectory);
      var loads = 0;
      final bytes = await pool.load(uri, 512, () async {
        loads++;
        return Uint8List.fromList([4, 5, 6]);
      });
      expect(loads, 1);
      expect(bytes, [4, 5, 6]);
      await pool.clear();
    },
  );

  test('larger cached avatars satisfy smaller surfaces', () async {
    final pool = AvatarMediaPool(directory: cacheDirectory);
    final uri = Uri.parse('mxc://example.org/alice');
    final bytes = Uint8List.fromList([4, 5, 6]);

    pool.seed(uri, bytes, AvatarMediaPool.profileDimension);

    expect(pool.peek(uri, AvatarMediaPool.rowDimension), same(bytes));
    expect(pool.peek(uri, AvatarMediaPool.profileDimension), same(bytes));
    await pool.clear();
  });

  test('disk cache survives a new pool without another network load', () async {
    final uri = Uri.parse('mxc://example.org/alice');
    final first = AvatarMediaPool(directory: cacheDirectory);
    expect(
      await first.load(
        uri,
        AvatarMediaPool.rowDimension,
        () async => Uint8List.fromList([7, 8, 9]),
      ),
      [7, 8, 9],
    );
    await first.clear(disk: false); // Wait for the protected disk write.

    final second = AvatarMediaPool(directory: cacheDirectory);
    var networkLoads = 0;
    final result = await second.load(
      uri,
      AvatarMediaPool.rowDimension,
      () async {
        networkLoads++;
        return Uint8List.fromList([0]);
      },
    );

    expect(result, [7, 8, 9]);
    expect(networkLoads, 0);
    await second.clear();
  });
}
