import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'screen_automation_service.dart';

/// Handles picking/capturing images to attach to a chat message and
/// converting them into base64 data URIs for the vision-capable models.
class ImageAttachmentService {
  static const int maxLongestEdge = 1568;
  static const int jpegQuality = 70;

  final ImagePicker _picker = ImagePicker();

  /// Lets the user pick an image from the gallery. Returns the local file
  /// path, or null if the user cancelled.
  Future<String?> pickFromGallery() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: maxLongestEdge.toDouble(),
      imageQuality: jpegQuality,
    );
    return file?.path;
  }

  /// Captures the current screen via the existing accessibility screenshot
  /// channel and writes it to a temp file, so it can be treated the same
  /// way as a gallery pick downstream.
  Future<String?> captureScreen(ScreenAutomationService service) async {
    final base64String = await service.takeScreenshot();
    if (base64String == null || base64String.isEmpty) return null;

    final bytes = base64Decode(base64String);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/screen_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Reads the file at [path] and returns it as a base64 data URI suitable
  /// for an OpenAI/NIM-style `image_url` content block.
  Future<String> toBase64DataUri(String path) async {
    final bytes = await File(path).readAsBytes();
    final mime = _mimeTypeFor(path);
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  String _mimeTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}
