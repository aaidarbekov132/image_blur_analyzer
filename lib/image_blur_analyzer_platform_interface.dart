import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'image_blur_analyzer_method_channel.dart';

abstract class ImageBlurAnalyzerPlatform extends PlatformInterface {
  /// Constructs a ImageBlurAnalyzerPlatform.
  ImageBlurAnalyzerPlatform() : super(token: _token);

  static final Object _token = Object();

  static ImageBlurAnalyzerPlatform _instance = MethodChannelImageBlurAnalyzer();

  /// The default instance of [ImageBlurAnalyzerPlatform] to use.
  ///
  /// Defaults to [MethodChannelImageBlurAnalyzer].
  static ImageBlurAnalyzerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ImageBlurAnalyzerPlatform] when
  /// they register themselves.
  static set instance(ImageBlurAnalyzerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
