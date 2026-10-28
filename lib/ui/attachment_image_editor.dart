import 'package:flutter/material.dart';
import '../models/chat_models.dart';
import '../models/media_compression.dart';
import '../services/image_preparation.dart';
import '../services/encoded_image_dimensions.dart';
import '../services/image_animation.dart';
import 'profile_image_cropper.dart';
import 'lifecycle_memory_image.dart' show LifecycleMemoryImage;

Future<AttachmentDraft?> showAttachmentImageEditor(
  BuildContext context,
  AttachmentDraft draft,
) => showDialog<AttachmentDraft>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _ImageEditor(draft: draft),
);

class _ImageEditor extends StatefulWidget {
  const _ImageEditor({required this.draft});
  final AttachmentDraft draft;
  @override
  State<_ImageEditor> createState() => _ImageEditorState();
}

class _ImageEditorState extends State<_ImageEditor> {
  late AttachmentDraft _edited = widget.draft;
  AttachmentDraft? _prepared;
  ImageCompressionPreset _quality = ImageCompressionPreset.original;
  double? _ratio;
  bool _busy = false;
  String? _error;
  Future<void> _crop() async {
    final size = await readEncodedImageDimensions(_edited.bytes);
    if (!mounted) return;
    if (size == null || size.width * size.height > 32000000) {
      setState(
        () => _error =
            'This format or image size cannot be cropped safely. You can send the original.',
      );
      return;
    }
    final bytes = await showProfileImageCropper(
      context,
      bytes: _edited.bytes,
      title: 'Crop image',
      aspectRatio: _ratio ?? size.width / size.height,
      maximumWidth: size.width,
    );
    if (!mounted || bytes == null) return;
    setState(() {
      _edited = _edited.copyWith(
        bytes: bytes,
        mimeType: 'image/png',
        name: '${_edited.name.replaceFirst(RegExp(r'\.[^.]+$'), '')}.png',
        imagePrepared: false,
      );
      _prepared = null;
    });
  }

  Future<void> _prepare({bool save = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final draft =
          _prepared ??
          await prepareImage(_edited.copyWith(imagePrepared: false), _quality);
      if (!mounted) return;
      _prepared = draft.copyWith(imagePrepared: true);
      if (save) Navigator.pop(context, _prepared);
    } catch (_) {
      if (mounted) {
        _error =
            'Could not process this image. Try original quality or keep the existing attachment.';
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final animated = hasAnimatedImageHeader(_edited.bytes);
    return AlertDialog(
      scrollable: true,
      title: const Text('Edit image'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 260,
              child: LifecycleMemoryImage(
                bytes: (_prepared ?? _edited).bytes,
                animated: animated,
                autoplay: !MediaQuery.disableAnimationsOf(context),
                fit: BoxFit.contain,
                decodeWidth: 1024,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<double>(
              initialValue: _ratio ?? 0,
              decoration: const InputDecoration(labelText: 'Crop shape'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Keep aspect ratio')),
                DropdownMenuItem(value: 1, child: Text('Square')),
                DropdownMenuItem(value: 4 / 5, child: Text('Portrait, 4:5')),
                DropdownMenuItem(value: 16 / 9, child: Text('Landscape, 16:9')),
              ],
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _ratio = v == 0 ? null : v),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _crop,
              icon: const Icon(Icons.crop),
              label: const Text('Crop and move'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ImageCompressionPreset>(
              initialValue: _quality,
              decoration: const InputDecoration(labelText: 'Image quality'),
              items: const [
                DropdownMenuItem(
                  value: ImageCompressionPreset.original,
                  child: Text('Original'),
                ),
                DropdownMenuItem(
                  value: ImageCompressionPreset.balanced,
                  child: Text('Balanced, up to 2048 px'),
                ),
                DropdownMenuItem(
                  value: ImageCompressionPreset.smaller,
                  child: Text('Smaller, up to 1280 px'),
                ),
              ],
              onChanged: _busy || animated
                  ? null
                  : (v) => setState(() {
                      _quality = v!;
                      _prepared = null;
                    }),
            ),
            if (animated)
              const Text(
                'Animation is preserved. Quality presets do not re-encode animated images.',
              ),
            Text(
              '${((_prepared ?? _edited).bytes.length / 1048576).toStringAsFixed(2)} MiB',
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) Text(_error!),
            TextButton(
              onPressed: _busy ? null : () => _prepare(),
              child: const Text('Preview quality'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _prepare(save: true),
          child: const Text('Use image'),
        ),
      ],
    );
  }
}
