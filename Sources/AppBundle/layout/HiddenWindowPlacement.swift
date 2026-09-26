import Foundation
import CoreGraphics

/// Minimize overlap of the entire parked window, not a few points at a corner.
/// Retain the usual one-point corner overlap so macOS accepts the offscreen frame.
func hiddenWindowOrigin(size: CGSize, preferred: CGRect, displays: [CGRect], inset: CGFloat = 1) -> CGPoint {
    var best = CGPoint(x: preferred.maxX - inset, y: preferred.maxY - inset)
    var bestArea = CGFloat.infinity
    var bestDistance = CGFloat.infinity
    func consider(_ point: CGPoint) {
        let frame = CGRect(origin: point, size: size)
        var area: CGFloat = 0
        for display in displays {
            let overlap = frame.intersection(display)
            if !overlap.isNull { area += overlap.width * overlap.height }
        }
        let dx = point.x - preferred.maxX
        let dy = point.y - preferred.maxY
        let distance = dx * dx + dy * dy
        if area < bestArea || (area == bestArea && distance < bestDistance) {
            best = point
            bestArea = area
            bestDistance = distance
        }
    }
    func considerCorners(_ frame: CGRect) {
        consider(CGPoint(x: frame.maxX - inset, y: frame.maxY - inset))
        consider(CGPoint(x: frame.minX + inset - size.width, y: frame.maxY - inset))
    }
    considerCorners(preferred)
    for display in displays { considerCorners(display) }
    return best
}
