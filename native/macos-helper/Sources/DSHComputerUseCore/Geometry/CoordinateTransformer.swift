import Foundation
import CoreGraphics

/// Converts points between a local coordinate space (for example a single
/// display's point space) and the global top-left-origin space.
///
/// `origin` is the local space's top-left corner expressed in global
/// coordinates and may be negative for displays arranged left of or above the
/// primary display. `scaleX` / `scaleY` are the local-to-global multipliers and
/// may be negative to express a mirroring/flip.
public struct CoordinateTransformer: Equatable {
    public var origin: Point
    public var scaleX: Double
    public var scaleY: Double

    public init(origin: Point = Point(x: 0, y: 0), scaleX: Double = 1, scaleY: Double = 1) {
        self.origin = origin
        self.scaleX = scaleX
        self.scaleY = scaleY
    }

    /// Maps a top-left-origin local point into global coordinates.
    public func toGlobal(_ local: Point) -> Point {
        Point(
            x: origin.x + local.x * scaleX,
            y: origin.y + local.y * scaleY
        )
    }

    /// Maps a global point back into the local coordinate space.
    public func toLocal(_ global: Point) -> Point {
        Point(
            x: (global.x - origin.x) / scaleX,
            y: (global.y - origin.y) / scaleY
        )
    }

    /// Converts a Vision-style normalized bounding box (origin at bottom-left,
    /// values in `0...1`) into a pixel-space rectangle with a top-left origin,
    /// given the pixel size of the source image.
    public static func rectFromNormalizedBottomLeft(box: CGRect, imageSize: CGSize) -> CGRect {
        let x = box.minX * imageSize.width
        let y = (1.0 - box.maxY) * imageSize.height
        let width = box.width * imageSize.width
        let height = box.height * imageSize.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
