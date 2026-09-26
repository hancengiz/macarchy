import AppKit
import Common

struct ResizeCommand: Command {
    let args: ResizeCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }

        let candidates = target.windowOrNil?.parentsWithSelf
            .filter { ($0.parent as? TilingContainer).map { $0.layout == .tiles || $0.layout == .scrolling } == true }
            ?? []

        let orientation: Orientation?
        let parent: TilingContainer?
        let node: TreeNode?
        switch args.dimension.val {
            case .width:
                orientation = .h
                node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
                parent = node?.parent as? TilingContainer
            case .height:
                orientation = .v
                node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
                parent = node?.parent as? TilingContainer
            case .smart:
                node = candidates.first
                parent = node?.parent as? TilingContainer
                orientation = parent?.orientation
            case .smartOpposite:
                orientation = (candidates.first?.parent as? TilingContainer)?.orientation.opposite
                node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
                parent = node?.parent as? TilingContainer
        }
        guard let parent else {
            return await resizeFloatingWindow(target: target, io)
        }
        guard let orientation else { return .fail }
        guard let node else { return .fail }
        if parent.layout == .scrolling {
            guard let extent = parent.lastAppliedLayoutPhysicalRect?.getDimension(orientation) else { return .fail }
            let current = node.scrollingSize ?? extent * CGFloat(config.scrollingColumnWidth) / 100
            let size: CGFloat = switch args.units.val {
                case .set(let unit): CGFloat(unit)
                case .add(let unit): current + CGFloat(unit)
                case .subtract(let unit): current - CGFloat(unit)
            }
            node.scrollingSize = size.coerce(in: min(100, extent) ... extent)
            return .succ
        }
        let diff: CGFloat = switch args.units.val {
            case .set(let unit): CGFloat(unit) - node.getWeight(orientation)
            case .add(let unit): CGFloat(unit)
            case .subtract(let unit): -CGFloat(unit)
        }

        guard let childDiff = diff.div(parent.children.count - 1) else { return .fail }
        parent.children.lazy
            .filter { $0 != node }
            .forEach { $0.setWeight(parent.orientation, $0.getWeight(parent.orientation) - childDiff) }

        node.setWeight(orientation, node.getWeight(orientation) + diff)
        return .succ
    }

    /// Floating windows have no tiling weights; resize their frame directly,
    /// keeping the center and clamping to the monitor (Super+-/= now fits an
    /// oversized floating window instead of erroring).
    @MainActor private func resizeFloatingWindow(target: LiveFocus, _ io: CmdIo) async -> BinaryExitCode {
        guard let window = target.windowOrNil else {
            return .fail(io.err("resize command requires a window target"))
        }
        guard window.isFloating else {
            return .fail(io.err("resize command doesn't support this target yet"))
        }
        guard let windowRect = try? await window.getAxRect(.cancellable),
              let monitorRect = window.nodeMonitor?.visibleRect
        else { return .fail }
        let horizontal = switch args.dimension.val {
            case .height: false
            default: true // width, smart, smartOpposite: no orientation context when floating
        }
        let maxDim = horizontal ? monitorRect.width : monitorRect.height
        let current = horizontal ? windowRect.width : windowRect.height
        let size: CGFloat = switch args.units.val {
            case .set(let unit): CGFloat(unit)
            case .add(let unit): current + CGFloat(unit)
            case .subtract(let unit): current - CGFloat(unit)
        }
        let newSize = size.coerce(in: min(100, maxDim) ... maxDim)
        var newX = windowRect.topLeftX
        var newY = windowRect.topLeftY
        let newWidth = horizontal ? newSize : windowRect.width
        let newHeight = horizontal ? windowRect.height : newSize
        if horizontal {
            newX = windowRect.topLeftX + windowRect.width / 2 - newSize / 2
        } else {
            newY = windowRect.topLeftY + windowRect.height / 2 - newSize / 2
        }
        newX = newX.coerce(in: monitorRect.minX ... max(monitorRect.minX, monitorRect.maxX - newWidth))
        newY = newY.coerce(in: monitorRect.minY ... max(monitorRect.minY, monitorRect.maxY - newHeight))
        window.setAxFrame(CGPoint(x: newX, y: newY), CGSize(width: newWidth, height: newHeight))
        return .succ
    }
}
