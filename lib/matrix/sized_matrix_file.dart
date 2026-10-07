import 'package:matrix/matrix.dart';

/// Adds dimensions without decoding animation frames or generating thumbnails.
class SizedMatrixFile extends MatrixFile {
  SizedMatrixFile({
    required super.bytes,
    required super.name,
    required super.mimeType,
    required this.width,
    required this.height,
  });

  final int? width;
  final int? height;

  @override
  Map<String, dynamic> get info => {
    ...super.info,
    if (width != null && height != null) ...{'w': width, 'h': height},
  };
}
