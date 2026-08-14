import Foundation

/// A single recognized text run with a pixel-space, top-left-origin frame.
public struct OCRTextObservation: Codable, Equatable {
    public var text: String
    public var confidence: Double
    public var frame: Rect

    public init(text: String, confidence: Double, frame: Rect) {
        self.text = text
        self.confidence = confidence
        self.frame = frame
    }
}

/// The result of an OCR pass over an image file.
public struct OCRResult: Codable, Equatable {
    public var observations: [OCRTextObservation]
    public var imageSize: Size?
    public var durationMs: Double?

    public init(
        observations: [OCRTextObservation],
        imageSize: Size? = nil,
        durationMs: Double? = nil
    ) {
        self.observations = observations
        self.imageSize = imageSize
        self.durationMs = durationMs
    }
}

/// Parameters for the `ocrFile` method.
public struct OCRFileRequest: Codable, Equatable {
    public var path: String

    public init(path: String) {
        self.path = path
    }
}
