import AppKit

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: \(message)") }
    checks += 1
}
// Odd pixel dimensions, negative origins, and vertically offset displays.
for area in [CGRect(x: -1512,y: -200,width: 1511,height: 947), CGRect(x: 200,y: 38,width: 1727,height: 1079), CGRect(x: 0,y: 0,width: 1920,height: 1080)] {
    let a = Layout.firstThird.frame(in: area), b = Layout.middleThird.frame(in: area), c = Layout.lastThird.frame(in: area)
    check(a.minX == area.minX, "thirds left edge")
    check(a.maxX == b.minX && b.maxX == c.minX, "thirds share boundaries")
    check(c.maxX == area.maxX, "thirds right edge")
    check(a.width+b.width+c.width == area.width, "thirds preserve full width")
    let cells: [Layout] = [.cell1,.cell2,.cell3,.cell4,.cell5,.cell6]
    let frames = cells.map { $0.frame(in: area) }
    check(frames.reduce(0) { $0 + $1.width*$1.height } == area.width*area.height, "six cells preserve area")
    for i in frames.indices {
        check(area.contains(frames[i]), "cell fits usable screen")
        for j in frames.indices where i < j { check(ScreenGeometry.overlap(frames[i],frames[j]) == 0, "cells never overlap") }
    }
    check(frames[0].minY == area.minY && frames[3].maxY == area.maxY, "top-left coordinate orientation")
    check(Layout.maximize.frame(in: area) == area, "maximize uses usable screen")
    check(Layout.left.frame(in: area).maxX == Layout.right.frame(in: area).minX, "horizontal halves share boundary")
    check(Layout.top.frame(in: area).maxY == Layout.bottom.frame(in: area).minY, "vertical halves share boundary")
}
let shortcuts = Layout.allCases.compactMap { $0.defaultShortcut }
check(shortcuts.count == Layout.allCases.count, "all layouts have defaults")
for i in shortcuts.indices {
    check(shortcuts[i].modifiers != 0, "defaults always modified")
    for j in shortcuts.indices where i < j { check(shortcuts[i] != shortcuts[j], "defaults never conflict") }
}
let original = Shortcut(keyCode: 123, modifiers: 2304)
let roundTrip = try JSONDecoder().decode(Shortcut.self, from: JSONEncoder().encode(original))
check(roundTrip == original, "shortcut persistence round trip")
check(original.label == "⌥⌘←", "shortcut display label")

// Display selection, Cocoa-to-AX conversion, and unplugged-display recovery.
let primary = CGRect(x: 0,y: 24,width: 1440,height: 850), secondary = CGRect(x: -1920,y: -100,width: 1920,height: 1080)
check(ScreenGeometry.accessibilityFrame(CGRect(x: -1920,y: 0,width: 1920,height: 1080),primaryTop: 900) == CGRect(x: -1920,y: -180,width: 1920,height: 1080), "AX Y-axis conversion")
check(ScreenGeometry.screen(for: CGRect(x: -100,y: 100,width: 500,height: 400),in: [primary,secondary]) == primary, "select maximum overlap")
check(ScreenGeometry.screen(for: CGRect(x: -3000,y: 100,width: 200,height: 200),in: [primary,secondary]) == secondary, "offscreen uses nearest screen")
check(ScreenGeometry.screen(for: .zero,in: []) == nil, "no screens handled")
let savedOffscreen = CGRect(x: -1800,y: 0,width: 1800,height: 1000)
let safeRestore = ScreenGeometry.visibleRestore(savedOffscreen,in: [primary])!
check(primary.contains(safeRestore), "unplugged monitor restores into reachable screen")
check(ScreenGeometry.visibleRestore(CGRect(x: 100,y: 100,width: 400,height: 300),in: [primary]) == CGRect(x: 100,y: 100,width: 400,height: 300), "reachable restore preserved")

// First geometry survives repeated snaps, remains window-specific, and is bounded.
var history = RestoreHistory<Int>(capacity: 3)
let firstFrame = CGRect(x: 10,y: 20,width: 500,height: 400)
history.remember(1,frame: firstFrame); history.remember(1,frame: .zero)
check(history.frame(for: 1) == firstFrame, "preserve original across repeated snaps")
history.remember(2,frame: CGRect(x: 1,y: 1,width: 1,height: 1)); history.remember(3,frame: .zero)
check(history.entries.count == 3, "independent window history")
history.remember(4,frame: .zero)
check(history.entries.count == 3 && history.frame(for: 1) == nil, "bounded restore history evicts oldest")
history.remove(2); check(history.frame(for: 2) == nil, "successful restore clears entry")
history.prune { $0 == 4 }; check(history.frame(for: 4) == nil, "terminated app pruning")

// Placement tests simulate AX behavior, not just the geometry formula.
let target = CGRect(x: 0,y: 24,width: 720,height: 850)
var simulated = firstFrame
var resizeCalls = 0
let applied = Placement.apply(target: target,resize: { simulated.size = $0; resizeCalls += 1; return true },move: { simulated.origin = $0; return true },read: { simulated })
check(applied == .applied, "successful readback")
check(resizeCalls == 1, "successful snap avoids redundant size write")
let constrained = Placement.apply(target: target,resize: { _ in true },move: { _ in true },read: { firstFrame })
check(constrained == .constrained, "minimum-size or position constraints detected")
check(Placement.apply(target: target,resize: { _ in true },move: { _ in true },read: { nil }) == .unverified, "missing readback never reports success")
check(Placement.apply(target: target,resize: { _ in true },move: { _ in false },read: { target }) == .failed, "position write failure")
check(Placement.apply(target: target,resize: { _ in false },move: { _ in true },read: { target }) == .failed, "persistent size write failure")
var attempts = 0
check(Placement.apply(target: target,resize: { _ in attempts += 1; return attempts > 1 },move: { _ in true },read: { target }) == .applied, "resize after move recovers transient failure")

final class MemoryStorage: ShortcutStorage {
    var data: Data?
    func load() -> Data? { data }
    func save(_ data: Data) { self.data = data }
}
final class FakeRegistrar: HotkeyRegistrar {
    var onKey: ((UInt32) -> Void)?
    var available = true
    var refs: [UInt32: Shortcut] = [:]
    var rejected: Shortcut?
    var registrations = 0
    func register(id: UInt32,shortcut: Shortcut) -> Bool {
        registrations += 1
        guard available, shortcut != rejected, !refs.values.contains(shortcut) else { return false }
        refs[id] = shortcut; return true
    }
    func unregister(id: UInt32) { refs[id] = nil }
    func unregisterAll() { refs.removeAll() }
}
let storage = MemoryStorage(), registrar = FakeRegistrar()
let keys = Hotkeys(storage: storage,registrar: registrar)
check(registrar.refs.count == Layout.allCases.count, "all defaults registered")
let custom = Shortcut(keyCode: 0,modifiers: 4096) // Control+A
let oldRight = keys.bindings[.right]
let beforeUpdate = registrar.registrations
check(keys.update(.left,shortcut: custom) == nil, "custom shortcut accepted")
check(registrar.registrations-beforeUpdate == 1 && keys.bindings[.right] == oldRight, "single edit only registers target")
check(keys.update(.right,shortcut: custom) != nil && keys.bindings[.right] == oldRight, "duplicate edit rejected without loss")
let blocked = Shortcut(keyCode: 1,modifiers: 4096); registrar.rejected = blocked
check(keys.update(.right,shortcut: blocked) != nil && keys.bindings[.right] == oldRight && registrar.refs[2] == oldRight, "OS conflict rolls back previous binding")
check(keys.update(.right,shortcut: Shortcut(keyCode: 1,modifiers: 0)) != nil, "invalid modifier rejected")
var fired: Layout?
keys.onAction = { fired = $0 }; registrar.onKey?(1)
check(fired == .left, "registered callback routed to correct action")
keys.suspend(); fired = nil; registrar.onKey?(1)
check(registrar.refs.isEmpty && fired == nil, "recording suspends all global shortcuts")
let recordingCustom = Shortcut(keyCode: 2,modifiers: 4096)
check(keys.update(.right,shortcut: recordingCustom) == nil && registrar.refs.isEmpty, "recording validates then unregisters probe")
keys.resume(); check(registrar.refs.count == Layout.allCases.count, "recording finish restores active shortcuts")
keys.isEnabled = false; fired = nil; registrar.onKey?(1)
check(registrar.refs.isEmpty && fired == nil, "pause releases keys and ignores callbacks")
keys.suspend(); keys.resume(); check(registrar.refs.isEmpty, "ending editor does not undo pause")
keys.isEnabled = true; check(registrar.refs.count == Layout.allCases.count, "resume registers shortcuts")
check(keys.update(.right,shortcut: nil) == nil && keys.bindings[.right] == nil && registrar.refs[2] == nil, "disable individual shortcut")
let reloaded = Hotkeys(storage: storage,registrar: FakeRegistrar())
check(reloaded.bindings[.left] == custom && reloaded.bindings[.right] == nil, "saved custom and disabled shortcut survive reload")
keys.reset(); check(keys.bindings[.right] == Layout.right.defaultShortcut, "reset defaults")
let unavailable = FakeRegistrar(); unavailable.available = false
let broken = Hotkeys(storage: MemoryStorage(),registrar: unavailable)
check(!broken.handlerAvailable && broken.failures.count == Layout.allCases.count, "event handler failure surfaced")

// Resource math: MB is decimal bytes, CPU is one-core percentage, not machine-wide.
let sample1 = ResourceSample(uptimeSeconds: 10,cpuSeconds: 2,residentBytes: 60_000_000,footprintBytes: 20_000_000)
let sample2 = ResourceSample(uptimeSeconds: 15,cpuSeconds: 2.1,residentBytes: 65_000_000,footprintBytes: 25_000_000)
let report = ResourceReport(mode: "test",samples: [sample1,sample2])!
check(abs(report.cpuPercentOfOneCore-2) < 0.000001, "CPU delta measurement")
check(report.peakSampledFootprintMB == 25 && report.peakSampledResidentMB == 65 && report.footprintUnder50MB, "RSS and footprint separated")
check(ResourceReport(mode: "empty",samples: []) == nil, "empty resource samples rejected")
let metrics = SnapMetrics()
for i in 0..<150 { metrics.record(milliseconds: Double(i),status: .success) }
check(metrics.entries.count == 100 && metrics.entries.first?.milliseconds == 50, "latency history bounded")
metrics.record(milliseconds: 999,status: .failure)
check(metrics.summary.contains("실패·제약 1회"), "latency summary includes failures")
let liveSample = ResourceSample.capture()
check(liveSample != nil && liveSample!.residentBytes > 0 && liveSample!.footprintBytes > 0, "real self-task Mach memory API is readable in test process")
check(liveSample!.cpuSeconds >= 0 && liveSample!.uptimeSeconds > 0, "real self-process CPU sample is valid")
let excess = ResourceReport(mode: "test",samples: [sample1,ResourceSample(uptimeSeconds: 15,cpuSeconds: 2.1,residentBytes: 70_000_000,footprintBytes: 51_000_000)])!
check(!excess.footprintUnder50MB, "footprint above budget fails target")
let exported = DiagnosticExport(createdAt: "test",resources: report,recentSnaps: metrics.entries,notes: "test")
let decoded = try JSONDecoder().decode(DiagnosticExport.self,from: JSONEncoder().encode(exported))
check(decoded.resources?.sampleCount == 2 && decoded.recentSnaps.count == 100, "diagnostic JSON round trip")
var bounded = RestoreHistory<Int>()
for i in 0..<200 { bounded.remember(i,frame: firstFrame) }
check(bounded.entries.count == 128 && bounded.frame(for: 71) == nil && bounded.frame(for: 72) != nil, "production history bound holds over many windows")
keys.isEnabled = false; keys.reset()
check(registrar.refs.isEmpty && !keys.isEnabled, "reset preserves paused state")
fired = nil; registrar.onKey?(0); registrar.onKey?(999)
check(fired == nil, "invalid callback IDs ignored")
print("PASS: \(checks) checks (geometry, display recovery, placement failures, history, hotkey registration/persistence/pause, diagnostics)")
