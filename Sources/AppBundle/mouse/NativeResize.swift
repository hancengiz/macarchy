import Foundation

/// AX can accept a layout request but apply an app-specific minimum/maximum.
/// Only changes from the last frame we actually applied are native user resizes.
func nativeResizeTargetSize(expected: CGSize, actual: CGSize, lastApplied: CGSize?) -> CGSize? {
    let baseline = lastApplied ?? expected
    let widthDelta = actual.width - baseline.width
    let heightDelta = actual.height - baseline.height
    guard abs(widthDelta) > 2 || abs(heightDelta) > 2 else { return nil }
    return CGSize(
        width: abs(widthDelta) > 2 ? actual.width : expected.width,
        height: abs(heightDelta) > 2 ? actual.height : expected.height,
    )
}
