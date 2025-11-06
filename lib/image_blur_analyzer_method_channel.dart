import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'image_blur_analyzer_platform_interface.dart';

/// An implementation of [ImageBlurAnalyzerPlatform] that uses method channels.
class MethodChannelImageBlurAnalyzer extends ImageBlurAnalyzerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('image_blur_analyzer');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
