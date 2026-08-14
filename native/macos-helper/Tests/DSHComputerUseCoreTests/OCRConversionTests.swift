import XCTest
import CoreGraphics
import DSHComputerUseCore

final class OCRConversionTests: XCTestCase {
    func testBottomLeftBoxConversion() {
        // A Vision bounding box occupying the visual top-left quarter of the
        // image (normalized, bottom-left origin: y from 0.75..1.0) becomes the
        // top-left quarter in top-left pixel space.
        let rect = CoordinateTransformer.rectFromNormalizedBottomLeft(
            box: CGRect(x: 0, y: 0.75, width: 0.25, height: 0.25),
            imageSize: CGSize(width: 400, height: 200)
        )
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 100, height: 50))
    }

    func testBottomLeftBoxCentered() {
        let rect = CoordinateTransformer.rectFromNormalizedBottomLeft(
            box: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            imageSize: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(rect, CGRect(x: 25, y: 25, width: 50, height: 50))
    }

    func testOCRTextObservationCodable() throws {
        let observation = OCRTextObservation(
            text: "Hello, world!",
            confidence: 0.99,
            frame: Rect(x: 0, y: 0, width: 100, height: 50)
        )
        let data = try JSONEncoder().encode(observation)
        let decoded = try JSONDecoder().decode(OCRTextObservation.self, from: data)
        XCTAssertEqual(decoded, observation)
    }

    func testOCRResultCodable() throws {
        let result = OCRResult(
            observations: [
                OCRTextObservation(text: "line one", confidence: 0.9, frame: Rect(x: 0, y: 0, width: 10, height: 10)),
                OCRTextObservation(text: "line two", confidence: 0.8, frame: Rect(x: 0, y: 10, width: 10, height: 10)),
            ],
            imageSize: Size(width: 1920, height: 1080)
        )
        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(OCRResult.self, from: data)
        XCTAssertEqual(decoded, result)
    }

    func testPixelRectMatchesImageSizeBounds() {
        // A full-frame normalized box must always land inside the image bounds.
        let rect = CoordinateTransformer.rectFromNormalizedBottomLeft(
            box: CGRect(x: 0, y: 0, width: 1, height: 1),
            imageSize: CGSize(width: 640, height: 480)
        )
        XCTAssertEqual(rect.minX, 0)
        XCTAssertEqual(rect.minY, 0)
        XCTAssertEqual(rect.maxX, 640)
        XCTAssertEqual(rect.maxY, 480)
    }
}
