import Foundation
import Vision
import ImageIO

/// Runs Vision OCR and returns recognized text runs with normalized,
/// top-left-origin frames (in the source image's pixel space).
public final class VisionOCRService {
    public init() {}

    /// Recognizes text in an in-memory `CGImage`, returning pixel-space
    /// top-left-origin frames.
    public func recognize(cgImage: CGImage, languages: [String] = []) throws -> [OCRTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = languages.isEmpty
        if !languages.isEmpty {
            let supported = try request.supportedRecognitionLanguages()
            let unsupported = languages.filter { !supported.contains($0) }
            guard unsupported.isEmpty else {
                throw AgentError.ocr("Unsupported OCR languages: \(unsupported.joined(separator: ", "))")
            }
            request.recognitionLanguages = languages
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        return (request.results ?? []).map { observation in
            let rect = CoordinateTransformer.rectFromNormalizedBottomLeft(
                box: observation.boundingBox,
                imageSize: imageSize
            )
            let candidate = observation.topCandidates(1).first
            return OCRTextObservation(
                text: candidate?.string ?? "",
                confidence: Double(candidate?.confidence ?? 0),
                frame: Rect(rect)
            )
        }
    }

    /// Recognizes text in an image file, returning an `OCRResult` whose frames
    /// are relative to the image (top-left origin, pixels).
    public func recognize(imageURL: URL, languages: [String] = []) throws -> OCRResult {
        let start = Date()
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw AgentError.ocr("Cannot read image at \(imageURL.path)")
        }

        let observations = try recognize(cgImage: image, languages: languages)

        return OCRResult(
            observations: observations,
            imageSize: Size(width: Double(image.width), height: Double(image.height)),
            durationMs: Date().timeIntervalSince(start) * 1000.0
        )
    }
}
