import AppKit
import AVFoundation
import Carbon.HIToolbox
import CryptoKit

// Dictate — push-to-talk dictation for macOS. Speech is transcribed on this Mac by whisper.cpp; no network code.
// Model, language, prompt and hotkey are set in the app: menu bar icon → Settings…
// After changing this file run: bash build.sh

let defaultHotKey = "Cmd+L"
let supportDir = NSHomeDirectory() + "/Library/Application Support/Dictate"
let openWhisprModels = NSHomeDirectory() + "/.cache/openwhispr/whisper-models"
// whisper-cli: the copy inside Dictate.app (DMG build) first, then a manual build, then Homebrew.
let whisperCandidates: [String] = [Bundle.main.path(forAuxiliaryExecutable: "whisper-cli")].compactMap { $0 }
    + [supportDir + "/whisper-cli", "/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"]

// MARK: - Models

struct ModelPreset {
    let name: String
    let file: String
    let size: String
    let note: String
    let sha1: String   // from the models table in the whisper.cpp repository

    /// Opened in the browser: Dictate itself never downloads anything.
    var downloadURL: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/" + file)! }

    /// Where the file already is: Dictate's folder first, then OpenWhispr's cache.
    var installedPath: String? {
        [supportDir + "/" + file, openWhisprModels + "/" + file].first { FileManager.default.fileExists(atPath: $0) }
    }
}

let presets = [
    ModelPreset(name: "Large v3 Turbo", file: "ggml-large-v3-turbo.bin", size: "1.6 GB",
                note: "Recommended. Nearly Large v3 accuracy, several times faster.",
                sha1: "4af2b29d7ec73d781377bfd1758ca957a807e941"),
    ModelPreset(name: "Large v3", file: "ggml-large-v3.bin", size: "3.1 GB",
                note: "Most accurate and slowest.",
                sha1: "ad82bf6a9043ceed055076d0fd39f5f186ff8062"),
    ModelPreset(name: "Large v3 Turbo Q5", file: "ggml-large-v3-turbo-q5_0.bin", size: "574 MB",
                note: "Smallest and fastest, slightly less accurate.",
                sha1: "e050f7970618a659205450ad97eb95a18d69c9ee"),
]

let languages: [(name: String, code: String)] = [
    ("Auto-detect", "auto"), ("English", "en"), ("Russian", "ru"), ("Ukrainian", "uk"), ("German", "de"),
    ("French", "fr"), ("Spanish", "es"), ("Italian", "it"), ("Portuguese", "pt"), ("Polish", "pl"),
    ("Turkish", "tr"), ("Chinese", "zh"), ("Japanese", "ja"), ("Korean", "ko"),
]

enum ImportResult {
    case preset(Int, copied: Bool)
    case custom
    case failed(String)
}

/// whisper.cpp model files start with the ggml magic "lmgg".
func isWhisperModel(_ path: String) -> Bool {
    let magic = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)).read(upToCount: 4)
    return magic == Data("lmgg".utf8)
}

func sha1(ofFile path: String) -> String? {
    guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? handle.close() }
    var hasher = Insecure.SHA1()
    do {
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
    } catch {
        return nil
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

/// Checks a picked file against the three official checksums. A known model is copied into Dictate's
/// folder (an instant clone on APFS), so it keeps working after the original download is deleted.
func verifyAndImport(_ path: String) -> ImportResult {
    guard let digest = sha1(ofFile: path) else { return .failed("Couldn't read the file.") }
    guard let index = presets.firstIndex(where: { $0.sha1 == digest }) else { return .custom }
    let target = supportDir + "/" + presets[index].file
    if path == target || FileManager.default.fileExists(atPath: target) { return .preset(index, copied: false) }
    do {
        try FileManager.default.createDirectory(atPath: supportDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: path, toPath: target)
        return .preset(index, copied: true)
    } catch {
        return .failed(error.localizedDescription)
    }
}

// MARK: - Hotkey text parsing ("Cmd+L", "ctrl opt space", "⇧⌘D", "F5")

let keyCodes: [String: Int] = [
    "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E, "F": kVK_ANSI_F,
    "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
    "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R,
    "S": kVK_ANSI_S, "T": kVK_ANSI_T, "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
    "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
    "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
    "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    "SPACE": kVK_Space, "RETURN": kVK_Return, "ENTER": kVK_Return, "TAB": kVK_Tab, "ESC": kVK_Escape, "ESCAPE": kVK_Escape,
    "F1": kVK_F1, "F2": kVK_F2, "F3": kVK_F3, "F4": kVK_F4, "F5": kVK_F5, "F6": kVK_F6,
    "F7": kVK_F7, "F8": kVK_F8, "F9": kVK_F9, "F10": kVK_F10, "F11": kVK_F11, "F12": kVK_F12,
]

struct HotKey {
    let code: UInt32
    let modifiers: UInt32
    let text: String   // normalized, saved in settings: "Cmd+Shift+D"
    let title: String  // shown in the menu: "⇧⌘D"

    init?(_ input: String) {
        var spelled = input
        for (symbol, word) in [("⌘", "+Cmd+"), ("⌥", "+Opt+"), ("⌃", "+Ctrl+"), ("⇧", "+Shift+")] {
            spelled = spelled.replacingOccurrences(of: symbol, with: word)
        }
        var mods = 0
        var found: String?
        for part in spelled.split(whereSeparator: { $0 == "+" || $0 == "-" || $0.isWhitespace }) {
            switch part.uppercased() {
            case "CMD", "COMMAND": mods |= cmdKey
            case "OPT", "OPTION", "ALT": mods |= optionKey
            case "CTRL", "CONTROL": mods |= controlKey
            case "SHIFT": mods |= shiftKey
            case let token:
                guard found == nil, keyCodes[token] != nil else { return nil }
                found = token
            }
        }
        guard let key = found, let keyCode = keyCodes[key] else { return nil }
        // A bare letter would swallow normal typing, so require a modifier (F1–F12 may go alone).
        guard mods != 0 || (key.count > 1 && key.hasPrefix("F")) else { return nil }
        let name = key.count == 1 ? key : String(key.prefix(1)) + key.dropFirst().lowercased()
        let wordOrder: [(Int, String)] = [(cmdKey, "Cmd"), (controlKey, "Ctrl"), (optionKey, "Opt"), (shiftKey, "Shift")]
        let symbolOrder: [(Int, String)] = [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
        let words: [String] = wordOrder.filter { (mods & $0.0) != 0 }.map { $0.1 }
        let symbols: [String] = symbolOrder.filter { (mods & $0.0) != 0 }.map { $0.1 }
        code = UInt32(keyCode)
        modifiers = UInt32(mods)
        text = (words + [name]).joined(separator: "+")
        title = symbols.joined() + name
    }
}

func hotKeyHandler(_: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    var pressed = EventHotKeyID()
    _ = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                          nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
    let id = pressed.id
    let dictate = Unmanaged<Dictate>.fromOpaque(userData!).takeUnretainedValue()
    DispatchQueue.main.async {
        if id == 2 { dictate.cancel() } else { dictate.toggle() }  // id 2 = Escape while recording
    }
    return noErr
}

// MARK: - App

@main
@MainActor
final class Dictate: NSObject, NSApplicationDelegate {
    enum State { case idle, recording, transcribing }

    var state = State.idle
    var statusItem: NSStatusItem!
    var hud: NSPanel!
    var hudLabel: NSTextField!
    var recorder: AVAudioRecorder?
    var hotKeyRef: EventHotKeyRef?
    var escapeRef: EventHotKeyRef?
    var hotKey: HotKey?
    var hotKeyItem: NSMenuItem!

    var settingsWindow: NSWindow?
    var modelButtons: [NSButton] = []      // three presets, then "Other file"
    var statusLabels: [NSTextField] = []
    var downloadButtons: [NSButton] = []
    var modelField: NSTextField!
    var chooseButton: NSButton!
    var saveButton: NSButton!
    var statusLine: NSTextField!
    var languagePopup: NSPopUpButton!
    var promptField: NSTextField!
    var hotKeyField: NSTextField!

    let wavURL = FileManager.default.temporaryDirectory.appendingPathComponent("dictate.wav")

    /// The chosen model, or the first preset found on disk.
    var modelPath: String? {
        UserDefaults.standard.string(forKey: "modelPath") ?? presets.compactMap { $0.installedPath }.first
    }
    var language: String { UserDefaults.standard.string(forKey: "language") ?? "auto" }
    var prompt: String { UserDefaults.standard.string(forKey: "prompt") ?? "" }

    static func main() {
        let app = NSApplication.shared
        let dictate = Dictate()
        app.delegate = dictate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(dictate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        hotKeyItem = menu.addItem(withTitle: "No hotkey set", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Dictate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        installEditMenu()
        buildHUD()
        show(.idle)

        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), nil)
        let saved = UserDefaults.standard.string(forKey: "hotKey") ?? defaultHotKey
        var hotKeyWorks = false
        if let key = HotKey(saved) { hotKeyWorks = useHotKey(key) }
        if !hotKeyWorks {
            alert("The hotkey “\(saved)” isn't valid or is already used by another app. Set a different one in Settings.")
        }
        // First run: pick a model (and a hotkey, if the default one is taken).
        if !hotKeyWorks || modelPath == nil { openSettings() }
    }

    /// Registers `key` instead of the current hotkey. If the system refuses it, the old one is restored.
    func useHotKey(_ key: HotKey) -> Bool {
        let old = hotKey
        if registerHotKey(key) {
            hotKey = key
            hotKeyItem.title = "\(key.title) — start / stop dictation"
            return true
        }
        if let old { _ = registerHotKey(old) }
        return false
    }

    func registerHotKey(_ key: HotKey) -> Bool {
        if let ref = hotKeyRef {
            _ = UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        let id = EventHotKeyID(signature: OSType(0x4449_4354), id: 1)  // 'DICT'
        return RegisterEventHotKey(key.code, key.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr
    }

    /// Escape is grabbed only while recording, so it works normally in other apps the rest of the time.
    func setEscapeEnabled(_ enabled: Bool) {
        if enabled, escapeRef == nil {
            let id = EventHotKeyID(signature: OSType(0x4449_4354), id: 2)
            _ = RegisterEventHotKey(UInt32(kVK_Escape), 0, id, GetApplicationEventTarget(), 0, &escapeRef)
        } else if !enabled, let ref = escapeRef {
            _ = UnregisterEventHotKey(ref)
            escapeRef = nil
        }
    }

    // MARK: Recording and transcription

    func toggle() {
        switch state {
        case .idle: start()
        case .recording: stop()
        case .transcribing: NSSound.beep()
        }
    }

    func start() {
        guard let path = modelPath, FileManager.default.fileExists(atPath: path) else {
            alert("Choose a speech model first: download one of the three models or pick a model file you already have.")
            return openSettings()
        }
        guard whisperCandidates.contains(where: FileManager.default.isExecutableFile(atPath:)) else {
            return alert("whisper-cli not found.\n\nInstall Dictate from the DMG (it includes whisper-cli) or run: brew install whisper.cpp")
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        guard let recorder = try? AVAudioRecorder(url: wavURL, settings: settings), recorder.record() else {
            return alert("Recording didn't start. Check microphone access: System Settings → Privacy & Security → Microphone.")
        }
        self.recorder = recorder
        NSSound(named: "Tink")?.play()
        show(.recording)
    }

    func stop() {
        guard let recorder else { return show(.idle) }
        let seconds = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        NSSound(named: "Pop")?.play()
        guard seconds > 0.5, let path = modelPath,
              let whisper = whisperCandidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            try? FileManager.default.removeItem(at: wavURL)
            return show(.idle)
        }
        show(.transcribing)
        var arguments = ["-m", path, "-f", wavURL.path, "-l", language, "-nt"]
        if !prompt.isEmpty { arguments += ["--prompt", prompt] }
        let job = arguments
        DispatchQueue.global(qos: .userInitiated).async {
            let text = Dictate.transcribe(whisper, job)
            DispatchQueue.main.async { self.finish(text) }
        }
    }

    func cancel() {
        guard state == .recording, let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        self.recorder = nil
        NSSound(named: "Funk")?.play()
        show(.idle)
    }

    nonisolated static func transcribe(_ whisper: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: whisper)
        process.arguments = arguments
        // Clean environment and a non-writable working directory: ggml loads extra libraries named in
        // GGML_BACKEND_PATH / ANEFORGE_DYLIB / DYLD_* and libggml-*.so found in the current directory.
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "TMPDIR": NSTemporaryDirectory()]
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    func finish(_ text: String) {
        try? FileManager.default.removeItem(at: wavURL)
        show(.idle)
        guard !text.isEmpty else { return NSSound.beep() }
        // currentHostOnly: keep the text on this Mac, never hand it to Universal Clipboard (other Apple devices)
        NSPasteboard.general.prepareForNewContents(with: .currentHostOnly)
        NSPasteboard.general.setString(text, forType: .string)
        guard AXIsProcessTrusted() else {
            return alert("The text is on the clipboard — press ⌘V to paste it.\n\nTo paste automatically, enable Dictate in System Settings → Privacy & Security → Accessibility, then quit and reopen Dictate.")
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    // MARK: Settings window

    let defaultStatus = "Download opens your browser. When the file arrives, click Choose… and pick it: Dictate checks it against the official checksum and keeps a copy in ~/Library/Application Support/Dictate."

    @objc func openSettings() {
        if settingsWindow == nil { buildSettings() }
        refreshModelStatus()
        let current = modelPath
        if let index = presets.firstIndex(where: { $0.installedPath != nil && $0.installedPath == current }) {
            selectModel(index)
            modelField.stringValue = ""
        } else if let current {
            selectModel(presets.count)
            modelField.stringValue = current
        } else {
            selectModel(0)
        }
        languagePopup.selectItem(at: languages.firstIndex { $0.code == language } ?? 0)
        promptField.stringValue = prompt
        hotKeyField.stringValue = hotKey?.text ?? defaultHotKey
        statusLine.stringValue = defaultStatus
        NSApp.activate()
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func buildSettings() {
        let height: CGFloat = 520
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: height))
        // Positions are distances from the top edge, which reads easier than AppKit's bottom-up y.
        func add(_ control: NSView, x: CGFloat, top: CGFloat, width: CGFloat, height h: CGFloat) {
            control.frame = NSRect(x: x, y: height - top - h, width: width, height: h)
            view.addSubview(control)
        }
        func heading(_ text: String) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            return label
        }
        func small(_ text: String) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            return label
        }

        add(heading("Speech model"), x: 20, top: 20, width: 560, height: 18)
        for (index, preset) in presets.enumerated() {
            let top = CGFloat(48 + index * 56)
            let radio = NSButton(radioButtonWithTitle: "\(preset.name)  ·  \(preset.size)", target: self,
                                 action: #selector(modelChoiceChanged(_:)))
            add(radio, x: 20, top: top, width: 300, height: 20)
            modelButtons.append(radio)
            let status = NSTextField(labelWithString: "")
            status.alignment = .right
            add(status, x: 320, top: top + 2, width: 150, height: 17)
            statusLabels.append(status)
            let download = NSButton(title: "Download…", target: self, action: #selector(downloadPreset(_:)))
            download.tag = index
            add(download, x: 480, top: top - 6, width: 104, height: 32)
            downloadButtons.append(download)
            add(small(preset.note), x: 40, top: top + 22, width: 540, height: 16)
        }
        let other = NSButton(radioButtonWithTitle: "Other file:", target: self, action: #selector(modelChoiceChanged(_:)))
        add(other, x: 20, top: 216, width: 100, height: 20)
        modelButtons.append(other)
        modelField = NSTextField(string: "")
        modelField.placeholderString = "Path to a ggml-*.bin model"
        modelField.cell?.isScrollable = true
        modelField.cell?.wraps = false
        add(modelField, x: 124, top: 215, width: 350, height: 22)
        chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseModel))
        add(chooseButton, x: 480, top: 210, width: 104, height: 32)
        statusLine = small(defaultStatus)
        add(statusLine, x: 20, top: 248, width: 560, height: 30)

        add(heading("Recognition"), x: 20, top: 296, width: 560, height: 18)
        add(NSTextField(labelWithString: "Language:"), x: 20, top: 326, width: 125, height: 17)
        languagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        languagePopup.addItems(withTitles: languages.map { $0.name })
        add(languagePopup, x: 148, top: 320, width: 200, height: 26)
        add(NSTextField(labelWithString: "Prompt (optional):"), x: 20, top: 360, width: 125, height: 17)
        promptField = NSTextField(string: "")
        promptField.placeholderString = "e.g. Open a pull request on GitHub and run the Spark job."
        promptField.cell?.isScrollable = true
        promptField.cell?.wraps = false
        add(promptField, x: 148, top: 357, width: 432, height: 22)
        add(small("Whisper imitates this sample: its language, names, spelling and punctuation. Leave it empty if unsure."),
            x: 148, top: 383, width: 432, height: 30)

        add(NSTextField(labelWithString: "Hotkey:"), x: 20, top: 428, width: 125, height: 17)
        hotKeyField = NSTextField(string: "")
        hotKeyField.placeholderString = defaultHotKey
        add(hotKeyField, x: 148, top: 425, width: 150, height: 22)
        add(small("e.g. Cmd+L, Ctrl+Opt+Space, F5"), x: 308, top: 429, width: 272, height: 16)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(closeSettings))
        cancel.keyEquivalent = "\u{1b}"
        add(cancel, x: 372, top: 472, width: 104, height: 32)
        saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.keyEquivalent = "\r"
        add(saveButton, x: 480, top: 472, width: 104, height: 32)

        let window = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Dictate Settings"
        window.isReleasedWhenClosed = false
        window.contentView = view
        settingsWindow = window
    }

    func selectModel(_ index: Int) {
        for (i, button) in modelButtons.enumerated() { button.state = i == index ? .on : .off }
    }

    func refreshModelStatus() {
        for (index, preset) in presets.enumerated() {
            if let path = preset.installedPath {
                statusLabels[index].stringValue = path.hasPrefix(supportDir) ? "✓ Downloaded" : "✓ Found in OpenWhispr"
                statusLabels[index].textColor = .systemGreen
                downloadButtons[index].isHidden = true
            } else {
                statusLabels[index].stringValue = "Not downloaded"
                statusLabels[index].textColor = .secondaryLabelColor
                downloadButtons[index].isHidden = false
            }
        }
    }

    @objc func modelChoiceChanged(_ sender: NSButton) {
        let index = modelButtons.firstIndex(of: sender) ?? presets.count
        if index < presets.count, presets[index].installedPath == nil {
            statusLine.stringValue = "\(presets[index].name) isn't downloaded yet. Click Download…, then Choose… and pick the file."
        } else {
            statusLine.stringValue = defaultStatus
        }
    }

    @objc func downloadPreset(_ sender: NSButton) {
        let preset = presets[sender.tag]
        selectModel(sender.tag)
        NSWorkspace.shared.open(preset.downloadURL)
        statusLine.stringValue = "Your browser is downloading \(preset.file) (\(preset.size)). When it finishes, click Choose… and pick it in Downloads."
    }

    @objc func chooseModel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true  // models often live in hidden folders like ~/.cache
        panel.message = "Choose a whisper.cpp model (ggml-*.bin)"
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        guard isWhisperModel(path) else {
            return alert("This isn't a whisper.cpp model:\n\(path)\n\nPick a ggml-*.bin file.")
        }
        statusLine.stringValue = "Checking \(url.lastPathComponent)…"
        chooseButton.isEnabled = false
        saveButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async {
            let result = verifyAndImport(path)
            DispatchQueue.main.async { self.finishImport(path: path, result: result) }
        }
    }

    func finishImport(path: String, result: ImportResult) {
        chooseButton.isEnabled = true
        saveButton.isEnabled = true
        switch result {
        case .preset(let index, let copied):
            refreshModelStatus()
            selectModel(index)
            statusLine.stringValue = copied
                ? "\(presets[index].name) matches the official checksum and is in Dictate's folder now. You can delete the downloaded file. Click Save."
                : "\(presets[index].name) matches the official checksum. Click Save."
        case .custom:
            modelField.stringValue = path
            selectModel(presets.count)
            statusLine.stringValue = "Custom model: it isn't one of the three presets, so there's no official checksum to compare. Use files from sources you trust."
        case .failed(let message):
            statusLine.stringValue = defaultStatus
            alert("Couldn't use the model:\n\(message)")
        }
    }

    @objc func saveSettings() {
        let choice = modelButtons.firstIndex { $0.state == .on } ?? presets.count
        let path: String
        if choice < presets.count {
            guard let installed = presets[choice].installedPath else {
                return alert("\(presets[choice].name) isn't downloaded yet.\n\nClick Download…, then Choose… and pick the downloaded file.")
            }
            path = installed
        } else {
            path = (modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
            guard isWhisperModel(path) else {
                return alert("There's no whisper.cpp model at:\n\(path)\n\nPick a ggml-*.bin file.")
            }
        }
        guard let key = HotKey(hotKeyField.stringValue) else {
            return alert("Can't read the hotkey “\(hotKeyField.stringValue)”.\n\nExamples: Cmd+L, Ctrl+Opt+Space, Cmd+Shift+D, F5. Use Latin letters; only F1–F12 work without Cmd/Ctrl/Opt/Shift.")
        }
        guard useHotKey(key) else {
            return alert("\(key.title) is already used by another app. Choose a different hotkey.")
        }
        let defaults = UserDefaults.standard
        defaults.set(path, forKey: "modelPath")
        defaults.set(key.text, forKey: "hotKey")
        defaults.set(languages[max(0, languagePopup.indexOfSelectedItem)].code, forKey: "language")
        defaults.set(promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "prompt")
        settingsWindow?.close()
    }

    @objc func closeSettings() {
        settingsWindow?.close()
    }

    /// Accessory apps have no visible menu, but text fields need Edit key equivalents for ⌘X/⌘C/⌘V/⌘A.
    func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        let mainMenu = NSMenu()
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    // MARK: HUD and status item

    func buildHUD() {
        let frame = NSRect(x: 0, y: 0, width: 240, height: 34)
        hud = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hud.level = .statusBar
        hud.isOpaque = false
        hud.backgroundColor = .clear
        hud.hasShadow = true
        hud.ignoresMouseEvents = true
        hud.hidesOnDeactivate = false
        hud.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let box = NSView(frame: frame)
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        box.layer?.cornerRadius = 17
        hudLabel = NSTextField(labelWithString: "")
        hudLabel.frame = NSRect(x: 0, y: 8, width: frame.width, height: 18)
        hudLabel.alignment = .center
        hudLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        box.addSubview(hudLabel)
        hud.contentView = box
        if let screen = NSScreen.main?.visibleFrame {
            hud.setFrameOrigin(NSPoint(x: screen.midX - frame.width / 2, y: screen.minY + 48))
        }
    }

    func show(_ newState: State) {
        state = newState
        setEscapeEnabled(newState == .recording)
        let button = statusItem.button
        switch newState {
        case .idle:
            button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Dictate")
            button?.contentTintColor = nil
            hud.orderOut(nil)
        case .recording:
            button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
            button?.contentTintColor = .systemRed
            hudLabel.stringValue = "●  Listening   ·   Esc to cancel"
            hudLabel.textColor = .systemRed
            hud.orderFrontRegardless()
        case .transcribing:
            button?.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Transcribing")
            button?.contentTintColor = nil
            hudLabel.stringValue = "Transcribing…"
            hudLabel.textColor = .white
            hud.orderFrontRegardless()
        }
    }

    func alert(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Dictate"
        alert.informativeText = message
        alert.runModal()
    }
}
