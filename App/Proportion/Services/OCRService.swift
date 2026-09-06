import Foundation
import UIKit
import Vision

/// On-device text recognition for photographed recipes and screenshots.
///
/// Runs entirely locally. The recognised text — never the image — is what
/// goes to the parser, so a cookbook page stays on the phone. Falls back to
/// sending the image only when recognition is too weak to be useful and the
/// user has model parsing enabled.
struct OCRService: Sendable {
    struct Result: Sendable {
        var text: String
        /// Mean recognition confidence 0…1 across all lines.
        var confidence: Double
        var lineCount: Int

        /// Below this the text is likely garbage and the vision path is a better bet.
        var isUsable: Bool { confidence >= 0.5 && lineCount >= 3 }
    }

    func recognizeText(in image: UIImage) async throws -> Result {
        guard let cgImage = image.cgImage else { throw OCRError.invalidImage }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                var lines: [String] = []
                var confidences: [Double] = []
                for observation in observations {
                    guard let candidate = observation.topCandidates(1).first else { continue }
                    lines.append(candidate.string)
                    confidences.append(Double(candidate.confidence))
                }
                let mean = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
                continuation.resume(returning: Result(
                    text: lines.joined(separator: "\n"),
                    confidence: mean,
                    lineCount: lines.count))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "en-GB"]

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: Self.orientation(for: image.imageOrientation))
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Recognises several photos (e.g. a two-page spread) into one text.
    func recognizeText(in images: [UIImage]) async throws -> Result {
        var texts: [String] = []
        var confidences: [Double] = []
        var lines = 0
        for image in images {
            let result = try await recognizeText(in: image)
            texts.append(result.text)
            confidences.append(result.confidence)
            lines += result.lineCount
        }
        let mean = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
        return Result(text: texts.joined(separator: "\n\n"), confidence: mean, lineCount: lines)
    }

    private static func orientation(for orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    enum OCRError: Error {
        case invalidImage
    }
}

extension UIImage {
    /// JPEG data scaled so the longest edge is at most `maxEdge` points —
    /// enough for a hero image or a vision request, without shipping a
    /// 12-megapixel photo anywhere.
    func downsizedJPEGData(maxEdge: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return jpegData(compressionQuality: quality) }
        let scale = maxEdge / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }
}
