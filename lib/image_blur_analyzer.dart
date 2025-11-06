
import 'image_blur_analyzer_platform_interface.dart';

class ImageBlurAnalyzer {
  Future<String?> getPlatformVersion() {
    return ImageBlurAnalyzerPlatform.instance.getPlatformVersion();
  }
}
