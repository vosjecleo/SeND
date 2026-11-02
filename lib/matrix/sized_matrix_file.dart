import 'package:matrix/matrix.dart';

/// Preserve an unsupported image's original MIME/bytes without asking Matrix
/// clients to decode it as an inline image.
class RawImageMatrixFile extends MatrixFile {
  RawImageMatrixFile({
    required super.bytes,
    required super.name,
    required super.mimeType,
  });
  @override
  String get msgType => MessageTypes.File;
}

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
