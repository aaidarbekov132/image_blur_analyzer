# image_blur_analyzer

A Flutter plugin that scans the user's photo gallery and returns identifiers
of photos detected as blurry. Works on **iOS** and **Android**.

## Usage

```dart
import 'package:image_blur_analyzer/image_blur_analyzer.dart';

final ids = await ImageBlurAnalyzer().scanForBlurryPhotos();
```

The returned identifiers depend on the platform:

| Platform | Format                                      | Source                                   |
|----------|---------------------------------------------|------------------------------------------|
| iOS      | `PHAsset.localIdentifier` (UUID-like string) | Photos framework                         |
| Android  | Numeric MediaStore `_ID` as string           | `MediaStore.Images.Media._ID` (no `content://` prefix) |

## Permissions

The plugin does **not** request permissions itself. Request them in your app
before calling `scanForBlurryPhotos`, e.g. via
[`permission_handler`](https://pub.dev/packages/permission_handler).

### iOS
Add `NSPhotoLibraryUsageDescription` to `Info.plist`.

### Android
- API 33+: `READ_MEDIA_IMAGES`
- API 21–32: `READ_EXTERNAL_STORAGE`

These permissions are already declared in the plugin's `AndroidManifest.xml`,
so no manual merging is required. If access is missing, the call throws a
`PlatformException(code: 'PERMISSION_DENIED')`.

Minimum Android version: **API 21 (Android 5.0)**. On API 29+ the plugin
uses `ContentResolver.loadThumbnail()`; on older versions it falls back to
`BitmapFactory` with `inSampleSize` downscaling.

## How it works

- **iOS** uses Core Image (`CIEdges` + `CIAreaAverage`) on a 128×128 thumbnail
  and compares mean edge intensity to a threshold.
- **Android** uses the **variance of Laplacian** algorithm on a 128×128
  grayscale thumbnail (the classic Pech-Pacheco method): low variance means
  few sharp transitions, i.e. a blurry image.
