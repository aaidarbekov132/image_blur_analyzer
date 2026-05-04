## 0.0.3

* Added native Android implementation of `scanForBlurryPhotos` using
  variance-of-Laplacian on MediaStore thumbnails.
* Returns numeric `MediaStore.Images.Media._ID` strings on Android (no
  `content://` prefix) and `PHAsset.localIdentifier` on iOS.
* Supports Android API 21+: uses `ContentResolver.loadThumbnail` on API 29+
  and `BitmapFactory` with `inSampleSize` fallback below.
* Added optional `androidThreshold` parameter (default `300.0`) to tune blur
  sensitivity on Android without touching native code.

## 0.0.2

* iOS-only release with `scanForBlurryPhotos` returning `PHAsset.localIdentifier`.

## 0.0.1

* TODO: Describe initial release.
