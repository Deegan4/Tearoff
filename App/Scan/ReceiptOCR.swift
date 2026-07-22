import Foundation
import Vision

enum ReceiptOCRError: Error { case badImage }

/// On-device text recognition. Takes encoded image bytes (Sendable) rather
/// than a UIImage/CGImage so it can hop to a background queue cleanly under
/// strict concurrency. Returns recognized lines in top-to-bottom order.
enum ReceiptOCR {
    static func recognizeLines(from imageData: Data) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                let handler = VNImageRequestHandler(data: imageData, options: [:])
                do {
                    try handler.perform([request])
                    let observations = request.results ?? []
                    // Vision's y-origin is bottom-left, so higher midY == higher
                    // on the page. Sort descending to read top-to-bottom.
                    let lines = observations
                        .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                        .compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: lines)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
