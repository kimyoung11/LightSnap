import AppKit
import ApplicationServices

struct SnapOutcome {
    enum Status: String, Codable { case success, constrained, failure }
    let status: Status
    let message: String
}

final class SnapEngine {
    private struct WindowKey: Equatable {
        let window: AXUIElement
        let pid: pid_t
        static func == (a: Self, b: Self) -> Bool { a.pid == b.pid && CFEqual(a.window,b.window) }
    }
    // Accessed only by the serial snap queue.
    private var history = RestoreHistory<WindowKey>()
    var trusted: Bool { AXIsProcessTrusted() }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func snap(_ layout: Layout, app: NSRunningApplication?, screens: [CGRect]) -> SnapOutcome {
        func fail(_ message: String) -> SnapOutcome { SnapOutcome(status: .failure, message: message) }
        guard trusted else { return fail("접근성 권한을 먼저 허용해 주세요.") }
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier, !app.isTerminated else { return fail("배치할 앱의 창을 먼저 선택해 주세요.") }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.15)
        guard let raw = value(axApp, kAXFocusedWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return fail("이 앱에서 배치할 창을 찾을 수 없습니다.") }
        let window = unsafeBitCast(raw, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(window, 0.15)
        if let full = value(window, "AXFullScreen") as? Bool, full { return fail("전체 화면을 해제한 다음 다시 시도해 주세요.") }
        guard let original = frame(window) else { return fail("이 창의 위치와 크기를 읽을 수 없습니다.") }
        let deadPIDs = Set(history.entries.map { $0.key.pid }).filter { NSRunningApplication(processIdentifier: $0)?.isTerminated != false }
        history.prune { deadPIDs.contains($0.pid) }
        let key = WindowKey(window: window, pid: app.processIdentifier)
        let target: CGRect
        if layout == .restore {
            guard let saved = history.frame(for: key) else { return fail("이 창에 저장된 원래 배치가 없습니다.") }
            guard let visible = ScreenGeometry.visibleRestore(saved, in: screens) else { return fail("디스플레이를 찾을 수 없습니다.") }
            target = visible
        } else {
            guard let screen = ScreenGeometry.screen(for: original, in: screens) else { return fail("디스플레이를 찾을 수 없습니다.") }
            target = layout.frame(in: screen)
        }
        var canMove = DarwinBoolean(false), canResize = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &canMove) == .success,
              AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &canResize) == .success,
              canMove.boolValue, canResize.boolValue else { return fail("이 창은 이동 또는 크기 변경을 지원하지 않습니다.") }
        // Retain recovery geometry even if an app accepts only part of a request.
        if layout != .restore { history.remember(key, frame: original) }
        let result = Placement.apply(target: target, resize: { size in
            var size = size
            guard let v = AXValueCreate(.cgSize, &size) else { return false }
            return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString,v) == .success
        }, move: { point in
            var point = point
            guard let v = AXValueCreate(.cgPoint, &point) else { return false }
            return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString,v) == .success
        }, read: { self.frame(window) })
        switch result {
        case .failed: return fail("창 배치 중 일부 작업에 실패했습니다. 복원 단축키로 이전 배치를 다시 시도할 수 있습니다.")
        case .unverified: return fail("요청을 보냈지만 결과를 확인하지 못했습니다. 복원 기록은 유지합니다.")
        case .constrained: return SnapOutcome(status: .constrained, message: "앱의 최소 크기 또는 위치 제한이 적용되었습니다. 복원 기록은 유지합니다.")
        case .applied:
            if layout == .restore { history.remove(key) }
            return SnapOutcome(status: .success, message: "\(app.localizedName ?? "앱") · \(layout.title) 완료")
        }
    }
    private func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var output: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,name as CFString,&output) == .success else { return nil }
        return output
    }
    private func frame(_ window: AXUIElement) -> CGRect? {
        guard let p = value(window,kAXPositionAttribute), let s = value(window,kAXSizeAttribute), CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(p,to: AXValue.self),.cgPoint,&point), AXValueGetValue(unsafeBitCast(s,to: AXValue.self),.cgSize,&size), point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: point,size: size)
    }
}
