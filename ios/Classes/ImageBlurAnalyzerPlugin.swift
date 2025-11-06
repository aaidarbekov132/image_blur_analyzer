import Flutter
import UIKit
import Photos
import CoreImage
import MetalKit

public class ImageBlurAnalyzer: NSObject, FlutterPlugin {

    // --- Configuration ---
    private let edgeIntensityThreshold: Float = 0.011
    private let analysisTargetSize = CGSize(width: 128, height: 128)
    // Adjust based on device capabilities, ProcessInfo.processInfo.activeProcessorCount * 2 might be a start
    private let maxConcurrentOperations = max(2, ProcessInfo.processInfo.activeProcessorCount)

    private let cachingBatchSize = 250
    // Batch size for *reporting* progress, not execution control
    private let progressUpdateBatchSize = 100

    // --- Core Image Context
    private let ciContext: CIContext = {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: metalDevice, options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        } else {
            return CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        }
    }()

    // --- Concurrency Control ---
    private lazy var processingQueue = DispatchQueue(label: "imageBlurAnalyzer.processingQueue", qos: .userInitiated, attributes: .concurrent)
    private lazy var semaphore = DispatchSemaphore(value: maxConcurrentOperations)

    // --- Caching Image Manager ---
    private lazy var imageManager: PHCachingImageManager = {
        let manager = PHCachingImageManager()
        // We don't need high-quality images, so we can disable this.
        manager.allowsCachingHighQualityImages = false
        return manager
    }()

    // --- Registration ---
    // This is the method Flutter calls to set up your plugin.
    // The `pluginClass` in pubspec.yaml points to this class.
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "imageBlurAnalyzer", binaryMessenger: registrar.messenger())
        let instance = ImageBlurAnalyzer()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    // --- Method Call Handling ---
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "scanForBlurryPhotos" else {
            result(FlutterMethodNotImplemented)
            return
        }
        // Use the dedicated processing queue
        processingQueue.async {
            self.fetchAndAnalyzePhotos(flutterResult: result)
        }
    }


    // --- Photo Fetching and Analysis ---
    private func fetchAndAnalyzePhotos(flutterResult: @escaping FlutterResult) {
        // Fetch all photos with clear sort order
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        let totalAssets = assets.count

        if totalAssets == 0 {
            // This will now also be the result if permissions are not granted
            DispatchQueue.main.async { flutterResult([String]()) }
            return
        }


        var blurredPhotoIDs: [String] = [] // Changed to [String]
        let resultsLock = NSLock()
        let finalGroup = DispatchGroup()

        // Options for the blur analysis request
        let analysisRequestOptions = PHImageRequestOptions()
        analysisRequestOptions.deliveryMode = .fastFormat
        analysisRequestOptions.resizeMode = .fast
        analysisRequestOptions.isNetworkAccessAllowed = false // Avoid network for analysis step

        var processedCount = 0
        let startTime = CFAbsoluteTimeGetCurrent()

        var assetsToCache = [PHAsset]()
        var currentCacheStartIndex = 0
        let cachingOptions = analysisRequestOptions.copy() as! PHImageRequestOptions

        // Pre-cache the first batch
        let initialBatchSize = min(totalAssets, cachingBatchSize)
        if initialBatchSize > 0 {
            let initialAssets = (0..<initialBatchSize).map { assets.object(at: $0) }
            imageManager.startCachingImages(for: initialAssets,
                                            targetSize: self.analysisTargetSize,
                                            contentMode: .aspectFit,
                                            options: cachingOptions)
        }

        for i in 0..<totalAssets {
            let needsCacheUpdate = i == currentCacheStartIndex + cachingBatchSize
            if needsCacheUpdate {
                // Stop caching the previous batch
                let prevBatchEndIndex = currentCacheStartIndex + cachingBatchSize
                let prevAssets = (currentCacheStartIndex..<prevBatchEndIndex).map { assets.object(at: $0) }
                imageManager.stopCachingImages(for: prevAssets,
                                            targetSize: self.analysisTargetSize,
                                            contentMode: .aspectFit,
                                            options: cachingOptions)
                
                // Start caching the next batch
                currentCacheStartIndex = i
                let nextBatchEndIndex = min(totalAssets, currentCacheStartIndex + cachingBatchSize)
                if currentCacheStartIndex < nextBatchEndIndex { // Ensure there are assets left
                    let nextAssets = (currentCacheStartIndex..<nextBatchEndIndex).map { assets.object(at: $0) }
                    imageManager.startCachingImages(for: nextAssets,
                                                    targetSize: self.analysisTargetSize,
                                                    contentMode: .aspectFit,
                                                    options: cachingOptions)
                }
            }

            let asset = assets.object(at: i)
            finalGroup.enter() // Enter group for each asset
            semaphore.wait()   // Wait if concurrent operations limit is reached

            // Submit analysis to the processing queue
            processingQueue.async { [weak self] in
                // Ensure `self` is valid within the async block
                guard let self = self else {
                    self?.semaphore.signal()
                    finalGroup.leave()
                    return
                }

                // Use autorelease pool for memory management within the async task
                autoreleasepool {
                    self.analyzePhoto(
                        asset: asset,
                        imageManager: self.imageManager,
                        analysisRequestOptions: analysisRequestOptions
                    ) { identifier in // Completion handler now only returns String?
                        // Process result
                        if let id = identifier {
                            resultsLock.lock()
                            blurredPhotoIDs.append(id) // Append the ID
                            resultsLock.unlock()
                        }

                        // Update progress safely
                        processedCount += 1
                        DispatchQueue.main.async {
                            if processedCount % self.progressUpdateBatchSize == 0 || processedCount == totalAssets {
                                let percentage = Int(Double(processedCount) / Double(totalAssets) * 100)
                                // You could send this progress back to Flutter
                                // using an EventChannel, but for now it just prints.
                                print("Blur analysis progress: \(percentage)%")
                            }
                        }

                        // Signal completion for this asset
                        self.semaphore.signal()
                        finalGroup.leave()
                    }
                } // end autoreleasepool
            } // end processingQueue.async
        } // end for loop

        // Wait for all assets to be processed and notify on the main thread
        finalGroup.notify(queue: .main) {
            self.imageManager.stopCachingImagesForAllAssets()
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            print("Blur analysis finished in \(duration) seconds.")
            flutterResult(blurredPhotoIDs) // Return the list of IDs
        }
    }

    // --- Individual Photo Analysis (Async) ---
    private func analyzePhoto(
        asset: PHAsset,
        imageManager: PHImageManager,
        analysisRequestOptions: PHImageRequestOptions,
        completion: @escaping (String?) -> Void // Updated completion signature
    ) {

        var requestID: PHImageRequestID? // Store request ID if needed for cancellation

        requestID = imageManager.requestImage(
            for: asset,
            targetSize: self.analysisTargetSize,
            contentMode: .aspectFit,
            options: analysisRequestOptions
        ) { [weak self] (image, info) in

            // Ensure 'self' is valid
            guard let self = self else {
                completion(nil) // Complete if self is nil
                return
            }

            // Check for degraded, error, or cancelled states
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            let isError = info?[PHImageErrorKey] != nil
            let isCancelled = (info?[PHImageCancelledKey] as? Bool) ?? false

            if isDegraded || isError || isCancelled {
                if isError || isCancelled {
                    completion(nil)
                }
                // If just degraded, do nothing - wait for the next callback
                return
            }

            // --- Final Image Received ---
            guard let cgImage = image?.cgImage else {
                completion(nil)
                return
            }

            // Perform blur detection
            let blurred = self.isBlurred(cgImage: cgImage)

            if blurred {
                // It's blurred, return the identifier
                completion(asset.localIdentifier)
            } else {
                // Not blurred, complete immediately
                completion(nil)
            }
        }
        // Optional: Could store requestID and cancel it if needed.
    }


    // --- Blur Detection Algorithm (Unchanged) ---
    private func isBlurred(cgImage: CGImage) -> Bool {
        // Wrap CIImage creation in autoreleasepool just in case
        return autoreleasepool {
            let inputImage = CIImage(cgImage: cgImage)

            guard let edgeFilter = CIFilter(name: "CIEdges") else { return false }
            edgeFilter.setValue(inputImage, forKey: kCIInputImageKey)

            guard let edgeOutputImage = edgeFilter.outputImage else { return false }

            let extentVector = CIVector(x: edgeOutputImage.extent.origin.x,
                                        y: edgeOutputImage.extent.origin.y,
                                        z: edgeOutputImage.extent.size.width,
                                        w: edgeOutputImage.extent.size.height)

            guard let avgFilter = CIFilter(name: "CIAreaAverage") else { return false }
            avgFilter.setValue(edgeOutputImage, forKey: kCIInputImageKey)
            avgFilter.setValue(extentVector, forKey: kCIInputExtentKey)

            guard let avgOutputImage = avgFilter.outputImage else { return false }

            // Render to a small bitmap to get the average pixel value
            var bitmap = [UInt8](repeating: 0, count: 4)
            self.ciContext.render(avgOutputImage,
                                  toBitmap: &bitmap,
                                  rowBytes: 4,
                                  bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                  format: .RGBA8,
                                  colorSpace: nil)

            // Average intensity across R, G, B channels
            let averageIntensity = (Float(bitmap[0]) + Float(bitmap[1]) + Float(bitmap[2])) / (3.0 * 255.0)

            // Compare against threshold
            return averageIntensity < self.edgeIntensityThreshold
        }
    }
}