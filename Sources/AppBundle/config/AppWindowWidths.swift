import AppKit
import Common

/// The fallback is resolved on every layout; manual per-window sizes remain overrides.
@MainActor
func preferredScrollingSize(for node: TreeNode, extent: CGFloat) -> CGFloat {
    let percentage = (node as? Window)?.app.rawAppBundleId.flatMap { config.appWindowWidths[$0] }
        ?? config.scrollingColumnWidth
    return extent * CGFloat(percentage) / 100
}

struct AppWidthSnapshot {
    let windowId: UInt32
    let bundleId: String
    let appName: String
    let percentage: Int

    @MainActor init(window: Window) throws {
        guard let bundleId = window.app.rawAppBundleId, !bundleId.isEmpty else {
            throw SettingsError("The selected app does not have a bundle ID.")
        }
        let extent: CGFloat
        let logical: CGFloat
        if window.isFloating, let size = window.lastFloatingSize, let monitor = window.nodeMonitor {
            extent = monitor.visibleRect.width
            logical = size.width
        } else if let parent = window.parent as? TilingContainer, parent.layout == .scrolling,
                  let containerExtent = parent.lastAppliedLayoutPhysicalRect?.getDimension(parent.orientation), containerExtent > 0
        {
            extent = containerExtent
            // Never sample the AX frame: apps may enforce a larger physical minimum.
            logical = window.scrollingSize ?? preferredScrollingSize(for: window, extent: extent)
        } else if let parent = window.parent as? TilingContainer {
            let container = window.parentsWithSelf.compactMap { $0 as? TilingContainer }
                .first { $0.layout == .scrolling && $0.orientation == .h } ?? parent
            guard let containerWidth = container.lastAppliedLayoutPhysicalRect?.width, containerWidth > 0,
                  let allocatedWidth = window.lastAppliedLayoutPhysicalRect?.width
            else { throw SettingsError("This window has no current layout size. Show its workspace and try again.") }
            extent = containerWidth
            logical = allocatedWidth
        } else {
            throw SettingsError("Show a resizable app window before saving its preferred width.")
        }
        self.windowId = window.windowId
        self.bundleId = bundleId
        appName = window.app.name ?? bundleId
        percentage = min(100, max(1, Int((min(max(1, logical), extent) / extent * 100).rounded())))
    }

    @MainActor func save() async throws -> String {
        let url = try ConfigPersistence.set(["app-window-widths", bundleId], value: String(percentage))
        let warnings = try await ConfigPersistence.reload(url)
        // Only the captured target returns to the default. Other manually resized
        // windows keep their explicit overrides; untouched windows update on layout.
        if let window = Window.get(byId: windowId), window.app.rawAppBundleId == bundleId {
            window.scrollingSize = nil
        }
        return warnings
    }
}
