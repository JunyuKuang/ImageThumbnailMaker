//
//  ImageThumbnailMaker.swift
//
//  Created by Jonny Kuang on 1/4/20.
//  Copyright © 2020 Jonny Kuang. All rights reserved.
//

@preconcurrency import ImageIO
import UIKit
import UniformTypeIdentifiers

public class ImageThumbnailMaker {
    
    public let content: Content
    public let configuration: Configuration
    
    public init(content: Content, configuration: Configuration) {
        self.content = content
        self.configuration = configuration
    }
    
    private var cachedOriginalImageSize: CGSize?
}

public extension ImageThumbnailMaker {
    
    convenience init(data: Data, configuration: Configuration = .init()) {
        self.init(content: .data(data), configuration: configuration)
    }
    
    convenience init(fileURL: URL, configuration: Configuration = .init()) {
        self.init(content: .fileURL(fileURL), configuration: configuration)
    }
    
    enum Content {
        case data(Data)
        case fileURL(URL)
    }
    
    enum ScaleMode {
        case fill
        case fit
    }
    
    struct Configuration : Equatable {
        /// If the original image size is smaller, this value will be ignored.
        public var thumbnailSize: CGSize?
        public var scale: CGFloat
        public var scaleMode: ScaleMode
        /// Always make static thumbnails if this value is false.
        public var allowsGIF: Bool
        /// If number of GIF frames exceeded, a static image will be produced instead.
        /// Default to nil which means no limit.
        /// Setting a non-nil value helps avoid exceeding memory limit when loading faulty GIFs.
        public var maxGIFFrames: Int?
        
        public init(thumbnailSize: CGSize? = nil, scale: CGFloat = 1, scaleMode: ScaleMode = .fill, allowsGIF: Bool = false, maxGIFFrames: Int? = nil) {
            self.thumbnailSize = thumbnailSize
            self.scale = scale
            self.scaleMode = scaleMode
            self.allowsGIF = allowsGIF
            self.maxGIFFrames = maxGIFFrames
        }
    }
    
    func prepareThumbnail() async -> UIImage? {
        preparingThumbnail()
    }
    
    func preparingThumbnail() -> UIImage? {
        guard let imageSource = makeImageSource() else {
            return nil
        }
        let maxPointSize = calculateMaxPointSize(originalSize: originalImageSize(with: imageSource))
        
        if configuration.allowsGIF,
           CGImageSourceGetType(imageSource) as String? == UTType.gif.identifier,
           let image = processGIF(imageSource: imageSource, maxPointSize: maxPointSize)
        {
            return image
        }
        let index = CGImageSourceGetPrimaryImageIndex(imageSource)
        return makeThumbnail(withImageSource: imageSource, imageIndex: index, maxPointSize: maxPointSize)
    }
    
    func originalImageSize() -> CGSize? {
        if let cachedOriginalImageSize {
            return cachedOriginalImageSize
        }
        guard let imageSource = makeImageSource() else { return nil }
        return originalImageSize(with: imageSource)
    }
    
    /// Rotate the image by modifying the metadata.
    /// If supplied image is in PNG format, it will be converted to JPEG format.
    static func rotateImage(content: Content, clockwise: Bool) -> Data? {
        ImageThumbnailMaker(content: content, configuration: .init())._rotateOrFlipImage(rotate: true, clockwise: clockwise)
    }
    
    /// Flip the image horizontally by modifying the metadata.
    /// If supplied image is in PNG format, it will be converted to JPEG format.
    static func flipImage(content: Content) -> Data? {
        ImageThumbnailMaker(content: content, configuration: .init())._rotateOrFlipImage(rotate: false)
    }
    
    private func _rotateOrFlipImage(rotate: Bool, clockwise: Bool = false) -> Data? {
        guard let source = makeImageSource(), var imageType = CGImageSourceGetType(source) else {
            return nil
        }
        let index = CGImageSourceGetPrimaryImageIndex(source)
        
        let currentOrientation: CGImagePropertyOrientation = {
            guard let metadata = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let currentOrientationRaw = metadata[kCGImagePropertyOrientation] as? UInt32,
                  let currentOrientation = CGImagePropertyOrientation(rawValue: currentOrientationRaw)
            else {
                return .up
            }
            return currentOrientation
        }()
        let newOrientation: CGImagePropertyOrientation = {
            if rotate {
                switch currentOrientation {
                case .up:            return clockwise ? .right         : .left
                case .right:         return clockwise ? .down          : .up
                case .down:          return clockwise ? .left          : .right
                case .left:          return clockwise ? .up            : .down
                    
                case .upMirrored:    return clockwise ? .rightMirrored : .leftMirrored
                case .rightMirrored: return clockwise ? .downMirrored  : .upMirrored
                case .downMirrored:  return clockwise ? .leftMirrored  : .rightMirrored
                case .leftMirrored:  return clockwise ? .upMirrored    : .downMirrored
                    
                @unknown default:
                    assertionFailure()
                    return .up
                }
            } else {
                switch currentOrientation {
                case .up: return .upMirrored
                case .upMirrored: return .up
                case .down: return .downMirrored
                case .downMirrored: return .down
                case .left: return .rightMirrored
                case .leftMirrored: return .right
                case .right: return .leftMirrored
                case .rightMirrored: return .left
                    
                @unknown default:
                    assertionFailure()
                    return .upMirrored
                }
            }
        }()
        
        let destinationImageData = NSMutableData()
        
        if imageType as String == UTType.png.identifier {
            imageType = UTType.jpeg.identifier as CFString
        }
        guard let imageDestination = CGImageDestinationCreateWithData(destinationImageData as CFMutableData, imageType, 1, nil) else {
            return nil
        }
        let options = [
            kCGImagePropertyOrientation: newOrientation.rawValue,
            kCGImageDestinationPreserveGainMap: true,
        ] as CFDictionary
        
        CGImageDestinationAddImageFromSource(imageDestination, source, index, options)
        
        guard CGImageDestinationFinalize(imageDestination) else {
            assertionFailure()
            return nil
        }
        return destinationImageData as Data
    }
}

private extension ImageThumbnailMaker {
    
    static let imageSourceOptions = [kCGImageSourceShouldCache as String: false] as CFDictionary
    
    func makeImageSource() -> CGImageSource? {
        let imageSource: CGImageSource?
        let options = Self.imageSourceOptions
        
        switch content {
        case .data(let data):
            imageSource = CGImageSourceCreateWithData(data as CFData, options)
            
        case .fileURL(let fileURL):
            guard fileURL.isFileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }
            imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, options)
        }
        return imageSource
    }
    
    func makeThumbnail(withImageSource imageSource: CGImageSource, imageIndex index: Int, maxPointSize: CGFloat?) -> UIImage? {
        let maxPointSize = maxPointSize ?? 1_000_000
        
        let options: [CFString : Any] = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: round(maxPointSize * configuration.scale),
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, index, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: thumbnail)
    }
    
    func originalImageSize(with imageSource: CGImageSource) -> CGSize? {
        if let cachedOriginalImageSize {
            return cachedOriginalImageSize
        }
        let index = CGImageSourceGetPrimaryImageIndex(imageSource)
        let options = Self.imageSourceOptions
        
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, options) as? [String : Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight as String] as? CGFloat
        else {
            return nil
        }
        let rotatedOrientations: [CGImagePropertyOrientation] = [.left, .leftMirrored, .right, .rightMirrored]
        let size: CGSize
        
        if let orientationValue = properties[kCGImagePropertyOrientation as String] as? UInt32,
           let orientation = CGImagePropertyOrientation(rawValue: orientationValue),
           rotatedOrientations.contains(orientation)
        {
            size = CGSize(width: height, height: width)
        } else {
            size = CGSize(width: width, height: height)
        }
        cachedOriginalImageSize = size
        return size
    }
    
    func calculateMaxPointSize(originalSize: CGSize?) -> CGFloat? {
        guard let thumbnailSize = configuration.thumbnailSize else {
            return nil
        }
        switch configuration.scaleMode {
        case .fill:
            if let originalSize = originalSize, originalSize.height > 0, thumbnailSize.height > 0 {
                let originalRatio = originalSize.width / originalSize.height
                let thumbnailRatio = thumbnailSize.width / thumbnailSize.height
                
                if originalRatio < thumbnailRatio {
                    return thumbnailSize.width / min(1, originalRatio)
                } else {
                    return thumbnailSize.height * max(1, originalRatio)
                }
            } else {
                fallthrough
            }
        case .fit:
            return max(thumbnailSize.width, thumbnailSize.height)
        }
    }
}

// MARK: - GIF
private extension ImageThumbnailMaker {
    
    func processGIF(imageSource: CGImageSource, maxPointSize: CGFloat?) -> UIImage? {
        let count = CGImageSourceGetCount(imageSource)
        guard count > 1 else {
            return nil
        }
        if let maxCount = configuration.maxGIFFrames, count > maxCount {
            return nil
        }
        var imagesAndFrameDurations = [(UIImage, Int)]()
        
        for index in 0..<count {
            if let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [String : Any],
               let gifInfo = properties[kCGImagePropertyGIFDictionary as String] as? [String : Any],
               let frameDuration = gifInfo[kCGImagePropertyGIFDelayTime as String] as? Double,
               frameDuration > 0,
               let image = makeThumbnail(withImageSource: imageSource, imageIndex: index, maxPointSize: maxPointSize)
            {
                imagesAndFrameDurations.append((image, Int(frameDuration * 1000)))
            }
        }
        if imagesAndFrameDurations.isEmpty {
            return nil
        }
        let sumDurations = imagesAndFrameDurations.map { $0.1 }.reduce(0, +)
        let baseFrameRate = greatestCommonDivisor(of: imagesAndFrameDurations.map { $0.1 })
        
        var images = [UIImage]()
        for (image, frameDuration) in imagesAndFrameDurations {
            for _ in 0 ..< frameDuration / baseFrameRate {
                images.append(image)
            }
        }
        return UIImage.animatedImage(with: images, duration: TimeInterval(sumDurations) / 1000)
    }
    
    func greatestCommonDivisor(of values: [Int]) -> Int {
        if values.isEmpty {
            return 1
        }
        let values = values.sorted(by: >)
        var gcd = values.last!
        for value in values {
            gcd = greatestCommonDivisor(bigValue: value, smallValue: gcd)
        }
        return gcd
    }
    
    func greatestCommonDivisor(bigValue: Int, smallValue: Int) -> Int {
        let remainder = bigValue % smallValue
        return remainder == 0 ? smallValue : greatestCommonDivisor(bigValue: smallValue, smallValue: remainder)
    }
}
