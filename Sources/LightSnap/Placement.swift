import Foundation

struct Placement {
    enum Result: Equatable { case applied, constrained, failed, unverified }
    // Actual AX operations are injected so failures and app size constraints can be tested.
    static func apply(target: CGRect, resize: (CGSize) -> Bool, move: (CGPoint) -> Bool, read: () -> CGRect?) -> Result {
        let resized = resize(target.size)
        guard move(target.origin) else { return .failed }
        if !resized && !resize(target.size) { return .failed }
        guard var actual = read() else { return .unverified }
        if !sameSize(actual.size, target.size) {
            guard resize(target.size) else { return .failed }
            guard let reread = read() else { return .unverified }
            actual = reread
        }
        return matches(actual, target) ? .applied : .constrained
    }
    static func sameSize(_ a: CGSize, _ b: CGSize) -> Bool { abs(a.width-b.width) <= 3 && abs(a.height-b.height) <= 3 }
    static func matches(_ a: CGRect, _ b: CGRect) -> Bool { sameSize(a.size,b.size) && abs(a.minX-b.minX) <= 3 && abs(a.minY-b.minY) <= 3 }
}

struct ScreenGeometry {
    static func accessibilityFrame(_ cocoa: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: cocoa.minX, y: primaryTop-cocoa.maxY, width: cocoa.width, height: cocoa.height)
    }
    static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat { let r = a.intersection(b); return r.isNull ? 0 : r.width*r.height }
    static func screen(for window: CGRect, in screens: [CGRect]) -> CGRect? {
        guard var best = screens.first else { return nil }
        for candidate in screens.dropFirst() {
            let score = overlap(window, candidate), current = overlap(window, best)
            if score > current || (score == current && distance(window, candidate) < distance(window, best)) { best = candidate }
        }
        return best
    }
    private static func distance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let dx = max(b.minX-a.maxX, a.minX-b.maxX, 0), dy = max(b.minY-a.maxY, a.minY-b.maxY, 0)
        return dx*dx + dy*dy
    }
    static func visibleRestore(_ saved: CGRect, in screens: [CGRect]) -> CGRect? {
        guard let screen = screen(for: saved, in: screens) else { return nil }
        // Keep the title bar reachable after disconnecting a display or changing resolution.
        if screens.contains(where: { $0.contains(CGPoint(x: saved.midX, y: saved.minY+12)) }) { return saved }
        let width = min(saved.width, screen.width), height = min(saved.height, screen.height)
        return CGRect(x: min(max(saved.minX, screen.minX),screen.maxX-width), y: min(max(saved.minY,screen.minY),screen.maxY-height), width: width, height: height)
    }
}
