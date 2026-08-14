import Foundation
import CoreGraphics

/// A serializable top-left-origin point. Global coordinates used by the helper
/// are normalized to a top-left origin, matching AX frames and CGEvent cursor
/// positions.
public struct Point: Codable, Equatable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.x = Double(point.x)
        self.y = Double(point.y)
    }

    public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// A serializable size.
public struct Size: Codable, Equatable, Hashable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public init(_ size: CGSize) {
        self.width = Double(size.width)
        self.height = Double(size.height)
    }

    public var cgSize: CGSize { CGSize(width: width, height: height) }
}

/// A serializable top-left-origin rectangle.
public struct Rect: Codable, Equatable, Hashable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.width)
        self.height = Double(rect.height)
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// Small, pure geometry helpers kept free of any framework-global state so they
/// can be exercised by the unit tests.
public enum Geometry {
    /// Flips a bottom-left-origin rectangle (AppKit / Vision convention) into
    /// the equivalent top-left-origin rectangle within a container of the given
    /// height.
    public static func flipVertical(_ rect: CGRect, containerHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: containerHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// Converts a pixel-space (top-left) rectangle within a captured image into
    /// global top-left points, given the capture's global origin (points) and
    /// pixel scale (pixels per point).
    public static func globalRect(pixelRect: CGRect, origin: CGPoint, scale: CGFloat) -> CGRect {
        CGRect(
            x: origin.x + pixelRect.minX / scale,
            y: origin.y + pixelRect.minY / scale,
            width: pixelRect.width / scale,
            height: pixelRect.height / scale
        )
    }
}
