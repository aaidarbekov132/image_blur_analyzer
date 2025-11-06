import 'package:flutter/services.dart';

/// A class to interact with the native ImageBlurAnalyzer plugin.
class ImageBlurAnalyzer {
  /// The MethodChannel used to interact with the native platform.
  ///
  /// Note: The name MUST match the one used in your Swift `register` method.
  static const MethodChannel _channel = MethodChannel('imageBlurAnalyzer');

  /// Scans the user's photo library for blurry images.
  ///
  /// This method calls the native 'scanForBlurryPhotos' method.
  ///
  /// Requires Photo library permissions on iOS.
  /// Returns a [List<String>] containing the local identifiers of
  /// photos that are determined to be blurry.
  ///
  /// Returns an empty list if an error occurs or no blurry photos are found.
  Future<List<String>> scanForBlurryPhotos() async {
    try {
      // Invoke the method on the native side.
      final List<dynamic>? blurryPhotoIDs = await _channel.invokeMethod('scanForBlurryPhotos');

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
