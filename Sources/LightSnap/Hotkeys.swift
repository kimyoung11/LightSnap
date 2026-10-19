import AppKit
import Carbon

protocol HotkeyRegistrar: AnyObject {
    var onKey: ((UInt32) -> Void)? { get set }
    var available: Bool { get }
    func register(id: UInt32, shortcut: Shortcut) -> Bool
    func unregister(id: UInt32)
    func unregisterAll()
}

final class CarbonHotkeyRegistrar: HotkeyRegistrar {
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    var onKey: ((UInt32) -> Void)?
    var available: Bool { handler != nil }
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x4C534E50 else { return OSStatus(eventNotHandledErr) }
            Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(context).takeUnretainedValue().onKey?(id.id)
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr { handler = nil }
    }
    func register(id: UInt32, shortcut: Shortcut) -> Bool {
        guard available else { return false }
        var ref: EventHotKeyRef?
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x4C534E50,id: id), GetApplicationEventTarget(), 0, &ref)
        guard result == noErr, let ref else { return false }
        refs[id] = ref; return true
    }
    func unregister(id: UInt32) { if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) } }
    func unregisterAll() { for id in Array(refs.keys) { unregister(id: id) } }
    deinit { unregisterAll(); if let handler { RemoveEventHandler(handler) } }
}

protocol ShortcutStorage: AnyObject {
    func load() -> Data?
    func save(_ data: Data)
}
final class DefaultsShortcutStorage: ShortcutStorage {
    func load() -> Data? { UserDefaults.standard.data(forKey: "shortcuts") }
    func save(_ data: Data) { UserDefaults.standard.set(data, forKey: "shortcuts") }
}

final class Hotkeys {
    private let registrar: HotkeyRegistrar
    private let storage: ShortcutStorage
    private var registered: Set<Layout> = []
    private var suspended = false
    private(set) var bindings: [Layout: Shortcut] = [:]
    private(set) var failures: Set<Layout> = []
    var onAction: ((Layout) -> Void)?
    var isEnabled = true { didSet { if isEnabled { resume() } else { unregisterAll() } } }
    var handlerAvailable: Bool { registrar.available }
    init(storage: ShortcutStorage = DefaultsShortcutStorage(), registrar: HotkeyRegistrar = CarbonHotkeyRegistrar()) {
        self.storage = storage; self.registrar = registrar
        if let data = storage.load(), let saved = try? JSONDecoder().decode([String: Shortcut].self, from: data) {
            for (key, shortcut) in saved { if let layout = Layout(rawValue: key), Self.valid(shortcut) { bindings[layout] = shortcut } }
        } else { for layout in Layout.allCases { bindings[layout] = layout.defaultShortcut } }
        registrar.onKey = { [weak self] id in
            guard let self, self.isEnabled, !self.suspended, id > 0, Int(id) <= Layout.allCases.count else { return }
            let layout = Layout.allCases[Int(id)-1]
            if self.registered.contains(layout) { self.onAction?(layout) }
        }
        resume()
    }
    deinit { registrar.unregisterAll() }
    private func id(_ layout: Layout) -> UInt32 { UInt32(Layout.allCases.firstIndex(of: layout)!+1) }
    private func unregisterAll() { registrar.unregisterAll(); registered.removeAll() }
    func suspend() { suspended = true; unregisterAll() }
    func resume() {
        suspended = false
        guard isEnabled else { return }
        for layout in Layout.allCases where !registered.contains(layout) {
            guard let shortcut = bindings[layout] else { failures.remove(layout); continue }
            if registrar.register(id: id(layout), shortcut: shortcut) { registered.insert(layout); failures.remove(layout) }
            else { failures.insert(layout) }
        }
    }
    static func valid(_ shortcut: Shortcut) -> Bool {
        let allowed = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        return shortcut.keyCode <= 127 && shortcut.modifiers & UInt32(cmdKey | controlKey) != 0 && shortcut.modifiers & ~allowed == 0
    }
    func update(_ layout: Layout, shortcut: Shortcut?) -> String? {
        if let shortcut {
            guard Self.valid(shortcut) else { return "⌘ 또는 ⌃를 포함하는 유효한 단축키를 입력해 주세요." }
            if let duplicate = bindings.first(where: { $0.key != layout && $0.value == shortcut }) { return "이미 ‘\(duplicate.key.title)’에서 사용 중입니다." }
        }
        let previous = bindings[layout], wasRegistered = registered.contains(layout)
        registrar.unregister(id: id(layout)); registered.remove(layout)
        if let shortcut {
            guard registrar.register(id: id(layout), shortcut: shortcut) else {
                if wasRegistered, let previous {
                    if registrar.register(id: id(layout), shortcut: previous) { registered.insert(layout) } else { failures.insert(layout) }
                }
                return "단축키 등록에 실패했습니다. 다른 앱·macOS의 사용 여부를 확인해 주세요."
            }
            if isEnabled && !suspended { registered.insert(layout) } else { registrar.unregister(id: id(layout)) }
        }
        bindings[layout] = shortcut; failures.remove(layout); save(); return nil
    }
    func reset() {
        unregisterAll(); bindings.removeAll(); failures.removeAll()
        for layout in Layout.allCases { bindings[layout] = layout.defaultShortcut }
        save(); if !suspended { resume() }
    }
    private func save() {
        let values = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue,$0.value) })
        if let data = try? JSONEncoder().encode(values) { storage.save(data) }
    }
}
