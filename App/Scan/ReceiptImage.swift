import UIKit
import ImageIO

/// Prepares a scanned receipt for storage. Receipts are text on white, so a
/// bounded long edge and moderate JPEG quality keep them legible while capping
/// the blob SwiftData writes to disk. Downsampling goes through ImageIO so a
/// large capture is never fully decoded into memory at full resolution.
enum ReceiptImage {
    static func forStorage(_ image: UIImage, maxPixel: CGFloat = 2200, quality: CGFloat = 0.75) -> Data? {
        guard let full = image.jpegData(compressionQuality: 1.0) else { return nil }
        return downsample(full, maxPixel: maxPixel, quality: quality)
            // Fall back to a plain re-encode if thumbnailing fails for any reason.
            ?? image.jpegData(compressionQuality: quality)
    }

    private static func downsample(_ data: Data, maxPixel: CGFloat, quality: CGFloat) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: quality)
    }
}
