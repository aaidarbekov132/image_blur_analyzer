import 'package:flutter/services.dart';

/// A class to interact with the native ImageBlurAnalyzer plugin.
class ImageBlurAnalyzer {
  /// The MethodChannel used to interact with the native platform.
  ///
  /// Note: The name MUST match the one used in your Swift `register` method.
  static const MethodChannel _channel = MethodChannel('imageBlurAnalyzer');

  /// Scans the user's photo library for blurry images.
  ///
  /// This method calls the native `scanForBlurryPhotos` method.
  ///
  /// Permissions must be granted by the host app before calling this:
  /// * iOS — `NSPhotoLibraryUsageDescription` and Photos access.
  /// * Android — `READ_MEDIA_IMAGES` (API 33+) or `READ_EXTERNAL_STORAGE`
  ///   (API 32 and below). On Android the call throws a
  ///   `PlatformException(code: 'PERMISSION_DENIED')` if access is missing.
  ///
  /// Returns a `List<String>` of identifiers of blurry photos:
  /// * iOS — `PHAsset.localIdentifier` (e.g. `"E1F1...EBC/L0/001"`).
  /// * Android — the numeric `MediaStore.Images.Media._ID` as a string
  ///   (e.g. `"123456"`), without any `content://` prefix.
  ///
  /// [androidThreshold] tunes the Android variance-of-Laplacian cutoff:
  /// images with variance below this value are treated as blurry. Higher
  /// values mark more photos as blurry. Defaults to `300.0`. Ignored on iOS,
  /// which has its own (separate) edge-intensity threshold baked into native.
  Future<List<String>> scanForBlurryPhotos({double androidThreshold = 300.0}) async {
    try {
      final List<dynamic>? blurryPhotoIDs = await _channel.invokeMethod(
        'scanForBlurryPhotos',
        <String, dynamic>{'threshold': androidThreshold},
      );

      // The platform returns a List<dynamic>, so we cast it
      // to the expected List<String>.
      if (blurryPhotoIDs == null) {
        return [];
      }
      return blurryPhotoIDs.cast<String>();
    } catch (_) {
      // Handle any potential platform errors, like permissions denied.
      rethrow;
    }
  }
}
