import Foundation

struct CycleTracker<Key: Equatable> {
    private struct Last { let key: Key; let action: Layout; let screen: CGRect; let actual: CGRect; let index: Int }
    private var last: Last?
    func proposal(key: Key, action: Layout, current: CGRect, screen: CGRect, enabled: Bool) -> (layout: Layout, index: Int) {
        guard enabled, action == .left || action == .right else { return (action,0) }
        let choices: [Layout] = action == .left ? [.left,.leftTwoThirds,.firstThird] : [.right,.rightTwoThirds,.lastThird]
        let index: Int
        if let last, last.key == key, last.action == action, last.screen == screen, Placement.matches(current,last.actual) { index = (last.index+1)%choices.count }
        else { index = 0 }
        return (choices[index],index)
    }
    mutating func commit(key: Key, action: Layout, screen: CGRect, actual: CGRect, index: Int) {
        last = Last(key: key,action: action,screen: screen,actual: actual,index: index)
    }
    mutating func reset() { last = nil }
}

extension ScreenGeometry {
    static func nextScreen(for window: CGRect, in screens: [CGRect]) -> CGRect? {
        let unique = screens.reduce(into: [CGRect]()) { if !$0.contains($1) { $0.append($1) } }
        let ordered = unique.sorted { $0.minX == $1.minX ? $0.minY < $1.minY : $0.minX < $1.minX }
        guard ordered.count > 1, let current = screen(for: window,in: ordered), let index = ordered.firstIndex(of: current) else { return nil }
        return ordered[(index+1)%ordered.count]
    }
    static func transfer(_ window: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return destination }
        let width = min(destination.width,max(1,(window.width/source.width*destination.width).rounded()))
        let height = min(destination.height,max(1,(window.height/source.height*destination.height).rounded()))
        let x = destination.minX+(window.minX-source.minX)/source.width*destination.width
        let y = destination.minY+(window.minY-source.minY)/source.height*destination.height
        return CGRect(x: min(max(x.rounded(),destination.minX),destination.maxX-width),y: min(max(y.rounded(),destination.minY),destination.maxY-height),width: width,height: height)
    }
}
