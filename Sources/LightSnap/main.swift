import AppKit
import Carbon
import UniformTypeIdentifiers
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let engine = SnapEngine()
    let hotkeys = Hotkeys()
    var statusItem: NSStatusItem!
    var window: NSWindow?
    var permissionLabel: NSTextField?
    private let loginItem = LoginItemController()
    private var loginCheckbox: NSButton?
    private var loginStatusLabel: NSTextField?
    private var cycleCheckbox: NSButton?
    private var cyclingEnabled: Bool { UserDefaults.standard.object(forKey: "cycleHorizontalSizes") as? Bool ?? true }
    var feedback: NSTextField?
    var buttons: [Layout: NSButton] = [:]
    var recording: Layout?
    var monitor: Any?
    private let snapQueue = DispatchQueue(label: "dev.lightsnap.snap", qos: .userInitiated)
    private var isSnapping = false
    private var receivedHotkeyCount = 0
    private var permissionBlockedCount = 0
    private var previousApp: NSRunningApplication?
    private let metrics = SnapMetrics()
    private var diagnosticTimer: Timer?
    private var profileTimer: Timer?
    private var profileSamples: [ResourceSample] = []
    private let arguments = Array(CommandLine.arguments.dropFirst())
    var activationObserver: NSObjectProtocol?
    var statusMessage = "다른 앱의 창을 선택하고 단축키를 눌러 보세요."

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        previousApp = NSWorkspace.shared.frontmostApplication
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { self?.previousApp = app }
        }
        hotkeys.onAction = { [weak self] action in
            guard let self else { return }
            self.receivedHotkeyCount += 1
            self.perform(action)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "LightSnap 창 배치")
        rebuildMenu()
        if arguments.first == "--profile-idle" || arguments.first == "--profile-settings" {
            if arguments.first == "--profile-settings" { showSettings() }
            startProfile()
        } else {
            if !UserDefaults.standard.bool(forKey: "hasOpened") { showSettings() }
            UserDefaults.standard.set(true, forKey: "hasOpened")
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        cancelRecording(); diagnosticTimer?.invalidate(); profileTimer?.invalidate()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }
    func rebuildMenu() {
        guard statusItem != nil else { return }
        let menu = NSMenu(); menu.delegate = self
        let title = NSMenuItem(title: "LightSnap", action: nil, keyEquivalent: ""); title.isEnabled = false; menu.addItem(title)
        let state = NSMenuItem(title: engine.trusted ? "접근성 권한 연결됨" : "접근성 권한 필요", action: nil, keyEquivalent: ""); state.isEnabled = false; menu.addItem(state)
        let message = NSMenuItem(title: statusMessage, action: nil, keyEquivalent: ""); message.isEnabled = false; menu.addItem(message)
        menu.addItem(.separator())
        for layout in Layout.allCases {
            let key = hotkeys.bindings[layout]?.label ?? "미설정"
            let item = NSMenuItem(title: "\(layout.title)    \(key)\(hotkeys.failures.contains(layout) ? " ⚠︎" : "")", action: #selector(menuSnap(_:)), keyEquivalent: "")
            item.target = self; item.isEnabled = hotkeys.isEnabled && !isSnapping; item.representedObject = layout.rawValue; menu.addItem(item)
        }
        menu.addItem(.separator())
        let permission = NSMenuItem(title: "접근성 설정 열기…", action: #selector(grantPermission), keyEquivalent: ""); permission.target = self; menu.addItem(permission)
        let runtime = NSMenuItem(title: "실행 정보 복사", action: #selector(copyRuntimeInfo), keyEquivalent: ""); runtime.target = self; menu.addItem(runtime)
        let pause = NSMenuItem(title: hotkeys.isEnabled ? "스냅 일시정지" : "스냅 다시 시작", action: #selector(togglePause), keyEquivalent: ""); pause.target = self; menu.addItem(pause)
        let diagnostic = NSMenuItem(title: "리소스 진단 (5초)…", action: #selector(diagnose), keyEquivalent: ""); diagnostic.target = self; menu.addItem(diagnostic)
        let settings = NSMenuItem(title: "설정…", action: #selector(showSettings), keyEquivalent: ","); settings.target = self; menu.addItem(settings)
        let quit = NSMenuItem(title: "LightSnap 종료", action: #selector(quit), keyEquivalent: "q"); quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
    }
    @objc func menuSnap(_ sender: NSMenuItem) { if let raw = sender.representedObject as? String, let action = Layout(rawValue: raw) { perform(action) } }
    func menuWillOpen(_ menu: NSMenu) {
        menu.item(at: 1)?.title = engine.trusted ? "접근성 권한 연결됨" : "접근성 권한 필요"
    }
    func applicationDidBecomeActive(_ notification: Notification) { updatePermission() }
    func windowDidBecomeKey(_ notification: Notification) { updatePermission() }
    @objc func togglePause() {
        cancelRecording(); hotkeys.isEnabled.toggle()
        statusMessage = hotkeys.isEnabled ? "스냅을 다시 시작했습니다." : "스냅 일시정지 · 전역 단축키 해제됨"
        feedback?.stringValue = statusMessage; rebuildMenu()
    }
    func perform(_ action: Layout) {
        guard hotkeys.isEnabled, !isSnapping else { return }
        guard engine.trusted else {
            permissionBlockedCount += 1
            statusMessage = "단축키 수신됨 · 현재 실행 중인 LightSnap의 접근성 권한이 연결되지 않았습니다."
            feedback?.stringValue = statusMessage; statusItem.button?.toolTip = statusMessage
            updatePermission(); NSSound.beep()
            return
        }
        let start = ProcessInfo.processInfo.systemUptime
        let current = NSWorkspace.shared.frontmostApplication
        let targetApp = current?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? previousApp : current
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let shouldCycle = cyclingEnabled
        let screens = NSScreen.screens.map { ScreenGeometry.accessibilityFrame($0.visibleFrame, primaryTop: primaryTop) }
        if current?.processIdentifier == ProcessInfo.processInfo.processIdentifier { window?.orderOut(nil) }
        isSnapping = true
        // AX calls may block in another app. Keep them off the UI thread, with no repeat queue.
        snapQueue.async { [weak self] in
            guard let self else { return }
            let result = autoreleasepool { self.engine.snap(action, app: targetApp, screens: screens, cyclingEnabled: shouldCycle) }
            DispatchQueue.main.async {
                self.metrics.record(milliseconds: (ProcessInfo.processInfo.systemUptime-start)*1000,status: result.status)
                self.isSnapping = false; self.statusMessage = result.message
                self.feedback?.stringValue = result.message; self.statusItem.button?.toolTip = result.message
                self.rebuildMenu()
                if result.status != .success { NSSound.beep() }
            }
        }
    }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func grantPermission() { engine.requestPermission(); updatePermission() }
    @objc func recheckPermission() {
        statusMessage = engine.trusted ? "접근성 권한 연결됨 · 다른 앱 창에서 단축키를 사용해 보세요." : "권한 미연결 · 현재 앱을 다시 추가하고 종료 후 재실행해 주세요."
        feedback?.stringValue = statusMessage; updatePermission()
    }
    @objc func revealRunningApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    private var runtimeInfo: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        return """
        LightSnap \(version)
        실행 경로: \(Bundle.main.bundleURL.path)
        Bundle ID: \(Bundle.main.bundleIdentifier ?? "none")
        PID: \(ProcessInfo.processInfo.processIdentifier)
        접근성 권한: \(engine.trusted ? "연결됨" : "미연결")
        단축키 처리기: \(hotkeys.handlerAvailable ? "설치됨" : "설치 실패")
        등록 실패: \(hotkeys.failures.count)개
        수신한 전역 단축키: \(receivedHotkeyCount)회
        권한 미연결 차단: \(permissionBlockedCount)회
        스냅 활성화: \(hotkeys.isEnabled)
        좌우 크기 순환: \(cyclingEnabled)
        자동 실행: \(loginItem.state.description)
        마지막 상태: \(statusMessage)
        """
    }
    @objc func copyRuntimeInfo() {
        let pasteboard = NSPasteboard.general; pasteboard.clearContents()
        pasteboard.setString(runtimeInfo,forType: .string)
        feedback?.stringValue = "실행 경로·권한 상태·단축키 수신 횟수를 복사했습니다."
    }
    @objc func reset() { cancelRecording(); hotkeys.reset(); refreshButtons(); feedback?.stringValue = hotkeys.failures.isEmpty ? "기본 단축키로 초기화했습니다." : "일부 기본 단축키 등록 실패 · ⚠︎ 항목을 변경해 주세요."; rebuildMenu() }

    @objc func showSettings() {
        if window == nil { buildSettings() }
        updatePermission(); refreshButtons()
        window?.center(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        cancelRecording(); window = nil; permissionLabel = nil; loginCheckbox = nil; loginStatusLabel = nil; cycleCheckbox = nil; feedback = nil; buttons.removeAll()
    }
    func windowDidResignKey(_ notification: Notification) { cancelRecording() }
    @objc func toggleLogin(_ sender: NSButton) {
        let error = loginItem.setEnabled(sender.state == .on)
        feedback?.stringValue = error ?? loginItem.state.description
        refreshPreferences()
    }
    @objc func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc func toggleCycling(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on,forKey: "cycleHorizontalSizes")
        snapQueue.async { [weak self] in self?.engine.resetCycle() }
        feedback?.stringValue = sender.state == .on ? "좌우 단축키 반복 시 ½ → ⅔ → ⅓로 순환합니다." : "좌우 단축키를 항상 절반 크기로 배치합니다."
    }
    private func refreshPreferences() {
        let state = loginItem.state
        loginCheckbox?.state = state.requested ? .on : .off
        loginStatusLabel?.stringValue = state.description
        cycleCheckbox?.state = cyclingEnabled ? .on : .off
    }
    func updatePermission() {
        refreshPreferences()
        permissionLabel?.stringValue = engine.trusted ? "● 접근성 권한 연결됨 · 창 배치 준비 완료" : "● 접근성 권한 미연결 · 현재 실행 중인 앱을 허용해 주세요"
        permissionLabel?.textColor = engine.trusted ? .systemGreen : .systemOrange
        if !hotkeys.handlerAvailable { feedback?.stringValue = "전역 단축키 처리기를 설치하지 못했습니다. 앱을 다시 실행해 주세요." }
        else if !hotkeys.failures.isEmpty { feedback?.stringValue = "⚠︎ 단축키 등록 실패 · 해당 조합을 변경해 주세요." }
        rebuildMenu()
    }
    @objc func diagnose() {
        guard diagnosticTimer == nil else { return }
        let mode = window?.isVisible == true ? "interactive-settings-open" : "interactive-menu-only"
        var samples = [ResourceSample](); if let first = ResourceSample.capture() { samples.append(first) }
        var ticks = 0
        statusMessage = "리소스 측정 중 (5초)…"; feedback?.stringValue = statusMessage; rebuildMenu()
        diagnosticTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if let sample = ResourceSample.capture() { samples.append(sample) }; ticks += 1
            guard ticks >= 5 else { return }
            timer.invalidate(); self.diagnosticTimer = nil
            let report = ResourceReport(mode: mode,samples: samples)
            let alert = NSAlert(); alert.messageText = "LightSnap 리소스 진단"
            alert.informativeText = (report?.summary ?? "시스템에서 측정 정보를 읽을 수 없습니다.") + "\n\n" + self.metrics.summary + "\n\n" + self.runtimeInfo
            alert.addButton(withTitle: "확인"); alert.addButton(withTitle: "JSON 저장…")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertSecondButtonReturn {
                let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "LightSnap-diagnostics.json"
                if panel.runModal() == .OK, let url = panel.url {
                    do {
                        let export = DiagnosticExport(createdAt: ISO8601DateFormatter().string(from: Date()),resources: report,recentSnaps: self.metrics.entries,notes: self.runtimeInfo + "\nMB=1,000,000 bytes; CPU=one-core percent. Snap timing begins at callback and ends after AX readback; hardware input and visible rendering excluded. Samples are bounded to the last 100 attempts.")
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
                        try encoder.encode(export).write(to: url,options: .atomic)
                    } catch { NSAlert(error: error).runModal() }
                }
            }
            self.statusMessage = "리소스 측정 완료"; self.feedback?.stringValue = self.statusMessage; self.rebuildMenu()
        }
    }
    private func startProfile() {
        guard arguments.count >= 2 else { NSApp.terminate(nil); return }
        let path = arguments[1], seconds = min(60,max(5,Int(arguments.dropFirst(2).first ?? "15") ?? 15))
        // Exclude first 3 seconds of startup. Sampling itself has small overhead.
        DispatchQueue.main.asyncAfter(deadline: .now()+3) { [weak self] in
            guard let self else { return }
            if let first = ResourceSample.capture() { self.profileSamples.append(first) }
            var ticks = 0
            self.profileTimer = Timer.scheduledTimer(withTimeInterval: 1,repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                if let sample = ResourceSample.capture() { self.profileSamples.append(sample) }; ticks += 1
                guard ticks >= seconds else { return }
                timer.invalidate(); self.profileTimer = nil
                do {
                    guard let report = ResourceReport(mode: String(self.arguments[0].dropFirst(2)),samples: self.profileSamples) else { throw NSError(domain: "LightSnap.Profile",code: 1) }
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
                    try encoder.encode(report).write(to: URL(fileURLWithPath: path),options: .atomic)
                    print(report.summary)
                } catch { fputs("Profile failed: \(error)\n",stderr) }
                NSApp.terminate(nil)
            }
        }
    }
    func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let v = NSTextField(wrappingLabelWithString: text); v.font = .systemFont(ofSize: size, weight: weight); return v
    }
    func buildSettings() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 840), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        w.title = "LightSnap 설정 · 0.2.0"; w.minSize = NSSize(width: 660, height: 760); w.isReleasedWhenClosed = false; w.delegate = self; window = w
        let root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 10; root.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 20, right: 28); root.translatesAutoresizingMaskIntoConstraints = false
        w.contentView!.addSubview(root)
        NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo: w.contentView!.leadingAnchor), root.trailingAnchor.constraint(equalTo: w.contentView!.trailingAnchor), root.topAnchor.constraint(equalTo: w.contentView!.topAnchor), root.bottomAnchor.constraint(equalTo: w.contentView!.bottomAnchor)])
        let heading = NSStackView(); heading.orientation = .horizontal; heading.spacing = 12
        let icon = NSImageView(image: NSImage(systemSymbolName: "rectangle.split.2x2.fill", accessibilityDescription: nil)!); icon.contentTintColor = .systemTeal; icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 38, weight: .medium)
        heading.addArrangedSubview(icon)
        let titles = NSStackView(); titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 3
        titles.addArrangedSubview(label("LightSnap", size: 27, weight: .bold)); let subtitle = label("창은 가지런하게. 작업은 가볍게."); subtitle.textColor = .secondaryLabelColor; titles.addArrangedSubview(subtitle)
        heading.addArrangedSubview(titles); root.addArrangedSubview(heading)
        let permission = label(""); permissionLabel = permission; root.addArrangedSubview(permission)
        let grant = NSButton(title: "접근성 설정 열기", target: self, action: #selector(grantPermission)); grant.bezelStyle = .rounded; root.addArrangedSubview(grant)
        let tip = label("업데이트 후 권한이 연결되지 않으면: 접근성 목록의 이전 LightSnap을 제거 → +로 현재 앱 추가 → 허용 → 앱 종료 후 재실행. 설정창을 닫아도 메뉴 막대에 상주합니다.", size: 12); tip.textColor = .secondaryLabelColor; root.addArrangedSubview(tip)
        tip.widthAnchor.constraint(equalTo: root.widthAnchor,constant: -56).isActive = true
        let path = label("실행 중인 앱: " + Bundle.main.bundleURL.path,size: 11); path.textColor = .secondaryLabelColor; path.isSelectable = true; root.addArrangedSubview(path)
        path.widthAnchor.constraint(equalTo: root.widthAnchor,constant: -56).isActive = true
        let permissionTools = NSStackView(); permissionTools.orientation = .horizontal; permissionTools.spacing = 8
        for (title, action) in [("권한 다시 확인", #selector(recheckPermission)), ("실행 중인 앱 보기", #selector(revealRunningApp)), ("실행 정보 복사", #selector(copyRuntimeInfo))] {
            let button = NSButton(title: title,target: self,action: action); button.bezelStyle = .rounded; permissionTools.addArrangedSubview(button)
        }
        root.addArrangedSubview(permissionTools)
        let preferences = NSStackView(); preferences.orientation = .horizontal; preferences.spacing = 16
        let login = NSButton(checkboxWithTitle: "로그인 시 자동 실행",target: self,action: #selector(toggleLogin(_:))); loginCheckbox = login; preferences.addArrangedSubview(login)
        let cycling = NSButton(checkboxWithTitle: "좌우 반복 시 크기 순환",target: self,action: #selector(toggleCycling(_:))); cycleCheckbox = cycling; preferences.addArrangedSubview(cycling)
        let loginSettings = NSButton(title: "로그인 항목 설정…",target: self,action: #selector(openLoginSettings)); loginSettings.bezelStyle = .rounded; preferences.addArrangedSubview(loginSettings)
        root.addArrangedSubview(preferences)
        let loginState = label("",size: 11); loginState.textColor = .secondaryLabelColor; loginStatusLabel = loginState; root.addArrangedSubview(loginState)
        refreshPreferences()
        let section = NSStackView(); section.orientation = .horizontal
        section.addArrangedSubview(label("배치 & 단축키", size: 16, weight: .semibold))
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal); section.addArrangedSubview(spacer)
        let resetButton = NSButton(title: "기본값 복원", target: self, action: #selector(reset)); resetButton.bezelStyle = .rounded; section.addArrangedSubview(resetButton)
        root.addArrangedSubview(section); section.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true
        let hint = label("단축키 버튼을 눌러 새 조합 입력 · Esc 취소 · ⌫ 해제\n⌘ 또는 ⌃를 포함해야 합니다. 문자 키는 물리적 키 위치를 기준으로 동작합니다.", size: 12); hint.textColor = .secondaryLabelColor; root.addArrangedSubview(hint)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.borderType = .bezelBorder
        let rows = NSStackView(); rows.orientation = .vertical; rows.alignment = .leading; rows.spacing = 0; rows.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = rows; root.addArrangedSubview(scroll)
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56), scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 140), rows.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)])
        for (index, layout) in Layout.allCases.enumerated() {
            let row = NSStackView(); row.orientation = .horizontal; row.spacing = 14; row.edgeInsets = NSEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
            let preview = LayoutPreview(layout: layout); preview.widthAnchor.constraint(equalToConstant: 38).isActive = true; preview.heightAnchor.constraint(equalToConstant: 25).isActive = true; row.addArrangedSubview(preview)
            row.addArrangedSubview(label(layout.title))
            let filler = NSView(); filler.setContentHuggingPriority(.defaultLow, for: .horizontal); row.addArrangedSubview(filler)
            let button = NSButton(title: "", target: self, action: #selector(record(_:))); button.bezelStyle = .rounded; button.tag = index; button.widthAnchor.constraint(equalToConstant: 155).isActive = true; button.setAccessibilityLabel("\(layout.title) 단축키 변경"); buttons[layout] = button; row.addArrangedSubview(button)
            rows.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        let message = label(statusMessage, size: 12); message.textColor = .secondaryLabelColor; feedback = message; root.addArrangedSubview(message)
        message.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -56).isActive = true
        let diagnostics = NSButton(title: "리소스 진단 (5초)…", target: self, action: #selector(diagnose)); diagnostics.bezelStyle = .rounded; root.addArrangedSubview(diagnostics)
        let foot = label("⌥⌘←/→ 반복: 크기 순환  ·  ⌃⌥⌘→: 다음 모니터  ·  ⌥⌘⌫: 복원", size: 11); foot.textColor = .tertiaryLabelColor; root.addArrangedSubview(foot)
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
    }
    func refreshButtons() {
        for (layout, button) in buttons { button.title = recording == layout ? "새 단축키 입력…" : (hotkeys.bindings[layout]?.label ?? "미설정") + (hotkeys.failures.contains(layout) ? " ⚠︎" : "") }
    }
    @objc func record(_ sender: NSButton) {
        cancelRecording(); recording = Layout.allCases[sender.tag]; hotkeys.suspend(); refreshButtons()
        feedback?.stringValue = "새 단축키를 입력하세요. Esc로 취소할 수 있습니다."
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let layout = self.recording else { return event }
            if event.keyCode == 53 { self.cancelRecording(); return nil }
            let shortcut: Shortcut? = event.keyCode == 51 && event.modifierFlags.intersection([.command,.option,.control,.shift]).isEmpty ? nil : Shortcut(event: event)
            if let shortcut, shortcut.modifiers & UInt32(cmdKey | controlKey) == 0 { self.feedback?.stringValue = "⌘ Command 또는 ⌃ Control을 포함해 주세요."; return nil }
            if let error = self.hotkeys.update(layout, shortcut: shortcut) {
                self.feedback?.stringValue = error; self.hotkeys.suspend(); return nil
            }
            self.cancelRecording(); self.feedback?.stringValue = "\(layout.title) 단축키를 저장했습니다."; self.rebuildMenu(); return nil
        }
    }
    func cancelRecording() {
        guard recording != nil else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; recording = nil; hotkeys.resume(); refreshButtons()
    }
}

final class LayoutPreview: NSView {
    let layout: Layout
    init(layout: Layout) { self.layout = layout; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let area = bounds.insetBy(dx: 1, dy: 1)
        NSColor.quaternaryLabelColor.setFill(); NSBezierPath(roundedRect: area, xRadius: 3, yRadius: 3).fill()
        NSColor.systemTeal.withAlphaComponent(layout == .restore ? 0.35 : 0.8).setFill()
        NSBezierPath(roundedRect: layout.frame(in: area).insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2).fill()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
