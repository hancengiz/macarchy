import AppKit
import Common

/// Captures split weights once so a drag never compounds its own previous deltas.
@MainActor
struct ManagedResize {
    private struct Axis {
        let node: TreeNode
        let parent: TilingContainer
        let size: CGFloat
        let neighbor: TreeNode?
        let neighborSize: CGFloat
    }

    let rect: Rect
    let fromLeft: Bool
    let fromTop: Bool
    private let horizontal: Axis?
    private let vertical: Axis?

    init(window: Window, rect: Rect, fromLeft: Bool, fromTop: Bool) {
        self.rect = rect
        self.fromLeft = fromLeft
        self.fromTop = fromTop
        horizontal = Self.axis(window, .h, fromLeft)
        vertical = Self.axis(window, .v, fromTop)
    }

    private static func axis(_ window: Window, _ orientation: Orientation, _ negative: Bool) -> Axis? {
        for node in window.parentsWithSelf {
            guard let parent = node.parent as? TilingContainer, parent.orientation == orientation else { continue }
            if parent.layout == .scrolling {
                let size = node.scrollingSize ?? node.lastAppliedLayoutPhysicalRect?.getDimension(orientation)
                if let size { return Axis(node: node, parent: parent, size: size, neighbor: nil, neighborSize: 0) }
            }
            if parent.layout == .tiles, parent.children.count > 1, let index = node.ownIndex {
                let preferred = index + (negative ? -1 : 1)
                let other = parent.children.indices.contains(preferred) ? preferred : index + (negative ? 1 : -1)
                let neighbor = parent.children[other]
                return Axis(node: node, parent: parent, size: node.getWeight(orientation),
                            neighbor: neighbor, neighborSize: neighbor.getWeight(orientation))
            }
        }
        return nil
    }

    func apply(width: CGFloat, height: CGFloat) {
        apply(horizontal, delta: width - rect.width)
        apply(vertical, delta: height - rect.height)
    }

    private func apply(_ axis: Axis?, delta: CGFloat) {
        guard let axis, axis.node.parent === axis.parent else { return }
        if axis.parent.layout == .scrolling {
            guard let extent = axis.parent.lastAppliedLayoutPhysicalRect?.getDimension(axis.parent.orientation) else { return }
            axis.node.scrollingSize = (axis.size + delta).coerce(in: min(100, extent) ... max(100, extent))
        } else if axis.parent.layout == .tiles, let neighbor = axis.neighbor, neighbor.parent === axis.parent {
            let minimum = min(100, min(axis.size, axis.neighborSize))
            let delta = delta.coerce(in: minimum - axis.size ... axis.neighborSize - minimum)
            axis.node.setWeight(axis.parent.orientation, axis.size + delta)
            neighbor.setWeight(axis.parent.orientation, axis.neighborSize - delta)
        }
    }

    func draggedRect(delta: CGPoint) -> Rect {
        let width = max(100, rect.width + (fromLeft ? -delta.x : delta.x))
        let height = max(100, rect.height + (fromTop ? -delta.y : delta.y))
        return Rect(topLeftX: fromLeft ? rect.maxX - width : rect.minX,
                    topLeftY: fromTop ? rect.maxY - height : rect.minY, width: width, height: height)
    }
}

@MainActor
func adoptNativeWindowResize(_ window: Window) async throws -> Bool {
    guard config.adoptNativeWindowResize, !window.isFullscreen, !window.isOutsideScrollingViewport,
          window.parent is TilingContainer, let expected = window.lastAppliedLayoutPhysicalRect,
          let actual = try await window.getAxRect(.cancellable),
          abs(actual.width - expected.width) > 2 || abs(actual.height - expected.height) > 2 else { return false }
    let resize = ManagedResize(window: window, rect: expected,
                               fromLeft: abs(actual.minX - expected.minX) > 2,
                               fromTop: abs(actual.minY - expected.minY) > 2)
    resize.apply(width: actual.width, height: actual.height)
    return true
}
