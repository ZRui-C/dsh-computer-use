import Foundation
import CoreGraphics

/// Pure helpers that merge OCR observations into the flat observation node
/// list, converting pixel-space boxes to global top-left points and deduping
/// text already represented by an AX node.
public enum NodeMerger {
    /// Converts OCR observations (pixel rects) into flat `"ocr"`-sourced nodes
    /// with global top-left point frames, dropping any whose text is already
    /// represented by an AX node.
    public static func ocrNodes(
        from observations: [OCRTextObservation],
        origin: CGPoint,
        scale: CGFloat,
        existingAXNodes: [AXNode],
        depth: Int = 0
    ) -> [AXNode] {
        var result: [AXNode] = []
        for observation in observations {
            let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if existingAXNodes.contains(where: { $0.textMatches(text) }) { continue }

            let globalFrame = Geometry.globalRect(
                pixelRect: observation.frame.cgRect,
                origin: origin,
                scale: scale
            )
            result.append(AXNode(
                role: "AXStaticText",
                name: text,
                value: text,
                description: nil,
                enabled: nil,
                focused: nil,
                selected: nil,
                secure: false,
                actions: [],
                frame: Rect(globalFrame),
                target: nil,
                depth: depth,
                source: "ocr"
            ))
        }
        return result
    }
}
