import 'package:flutter_test/flutter_test.dart';
import 'package:image_blur_analyzer/image_blur_analyzer.dart';
import 'package:image_blur_analyzer/image_blur_analyzer_platform_interface.dart';
import 'package:image_blur_analyzer/image_blur_analyzer_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockImageBlurAnalyzerPlatform
    with MockPlatformInterfaceMixin
    implements ImageBlurAnalyzerPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final ImageBlurAnalyzerPlatform initialPlatform = ImageBlurAnalyzerPlatform.instance;

  test('$MethodChannelImageBlurAnalyzer is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelImageBlurAnalyzer>());
  });

  test('getPlatformVersion', () async {
    ImageBlurAnalyzer imageBlurAnalyzerPlugin = ImageBlurAnalyzer();
    MockImageBlurAnalyzerPlatform fakePlatform = MockImageBlurAnalyzerPlatform();
    ImageBlurAnalyzerPlatform.instance = fakePlatform;

    expect(await imageBlurAnalyzerPlugin.getPlatformVersion(), '42');
  });
}
