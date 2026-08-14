import XCTest
import CoreGraphics
import DSHComputerUseCore

final class CoordinateConversionTests: XCTestCase {
    func testIdentityTransformer() {
        let transformer = CoordinateTransformer()
        XCTAssertEqual(transformer.toGlobal(Point(x: 5, y: 7)), Point(x: 5, y: 7))
    }

    func testPositiveOriginAndScale() {
        let transformer = CoordinateTransformer(origin: Point(x: 100, y: 50), scaleX: 2, scaleY: 2)
        XCTAssertEqual(transformer.toGlobal(Point(x: 10, y: 20)), Point(x: 120, y: 90))
    }

    func testNegativeOrigin() {
        // A display arranged left of and above the primary has a negative origin.
        let transformer = CoordinateTransformer(origin: Point(x: -1920, y: -1080), scaleX: 1, scaleY: 1)
        XCTAssertEqual(transformer.toGlobal(Point(x: 0, y: 0)), Point(x: -1920, y: -1080))
        XCTAssertEqual(transformer.toGlobal(Point(x: 960, y: 540)), Point(x: -960, y: -540))
    }

    func testNegativeScaleMirrors() {
        let transformer = CoordinateTransformer(origin: Point(x: 0, y: 0), scaleX: -1, scaleY: 1)
        XCTAssertEqual(transformer.toGlobal(Point(x: 100, y: 50)), Point(x: -100, y: 50))
    }

    func testToLocalRoundTrip() {
        let transformer = CoordinateTransformer(origin: Point(x: -500, y: 300), scaleX: 3, scaleY: -2)
        let global = Point(x: 123.4, y: -567.8)
        let local = transformer.toLocal(global)
        let backToGlobal = transformer.toGlobal(local)
        XCTAssertEqual(backToGlobal.x, global.x, accuracy: 0.000_001)
        XCTAssertEqual(backToGlobal.y, global.y, accuracy: 0.000_001)
    }

    func testNormalizedBottomLeftBoxFullImage() {
        let rect = CoordinateTransformer.rectFromNormalizedBottomLeft(
            box: CGRect(x: 0, y: 0, width: 1, height: 1),
            imageSize: CGSize(width: 1920, height: 1080)
        )
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    func testNormalizedBottomLeftBoxQuarter() {
        // A box in the bottom-left quadrant (Vision origin) maps to the
        // bottom-left in top-left space only after the vertical flip.
        let rect = CoordinateTransformer.rectFromNormalizedBottomLeft(
            box: CGRect(x: 0, y: 0, width: 0.5, height: 0.5),
            imageSize: CGSize(width: 100, height: 100)
        )
        XCTAssertEqual(rect, CGRect(x: 0, y: 50, width: 50, height: 50))
    }

    func testFlipVertical() {
        let flipped = Geometry.flipVertical(
            CGRect(x: 10, y: 20, width: 30, height: 40),
            containerHeight: 100
        )
        XCTAssertEqual(flipped, CGRect(x: 10, y: 40, width: 30, height: 40))
    }

    func testGlobalRectFromPixelsAtRetinaScale() {
        // 2x Retina capture of the main display (origin 0,0): 100x50 pixels
        // becomes 50x25 points.
        let rect = Geometry.globalRect(
            pixelRect: CGRect(x: 200, y: 100, width: 100, height: 50),
            origin: CGPoint(x: 0, y: 0),
            scale: 2
        )
        XCTAssertEqual(rect, CGRect(x: 100, y: 50, width: 50, height: 25))
    }

    func testGlobalRectFromPixelsWithNegativeOrigin() {
        // A secondary display arranged left of the primary (negative x origin).
        let rect = Geometry.globalRect(
            pixelRect: CGRect(x: 400, y: 200, width: 80, height: 40),
            origin: CGPoint(x: -1920, y: 0),
            scale: 2
        )
        XCTAssertEqual(rect, CGRect(x: -1720, y: 100, width: 40, height: 20))
    }
}
