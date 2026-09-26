import AppKit
import Common
import Foundation
import os

let signposter = OSSignposter(subsystem: appId, category: .pointsOfInterest)

let myPid = NSRunningApplication.current.processIdentifier
let lockScreenAppBundleId = "com.apple.loginwindow"

@MainActor private var applicationSignalSources: [DispatchSourceSignal] = []

@MainActor
private func interceptSignal(_ value: Int32, handler: @escaping @MainActor @Sendable () async -> Void) {
    // A C signal handler may not allocate, touch AppKit, or create a Swift Task.
    // Dispatch safely delivers the ignored signal on a regular queue instead.
    unsafe signal(value, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: value, queue: .main)
    source.setEventHandler { Task { @MainActor in await handler() } }
    applicationSignalSources.append(source)
    source.resume()
}

@MainActor
func initTerminationHandler() {
    unsafe _terminationHandler = AppServerTerminationHandler()
    for value in [SIGTERM, SIGINT] {
        interceptSignal(value) {
            terminationHandler?.beforeTermination()
            exit(128 + value)
        }
    }
    interceptSignal(SIGUSR1) {
        do { try await restartMacarchy() }
        catch { reportSessionFailure("Could not restart Macarchy", error: error) }
    }
}

private struct AppServerTerminationHandler: TerminationHandler {
    @MainActor
    func beforeTermination() {
        SessionState.shared.saveBeforeTermination()
        // A normal quit only exposes windows Macarchy actually parked. Visible
        // windows retain their size/position, and native fullscreen is untouched.
        for window in MacWindow.allWindowsMap.values where window.isHiddenInCorner {
            guard let info = window.macApp.getSessionInfoForTermination(window.windowId), !info.fullscreen else { continue }
            let monitor = window.nodeWorkspace?.workspaceMonitor ?? info.rect?.center.monitorApproximation ?? mainMonitorInfo
            let frame = window.isFloating
                ? window.sessionFloatingRect(currentRect: info.rect)
                : window.lastAppliedLayoutPhysicalRect ?? info.rect
            let fitted = SessionFrame(frame ?? monitor.visibleRect).fitted(to: SessionFrame(monitor.visibleRect))
            window.macApp.setAxFrameForTermination(
                window.windowId,
                CGPoint(x: fitted.x, y: fitted.y),
                CGSize(width: fitted.width, height: fitted.height),
            )
        }
        if isDebug {
            let semaphore = DispatchSemaphore(value: 0)
            // Use Task.detached to avoid inheriting @MainActor.
            // If @MainActor was inherited, it would cause a deadlock
            Task.detached {
                await toggleReleaseServerIfDebug(.on)
                semaphore.signal()
            }
            semaphore.wait()
        }
    }
}

@MainActor
func terminateApp() -> Never {
    NSApplication.shared.terminate(nil)
    die("Unreachable code")
}

extension String {
    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(self, forType: .string)
    }
}

func - (a: CGPoint, b: CGPoint) -> CGPoint {
    CGPoint(x: a.x - b.x, y: a.y - b.y)
}

func + (a: CGPoint, b: CGPoint) -> CGPoint {
    CGPoint(x: a.x + b.x, y: a.y + b.y)
}

extension CGPoint: ConvenienceMutable {}

extension CGPoint {
    func distance(toOuterFrame rect: Rect) -> CGFloat {
        // Subtract 1 from maxX/maxY because the right/bottom bounds are
        // exclusive.
        let dx = max(rect.minX - x, 0, x - (rect.maxX - 1))
        let dy = max(rect.minY - y, 0, y - (rect.maxY - 1))
        return CGPoint(x: dx, y: dy).vectorLength
    }

    func coerce(in rect: Rect) -> CGPoint? {
        guard let xRange = rect.minX.until(incl: rect.maxX - 1) else { return nil }
        guard let yRange = rect.minY.until(incl: rect.maxY - 1) else { return nil }
        return CGPoint(x: x.coerce(in: xRange), y: y.coerce(in: yRange))
    }

    func addingXOffset(_ offset: CGFloat) -> CGPoint { CGPoint(x: x + offset, y: y) }
    func addingYOffset(_ offset: CGFloat) -> CGPoint { CGPoint(x: x, y: y + offset) }
    func addingOffset(_ orientation: Orientation, _ offset: CGFloat) -> CGPoint { orientation == .h ? addingXOffset(offset) : addingYOffset(offset) }

    func getProjection(_ orientation: Orientation) -> Double { orientation == .h ? x : y }

    var vectorLength: CGFloat { sqrt(x * x + y * y) }

    var monitorApproximation: MonitorInfo { monitorInfos.minByOrDie { distance(toOuterFrame: $0.rect) } }

    var withYAxisFlipped: CGPoint {
        consuming get {
            self.y = mainMonitorInfo.height - self.y
            return self
        }
    }
}

extension CGFloat {
    func div(_ denominator: Int) -> CGFloat? {
        denominator == 0 ? nil : self / CGFloat(denominator)
    }

    func coerce(in range: ClosedRange<CGFloat>) -> CGFloat {
        switch true {
            case self > range.upperBound: range.upperBound
            case self < range.lowerBound: range.lowerBound
            default: self
        }
    }
}

extension CGPoint: @retroactive Hashable { // todo migrate to self written Point
    public func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
    }
}

#if DEBUG
    let isDebug = true
#else
    let isDebug = false
#endif

@inlinable
func checkCancellation(_ cm: CancellationMode = .cancellable) throws(CancellationError) {
    if cm == .cancellable && Task.isCancelled {
        throw CancellationError()
    }
}

public enum CancellationMode: Equatable, Sendable {
    case cancellable
    case nonCancellable
}
