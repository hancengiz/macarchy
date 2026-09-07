import Foundation

/// Geometry is independent of AX: reveal the focused column with the smallest scroll.
struct ScrollingViewport {
    let starts: [CGFloat]
    let sizes: [CGFloat]
    let offset: CGFloat
    let visible: [Bool]

    init(sizes requestedSizes: [CGFloat], extent: CGFloat, gap: CGFloat, focusedIndex: Int, previousOffset: CGFloat) {
        let extent = max(1, extent)
        let gap = max(0, gap)
        let sizes = requestedSizes.map { min(max(1, $0), extent) }
        self.sizes = sizes
        var cursor: CGFloat = 0
        var starts: [CGFloat] = []
        for size in sizes {
            starts.append(cursor)
            cursor += size + gap
        }
        self.starts = starts
        let maxOffset = max(0, cursor - gap - extent)
        var offset = min(max(0, previousOffset), maxOffset)
        if sizes.indices.contains(focusedIndex) {
            let start = starts[focusedIndex]
            let end = start + sizes[focusedIndex]
            if start < offset { offset = start }
            if end > offset + extent { offset = end - extent }
        }
        self.offset = offset
        // Keep partial neighbors at their full size; the display edge clips them naturally.
        visible = sizes.indices.map { starts[$0] < offset + extent && starts[$0] + sizes[$0] > offset }
    }
}
