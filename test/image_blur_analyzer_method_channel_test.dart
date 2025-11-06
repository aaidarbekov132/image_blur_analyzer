import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_blur_analyzer/image_blur_analyzer_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelImageBlurAnalyzer platform = MethodChannelImageBlurAnalyzer();
  const MethodChannel channel = MethodChannel('image_blur_analyzer');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        return '42';
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
