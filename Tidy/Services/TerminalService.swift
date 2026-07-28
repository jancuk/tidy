import AppKit
import Combine
import Foundation
import GhosttyKit

enum TerminalServiceError: LocalizedError {
    case initializationFailed
    case configurationFailed
    case runtimeFailed
    case surfaceFailed

    var errorDescription: String? {
        switch self {
        case .initializationFailed:
            "Ghostty could not initialize."
        case .configurationFailed:
            "Ghostty could not create its configuration."
        case .runtimeFailed:
            "Ghostty could not create its embedded runtime."
        case .surfaceFailed:
            "Ghostty could not create a terminal surface."
        }
    }
}

enum TerminalKeyRouting {
    static func shouldDeferToApplication(
        charactersIgnoringModifiers: String?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        guard let characters = charactersIgnoringModifiers?.lowercased(),
              modifierFlags.contains(.command) else {
            return false
        }

        // Keep standard macOS application commands out of the terminal.
        if ["q", "w", "h", "m"].contains(characters) {
            return true
        }

        let relevantModifiers = modifierFlags.intersection([
            .command,
            .option,
            .control,
            .shift
        ])

        // Tidy feature navigation: Command-0 through Command-9.
        if relevantModifiers == [.command],
           characters.count == 1,
           characters.first.map({ ("0"..."9").contains($0) }) == true {
            return true
        }

        // Tidy sidebar toggle: Command-/.
        return relevantModifiers == [.command] && characters == "/"
    }
}

@MainActor
final class TerminalService: ObservableObject {
    @Published private(set) var surfaceView: GhosttyTerminalSurfaceView?
    @Published private(set) var title = "Terminal"
    @Published private(set) var currentDirectory: String
    @Published private(set) var isProcessRunning = false
    @Published private(set) var isRendererHealthy = true
    @Published private(set) var errorMessage: String?

    private var runtime: GhosttyTerminalRuntime?

    init() {
        let savedDirectory = UserDefaults.standard.string(forKey: AppDefaults.terminalWorkingDirectory) ?? ""
        currentDirectory = Self.validDirectory(savedDirectory)
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    func startIfNeeded() {
        guard surfaceView == nil, errorMessage == nil else { return }
        start()
    }

    func restart() {
        surfaceView = nil
        isProcessRunning = false
        errorMessage = nil
        start()
    }

    func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Terminal Working Directory"
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: currentDirectory, isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        currentDirectory = url.path
        UserDefaults.standard.set(url.path, forKey: AppDefaults.terminalWorkingDirectory)
        restart()
    }

    func focus() {
        guard let surfaceView else { return }
        surfaceView.window?.makeFirstResponder(surfaceView)
    }

    private func start() {
        do {
            let runtime = try runtime ?? GhosttyTerminalRuntime()
            self.runtime = runtime

            let view = try GhosttyTerminalSurfaceView(
                runtime: runtime,
                workingDirectory: currentDirectory
            )
            view.onTitleChange = { [weak self] title in
                Task { @MainActor in
                    self?.title = title.isEmpty ? "Terminal" : title
                }
            }
            view.onDirectoryChange = { [weak self] directory in
                Task { @MainActor in
                    guard !directory.isEmpty else { return }
                    self?.currentDirectory = directory
                }
            }
            view.onProcessExit = { [weak self] in
                Task { @MainActor in
                    self?.isProcessRunning = false
                }
            }
            view.onRendererHealthChange = { [weak self] healthy in
                Task { @MainActor in
                    self?.isRendererHealthy = healthy
                }
            }

            title = "Terminal"
            isProcessRunning = true
            isRendererHealthy = true
            surfaceView = view
        } catch {
            errorMessage = error.localizedDescription
            isProcessRunning = false
        }
    }

    private static func validDirectory(_ path: String) -> String? {
        guard !path.isEmpty else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return path
    }
}

final class GhosttyTerminalRuntime {
    private(set) var app: ghostty_app_t?
    private var config: ghostty_config_t?

    init() throws {
        guard ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS else {
            throw TerminalServiceError.initializationFailed
        }

        guard let config = ghostty_config_new() else {
            throw TerminalServiceError.configurationFailed
        }
        self.config = config
        ghostty_config_finalize(config)

        var runtimeConfig = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: false,
            wakeup_cb: { userdata in
                GhosttyTerminalRuntime.wakeup(userdata)
            },
            action_cb: { app, target, action in
                GhosttyTerminalRuntime.handleAction(app, target: target, action: action)
            },
            read_clipboard_cb: { userdata, location, state in
                GhosttyTerminalRuntime.readClipboard(userdata, location: location, state: state)
            },
            confirm_read_clipboard_cb: { userdata, string, state, request in
                GhosttyTerminalRuntime.confirmClipboardRead(
                    userdata,
                    string: string,
                    state: state,
                    request: request
                )
            },
            write_clipboard_cb: { userdata, location, content, count, confirm in
                GhosttyTerminalRuntime.writeClipboard(
                    userdata,
                    location: location,
                    content: content,
                    count: count,
                    confirm: confirm
                )
            },
            close_surface_cb: { userdata, _ in
                GhosttyTerminalRuntime.closeSurface(userdata)
            }
        )

        guard let app = ghostty_app_new(&runtimeConfig, config) else {
            throw TerminalServiceError.runtimeFailed
        }
        self.app = app
        ghostty_app_set_focus(app, NSApp.isActive)
        updateColorScheme()
    }

    deinit {
        if let app {
            ghostty_app_free(app)
        }
        if let config {
            ghostty_config_free(config)
        }
    }

    func updateColorScheme() {
        guard let app else { return }
        let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        ghostty_app_set_color_scheme(
            app,
            appearance == .darkAqua ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
        )
    }

    private static func wakeup(_ userdata: UnsafeMutableRawPointer?) {
        guard let userdata else { return }
        let runtime = Unmanaged<GhosttyTerminalRuntime>
            .fromOpaque(userdata)
            .takeUnretainedValue()
        DispatchQueue.main.async {
            guard let app = runtime.app else { return }
            ghostty_app_tick(app)
        }
    }

    private static func handleAction(
        _ app: ghostty_app_t?,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        guard let view = surfaceView(for: target) else {
            return false
        }

        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            guard let pointer = action.action.set_title.title else { return false }
            let title = String(cString: pointer)
            DispatchQueue.main.async {
                view.updateTitle(title)
            }
            return true

        case GHOSTTY_ACTION_PWD:
            guard let pointer = action.action.pwd.pwd else { return false }
            let directory = String(cString: pointer)
            DispatchQueue.main.async {
                view.updateDirectory(directory)
            }
            return true

        case GHOSTTY_ACTION_MOUSE_SHAPE:
            let shape = action.action.mouse_shape
            DispatchQueue.main.async {
                view.updateCursor(shape)
            }
            return true

        case GHOSTTY_ACTION_MOUSE_VISIBILITY:
            let visible = action.action.mouse_visibility == GHOSTTY_MOUSE_VISIBLE
            DispatchQueue.main.async {
                view.updateCursorVisibility(visible)
            }
            return true

        case GHOSTTY_ACTION_RENDERER_HEALTH:
            let healthy = action.action.renderer_health == GHOSTTY_RENDERER_HEALTH_HEALTHY
            DispatchQueue.main.async {
                view.updateRendererHealth(healthy)
            }
            return true

        case GHOSTTY_ACTION_OPEN_URL:
            let value = action.action.open_url
            guard let pointer = value.url else { return false }
            let bytes = UnsafeBufferPointer(start: pointer, count: Int(value.len))
            let string = String(decoding: bytes.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard let url = URL(string: string),
                  SecureHTTP.isSafeWebURL(url) else {
                return false
            }
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
            return true

        case GHOSTTY_ACTION_RING_BELL:
            DispatchQueue.main.async {
                NSSound.beep()
            }
            return true

        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            DispatchQueue.main.async {
                view.processDidExit()
            }
            return true

        case GHOSTTY_ACTION_COPY_TITLE_TO_CLIPBOARD:
            DispatchQueue.main.async {
                view.copyTitleToClipboard()
            }
            return true

        default:
            _ = app
            return false
        }
    }

    private static func readClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) -> Bool {
        guard location == GHOSTTY_CLIPBOARD_STANDARD,
              let view = surfaceView(from: userdata),
              let surface = view.surface,
              let value = NSPasteboard.general.string(forType: .string) else {
            return false
        }

        value.withCString { pointer in
            ghostty_surface_complete_clipboard_request(surface, pointer, state, false)
        }
        return true
    }

    private static func confirmClipboardRead(
        _ userdata: UnsafeMutableRawPointer?,
        string: UnsafePointer<CChar>?,
        state: UnsafeMutableRawPointer?,
        request: ghostty_clipboard_request_e
    ) {
        guard let view = surfaceView(from: userdata),
              let surface = view.surface else {
            return
        }

        // Normal paste is already completed by readClipboard. Terminal escape
        // sequences that request clipboard reads are denied by default.
        let value = string.map(String.init(cString:)) ?? ""
        value.withCString { pointer in
            ghostty_surface_complete_clipboard_request(
                surface,
                pointer,
                state,
                request == GHOSTTY_CLIPBOARD_REQUEST_PASTE
            )
        }
    }

    private static func writeClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        count: Int,
        confirm: Bool
    ) {
        guard location == GHOSTTY_CLIPBOARD_STANDARD,
              !confirm,
              surfaceView(from: userdata) != nil,
              let content,
              count > 0 else {
            return
        }

        for index in 0..<count {
            let item = content[index]
            guard let mime = item.mime,
                  String(cString: mime) == "text/plain",
                  let data = item.data else {
                continue
            }
            let value = String(cString: data)
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }
            return
        }
    }

    private static func closeSurface(_ userdata: UnsafeMutableRawPointer?) {
        guard let view = surfaceView(from: userdata) else { return }
        DispatchQueue.main.async {
            view.processDidExit()
        }
    }

    private static func surfaceView(for target: ghostty_target_s) -> GhosttyTerminalSurfaceView? {
        guard target.tag == GHOSTTY_TARGET_SURFACE,
              let surface = target.target.surface,
              let userdata = ghostty_surface_userdata(surface) else {
            return nil
        }
        return surfaceView(from: userdata)
    }

    private static func surfaceView(
        from userdata: UnsafeMutableRawPointer?
    ) -> GhosttyTerminalSurfaceView? {
        guard let userdata else { return nil }
        return Unmanaged<GhosttyTerminalSurfaceView>
            .fromOpaque(userdata)
            .takeUnretainedValue()
    }
}

final class GhosttyTerminalSurfaceView: NSView {
    var onTitleChange: ((String) -> Void)?
    var onDirectoryChange: ((String) -> Void)?
    var onProcessExit: (() -> Void)?
    var onRendererHealthChange: ((Bool) -> Void)?

    fileprivate private(set) var surface: ghostty_surface_t?
    private let runtime: GhosttyTerminalRuntime
    private var currentTitle = "Terminal"
    private var tracking: NSTrackingArea?
    private var cursorVisible = true

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    init(runtime: GhosttyTerminalRuntime, workingDirectory: String) throws {
        self.runtime = runtime
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        guard let app = runtime.app else {
            throw TerminalServiceError.runtimeFailed
        }

        var surfaceConfig = ghostty_surface_config_new()
        surfaceConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(self).toOpaque()
            )
        )
        surfaceConfig.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2)
        surfaceConfig.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        var environment = Self.makeEnvironment()
        defer {
            environment.storage.forEach { free($0) }
        }

        let newSurface: ghostty_surface_t? = workingDirectory.withCString { directoryPointer in
            surfaceConfig.working_directory = directoryPointer
            return environment.values.withUnsafeMutableBufferPointer { buffer in
                surfaceConfig.env_vars = buffer.baseAddress
                surfaceConfig.env_var_count = buffer.count
                return ghostty_surface_new(app, &surfaceConfig)
            }
        }

        guard let newSurface else {
            throw TerminalServiceError.surfaceFailed
        }
        surface = newSurface

        updateTrackingAreas()
        updateSurfaceMetrics()
        ghostty_surface_set_focus(newSurface, true)
        ghostty_surface_set_occlusion(newSurface, false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let tracking {
            removeTrackingArea(tracking)
        }
        if let surface {
            ghostty_surface_free(surface)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        runtime.updateColorScheme()
        updateSurfaceMetrics()
        if let surface {
            ghostty_surface_set_occlusion(surface, window != nil)
            if window != nil {
                ghostty_surface_refresh(surface)
                ghostty_surface_draw(surface)
            }
        }
        if let screenNumber = window?.screen?.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? NSNumber, let surface {
            ghostty_surface_set_display_id(surface, screenNumber.uint32Value)
        }
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateSurfaceMetrics()
    }

    override func layout() {
        super.layout()
        updateSurfaceMetrics()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        self.tracking = tracking
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface {
            ghostty_surface_set_focus(surface, false)
        }
        return result
    }

    override func keyDown(with event: NSEvent) {
        sendKey(event, action: event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS)
    }

    override func keyUp(with event: NSEvent) {
        sendKey(event, action: GHOSTTY_ACTION_RELEASE)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        if TerminalKeyRouting.shouldDeferToApplication(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifierFlags: event.modifierFlags
        ) {
            return false
        }
        return sendKey(
            event,
            action: event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        )
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendMousePosition(event)
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_LEFT)
    }

    override func mouseUp(with event: NSEvent) {
        sendMousePosition(event)
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT)
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendMousePosition(event)
        guard sendMouseButton(
            event,
            state: GHOSTTY_MOUSE_PRESS,
            button: GHOSTTY_MOUSE_RIGHT
        ) else {
            super.rightMouseDown(with: event)
            return
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        sendMousePosition(event)
        guard sendMouseButton(
            event,
            state: GHOSTTY_MOUSE_RELEASE,
            button: GHOSTTY_MOUSE_RIGHT
        ) else {
            super.rightMouseUp(with: event)
            return
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        sendMousePosition(event)
        sendMouseButton(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_MIDDLE)
    }

    override func otherMouseUp(with event: NSEvent) {
        sendMousePosition(event)
        sendMouseButton(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_MIDDLE)
    }

    override func mouseMoved(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func mouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        sendMousePosition(event)
    }

    override func mouseExited(with event: NSEvent) {
        guard let surface, NSEvent.pressedMouseButtons == 0 else { return }
        ghostty_surface_mouse_pos(surface, -1, -1, Self.modifiers(event.modifierFlags))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        if event.hasPreciseScrollingDeltas {
            x *= 2
            y *= 2
        }

        let momentum = Self.momentumValue(event.momentumPhase)
        let scrollModifiers = (event.hasPreciseScrollingDeltas ? 1 : 0) | (momentum << 1)
        ghostty_surface_mouse_scroll(surface, x, y, Int32(scrollModifiers))
    }

    fileprivate func updateTitle(_ title: String) {
        currentTitle = title
        onTitleChange?(title)
    }

    fileprivate func updateDirectory(_ directory: String) {
        onDirectoryChange?(directory)
    }

    fileprivate func updateRendererHealth(_ healthy: Bool) {
        onRendererHealthChange?(healthy)
    }

    fileprivate func processDidExit() {
        onProcessExit?()
    }

    fileprivate func copyTitleToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentTitle, forType: .string)
    }

    fileprivate func updateCursor(_ shape: ghostty_action_mouse_shape_e) {
        let cursor: NSCursor
        switch shape {
        case GHOSTTY_MOUSE_SHAPE_POINTER:
            cursor = .pointingHand
        case GHOSTTY_MOUSE_SHAPE_CROSSHAIR:
            cursor = .crosshair
        case GHOSTTY_MOUSE_SHAPE_GRAB, GHOSTTY_MOUSE_SHAPE_GRABBING:
            cursor = .openHand
        case GHOSTTY_MOUSE_SHAPE_EW_RESIZE,
             GHOSTTY_MOUSE_SHAPE_COL_RESIZE:
            cursor = .resizeLeftRight
        case GHOSTTY_MOUSE_SHAPE_NS_RESIZE,
             GHOSTTY_MOUSE_SHAPE_ROW_RESIZE:
            cursor = .resizeUpDown
        default:
            cursor = .iBeam
        }
        cursor.set()
    }

    fileprivate func updateCursorVisibility(_ visible: Bool) {
        guard cursorVisible != visible else { return }
        cursorVisible = visible
        if visible {
            NSCursor.unhide()
        } else {
            NSCursor.hide()
        }
    }

    private func updateSurfaceMetrics() {
        guard let surface else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        ghostty_surface_set_content_scale(surface, scale, scale)

        let backingSize = convertToBacking(bounds).size
        ghostty_surface_set_size(
            surface,
            UInt32(max(1, backingSize.width.rounded())),
            UInt32(max(1, backingSize.height.rounded()))
        )
    }

    @discardableResult
    private func sendKey(
        _ event: NSEvent,
        action: ghostty_input_action_e
    ) -> Bool {
        guard let surface else { return false }

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = Self.modifiers(event.modifierFlags)
        keyEvent.consumed_mods = Self.modifiers(
            event.modifierFlags.subtracting([.control, .command])
        )
        keyEvent.composing = false

        if let value = event.characters(byApplyingModifiers: []),
           value.unicodeScalars.count == 1,
           let scalar = value.unicodeScalars.first {
            keyEvent.unshifted_codepoint = scalar.value
        }

        guard action != GHOSTTY_ACTION_RELEASE,
              let characters = Self.terminalCharacters(for: event),
              !characters.isEmpty else {
            keyEvent.text = nil
            return ghostty_surface_key(surface, keyEvent)
        }

        return characters.withCString { pointer in
            keyEvent.text = pointer
            return ghostty_surface_key(surface, keyEvent)
        }
    }

    private func sendMousePosition(_ event: NSEvent) {
        guard let surface else { return }
        let position = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(
            surface,
            position.x,
            bounds.height - position.y,
            Self.modifiers(event.modifierFlags)
        )
    }

    @discardableResult
    private func sendMouseButton(
        _ event: NSEvent,
        state: ghostty_input_mouse_state_e,
        button: ghostty_input_mouse_button_e
    ) -> Bool {
        guard let surface else { return false }
        return ghostty_surface_mouse_button(
            surface,
            state,
            button,
            Self.modifiers(event.modifierFlags)
        )
    }

    private static func terminalCharacters(for event: NSEvent) -> String? {
        guard let characters = event.characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return nil
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }
        return characters
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var rawValue: UInt32 = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { rawValue |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { rawValue |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { rawValue |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { rawValue |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { rawValue |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue)
    }

    private static func momentumValue(_ phase: NSEvent.Phase) -> Int {
        if phase.contains(.began) { return 1 }
        if phase.contains(.stationary) { return 2 }
        if phase.contains(.changed) { return 3 }
        if phase.contains(.ended) { return 4 }
        if phase.contains(.cancelled) { return 5 }
        if phase.contains(.mayBegin) { return 6 }
        return 0
    }

    private static func makeEnvironment() -> (
        values: [ghostty_env_var_s],
        storage: [UnsafeMutablePointer<CChar>]
    ) {
        let pairs = [
            ("TERM", "xterm-256color"),
            ("COLORTERM", "truecolor"),
            ("TERM_PROGRAM", "Tidy")
        ]
        var storage: [UnsafeMutablePointer<CChar>] = []
        var values: [ghostty_env_var_s] = []

        for (key, value) in pairs {
            guard let keyPointer = strdup(key), let valuePointer = strdup(value) else {
                continue
            }
            storage.append(keyPointer)
            storage.append(valuePointer)
            values.append(
                ghostty_env_var_s(
                    key: UnsafePointer(keyPointer),
                    value: UnsafePointer(valuePointer)
                )
            )
        }
        return (values, storage)
    }
}
