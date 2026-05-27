import AppKit
import ApplicationServices
import SwiftUI
import Combine

// MARK: - Attached Toolbar Window
/// A borderless NSPanel that attaches near the bottom center of the Books reading window as a floating capsule pill.
/// Features true macOS behind-window visual effect glass and high-efficiency event-driven tracking.
@MainActor
final class AttachedToolbar: NSObject {

    // MARK: - Constants
    private let toolbarHeight: CGFloat = 56
    private let pollInterval:  TimeInterval = 0.25

    // MARK: - State
    private var panel:           FocusReaderPanel?
    private var pollTimer:       Timer?
    private var isVisible:       Bool = false
    private let engine:          RSVPEngine
    private var rsvpPanel:       RSVPOverlayPanel?
    private var activeObservers: [Any] = []

    init(engine: RSVPEngine) {
        self.engine = engine
        super.init()
        setupWorkspaceObservers()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in activeObservers {
            center.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Show / Hide
    func show() {
        buildPanelIfNeeded()
        isVisible = true
        
        let isBooksActive = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.iBooksX" }) != nil
        if isBooksActive {
            startPolling()
            updatePosition()
            panel?.orderFrontRegardless()
        } else {
            // Standalone or local library mode
            if engine.selectedLocalBookPath != nil || engine.isLibraryMode {
                showLibraryDirectly()
            }
        }
    }

    func hide() {
        isVisible = false
        stopPolling()
        panel?.orderOut(nil)
        rsvpPanel?.hide(activateBooks: false)
    }

    // MARK: - Build Panel
    private func buildPanelIfNeeded() {
        guard panel == nil else { return }

        let toolbar = ToolbarView(
            engine: engine,
            onFocusRead: { [weak self] in self?.startFocusRead() },
            onClose:      { [weak self] in self?.hide() }
        )
        let hostingView = FocusReaderHostingView(rootView: toolbar)

        let p = FocusReaderPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: toolbarHeight),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        
        // Wrap the panel in true Liquid Glass using NSVisualEffectView
        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 28 // Half of height = perfect capsule pill
        visualEffect.layer?.masksToBounds = true
        
        hostingView.frame = visualEffect.bounds
        hostingView.autoresizingMask = [.width, .height]
        visualEffect.addSubview(hostingView)
        
        p.contentView = visualEffect
        p.isOpaque              = false
        p.backgroundColor       = .clear
        p.hasShadow             = true
        p.level                 = .floating
        p.isMovable             = false
        p.collectionBehavior    = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed  = false
        p.ignoresMouseEvents    = false
        self.panel = p
    }

    // MARK: - Workspace Notification Handlers
    private func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        
        // Listen for Books becoming active
        let obs1 = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.iBooksX" else { return }
            
            Task { @MainActor [weak self] in
                guard let self = self, self.isVisible else { return }
                if self.engine.selectedLocalBookPath != nil || self.engine.isLibraryMode { return }
                self.startPolling()
                self.updatePosition()
                self.panel?.orderFrontRegardless()
            }
        }
        
        // Listen for Books losing focus — wait briefly to see if our own app took focus before hiding to save battery
        let obs2 = center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.iBooksX" else { return }
            
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.engine.selectedLocalBookPath != nil || self.engine.isLibraryMode { return }
                
                // Allow a small delay to check if our own app or its panel took focus
                try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
                let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                if frontApp == "com.focusreader.books" || frontApp == "com.apple.iBooksX" {
                    return
                }
                
                self.stopPolling()
                self.panel?.orderOut(nil)
                self.rsvpPanel?.hide(activateBooks: false)
            }
        }
        
        // Listen for internal "com.focusreader.readActiveBook" notification to trigger reading
        let obs3 = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("com.focusreader.readActiveBook"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.startFocusRead()
            }
        }
        
        activeObservers = [obs1, obs2, obs3]
    }

    // MARK: - Position Tracking Poller
    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updatePosition()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func updatePosition() {
        if engine.zenMode {
            if panel?.isVisible == true { panel?.orderOut(nil) }
            return
        }
        
        if engine.selectedLocalBookPath != nil || engine.isLibraryMode {
            if panel?.isVisible == true { panel?.orderOut(nil) }
            return
        }
        
        guard let booksWin = BooksWindowTracker.readingWindow() else {
            if panel?.isVisible == true { panel?.orderOut(nil) }
            if !engine.isPlaying && !(rsvpPanel?.isPanelVisible ?? false) {
                rsvpPanel?.hide(activateBooks: false)
            }
            return
        }

        let appKitFrame = BooksWindowTracker.appKitFrame(from: booksWin.frame)

        // Float the sleek capsule pill centered at the bottom inside edge of Books window
        let toolbarWidth: CGFloat = 680
        let toolbarFrame = NSRect(
            x:      appKitFrame.midX - toolbarWidth/2,
            y:      appKitFrame.minY + 24, // Centered and raised slightly from the bottom bezel
            width:  toolbarWidth,
            height: toolbarHeight
        )

        if panel?.frame != toolbarFrame {
            panel?.setFrame(toolbarFrame, display: true)
        }

        // Maintain visibility based on Books or Focus Reader status
        let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let isBooksActive = (frontApp == "com.apple.iBooksX" || frontApp == "com.focusreader.books")
        if isBooksActive && isVisible {
            if panel?.isVisible == false {
                panel?.orderFrontRegardless()
            }
        } else if panel?.isVisible == true {
            panel?.orderOut(nil)
        }

        // Sync RSVP overlay position
        rsvpPanel?.updatePosition(booksFrame: appKitFrame)
    }

    // MARK: - Focus Read Action
    func startFocusRead() {
        engine.pause()

        var willLoadAsync = false

        if let booksWin = BooksWindowTracker.readingWindow(),
           NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.iBooksX" }) != nil {
            
            if let scrapedText = BooksTextExtractor.extractVisiblePageText(), !scrapedText.isEmpty {
                let cleanedWords = scrapedText.components(separatedBy: .whitespacesAndNewlines)
                                              .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                if !cleanedWords.isEmpty {
                    let cleanedTitle = booksWin.title.replacingOccurrences(of: " — Books", with: "")
                                                      .replacingOccurrences(of: " – Books", with: "")
                    engine.load(words: cleanedWords, startAt: 0, title: cleanedTitle, author: "Apple Books (Active Page)")
                    engine.selectedLocalBookPath = nil
                } else {
                    willLoadAsync = true
                    loadCurrentBook(playOnLoad: true)
                }
            } else {
                willLoadAsync = true
                loadCurrentBook(playOnLoad: true)
            }
        } else {
            if engine.selectedLocalBookPath == nil && !engine.hasContent {
                engine.isLibraryMode = true
            }
        }

        if rsvpPanel == nil {
            rsvpPanel = RSVPOverlayPanel(engine: engine, onClose: { [weak self] in
                self?.engine.pause()
                self?.engine.zenMode = false
                self?.rsvpPanel?.hide(activateBooks: true)
            })
        }

        if engine.zenMode {
            engine.zenMode = false
        }

        if let booksWin = BooksWindowTracker.readingWindow() {
            let frame = BooksWindowTracker.appKitFrame(from: booksWin.frame)
            rsvpPanel?.show(over: frame)
        } else {
            rsvpPanel?.show(over: nil)
        }

        if !willLoadAsync {
            engine.play()
        }
    }

    func showLibraryDirectly() {
        buildPanelIfNeeded()
        if rsvpPanel == nil {
            rsvpPanel = RSVPOverlayPanel(engine: engine, onClose: { [weak self] in
                self?.engine.pause()
                self?.rsvpPanel?.hide(activateBooks: true)
            })
        }
        rsvpPanel?.show(over: nil)
    }

    func loadCurrentBook(playOnLoad: Bool = false) {
        guard let book = BooksLibrary.mostRecentBook() else {
            engine.load(words: ["No", "book", "found", "—", "open", "a", "book", "in", "Books", "first."],
                         startAt: 0, title: "No book found", author: "")
            return
        }
        engine.isLoading = true
        let path = book.epubPath
        let progressVal = book.readingProgress
        let title = book.title
        let author = book.author
        
        Task.detached(priority: .userInitiated) {
            let (words, startIdx, _) = EPUBParser.wordsFrom(epubPath: path, progress: progressVal)
            
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.engine.load(words: words, startAt: startIdx, title: title, author: author)
                self.engine.isLoading = false
                if playOnLoad {
                    self.engine.play()
                }
            }
        }
    }
}

// MARK: - RSVP Overlay Panel
@MainActor
final class RSVPOverlayPanel: NSObject, NSWindowDelegate {
    private var panel: FocusReaderPanel?
    private let engine: RSVPEngine
    private let onClose: () -> Void
    private var cancellables = Set<AnyCancellable>()

    // Relative positioning
    private var relativeOffset: NSPoint = .zero
    private var hasUserDragged: Bool = false
    private var isUpdatingFromBooks: Bool = false
    private var nonZenFrame: NSRect? = nil

    var isPanelVisible: Bool { panel?.isVisible ?? false }

    init(engine: RSVPEngine, onClose: @escaping () -> Void) {
        self.engine  = engine
        self.onClose = onClose
        super.init()
        buildPanel()
        
        // Observe zenMode changes to resize and level the panel
        engine.$zenMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isZen in
                self?.handleZenModeChange(isZen)
            }
            .store(in: &cancellables)
    }

    private func handlePanelKeyEvent(_ event: NSEvent) -> Bool {
        guard panel?.isVisible == true else { return false }

        switch event.keyCode {
        case 53:
            if engine.zenMode {
                withAnimation(.spring(response: 0.25)) {
                    engine.zenMode = false
                }
            } else {
                onClose()
            }
            return true
        case 49:
            engine.togglePlayPause()
            return true
        case 123:
            engine.skipBack()
            return true
        case 124:
            engine.skipForward()
            return true
        case 126:
            engine.increaseWPM()
            return true
        case 125:
            engine.decreaseWPM()
            return true
        case 6:
            withAnimation(.spring(response: 0.25)) {
                engine.zenMode.toggle()
                engine.triggerHaptics(.generic)
            }
            return true
        default:
            return false
        }
    }

    // MARK: - Zen Mode
    private func handleZenModeChange(_ isZen: Bool) {
        guard let panel = panel else { return }
        
        if isZen {
            // Save the current frame to restore later
            nonZenFrame = panel.frame
            
            // Go full screen using visibleFrame (excludes menu bar + Dock)
            if let screen = panel.screen ?? NSScreen.main {
                if let visualEffect = panel.contentView as? NSVisualEffectView {
                    visualEffect.layer?.cornerRadius = 0
                }
                if let themeFrame = panel.contentView?.superview {
                    themeFrame.layer?.cornerRadius = 0
                }
                panel.isMovable = false
                panel.isMovableByWindowBackground = false
                panel.setFrame(screen.frame, display: true, animate: true)
                panel.level = .screenSaver // High level above other apps
            }
        } else {
            if let visualEffect = panel.contentView as? NSVisualEffectView {
                visualEffect.wantsLayer = true
                visualEffect.layer?.cornerRadius = 24
                visualEffect.layer?.masksToBounds = true
            }
            if let themeFrame = panel.contentView?.superview {
                themeFrame.wantsLayer = true
                themeFrame.layer?.cornerRadius = 24
                themeFrame.layer?.masksToBounds = true
            }
            panel.isMovable = true
            panel.isMovableByWindowBackground = true
            panel.level = .floating
            panel.invalidateShadow()
            
            // Restore the non-zen frame
            if let restoreFrame = nonZenFrame {
                panel.setFrame(restoreFrame, display: true, animate: true)
            } else {
                // Fallback: center on screen or place over Books
                if let booksWin = BooksWindowTracker.readingWindow() {
                    let frame = BooksWindowTracker.appKitFrame(from: booksWin.frame)
                    updatePosition(booksFrame: frame)
                } else if let screen = panel.screen ?? NSScreen.main {
                    let w: CGFloat = 740
                    let h: CGFloat = 400
                    let x = (screen.visibleFrame.width - w) / 2 + screen.visibleFrame.minX
                    let y = (screen.visibleFrame.height - h) / 2 + screen.visibleFrame.minY
                    panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true, animate: true)
                }
            }
        }
    }

    // MARK: - Show / Hide (with state reset)
    func show(over booksFrame: NSRect?) {
        // Reset drag offset when re-showing to avoid stale positioning
        hasUserDragged = false
        relativeOffset = .zero
        NSApp.activate(ignoringOtherApps: true)

        if engine.zenMode {
            if let screen = panel?.screen ?? NSScreen.main {
                if let visualEffect = panel?.contentView as? NSVisualEffectView {
                    visualEffect.layer?.cornerRadius = 0
                }
                if let themeFrame = panel?.contentView?.superview {
                    themeFrame.layer?.cornerRadius = 0
                }
                panel?.isMovable = false
                panel?.isMovableByWindowBackground = false
                panel?.setFrame(screen.frame, display: true)
                panel?.level = .screenSaver
            }
        } else {
            if let visualEffect = panel?.contentView as? NSVisualEffectView {
                visualEffect.wantsLayer = true
                visualEffect.layer?.cornerRadius = 24
                visualEffect.layer?.masksToBounds = true
            }
            if let themeFrame = panel?.contentView?.superview {
                themeFrame.wantsLayer = true
                themeFrame.layer?.cornerRadius = 24
                themeFrame.layer?.masksToBounds = true
            }
            
            if let frame = booksFrame {
                let w: CGFloat = min(740, frame.width - 60)
                let h: CGFloat = 400
                
                let origin = NSPoint(x: frame.midX - w/2, y: frame.midY - h/2)
                panel?.setFrame(NSRect(origin: origin, size: NSSize(width: w, height: h)), display: true)
            } else {
                // Center on main screen
                if let screen = NSScreen.main {
                    let w: CGFloat = 740
                    let h: CGFloat = 400
                    let x = (screen.visibleFrame.width - w) / 2 + screen.visibleFrame.minX
                    let y = (screen.visibleFrame.height - h) / 2 + screen.visibleFrame.minY
                    panel?.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
                }
            }
        }
        panel?.makeKeyAndOrderFront(nil)
        panel?.orderFrontRegardless()
        panel?.invalidateShadow()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeFirstResponder(panel)
    }

    func hide(activateBooks: Bool = false) {
        panel?.orderOut(nil)
        if activateBooks, let booksApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.iBooksX" }) {
            booksApp.activate(options: [.activateIgnoringOtherApps])
        }
    }

    func updatePosition(booksFrame: NSRect) {
        guard let panel, panel.isVisible else { return }
        guard !engine.zenMode else { return } // Do not update position while in Zen Mode!
        
        let w: CGFloat = min(740, booksFrame.width - 60)
        let h: CGFloat = 400
        
        isUpdatingFromBooks = true
        if hasUserDragged {
            let booksCenter = NSPoint(x: booksFrame.midX, y: booksFrame.midY)
            let targetCenter = NSPoint(x: booksCenter.x + relativeOffset.x, y: booksCenter.y + relativeOffset.y)
            panel.setFrame(NSRect(x: targetCenter.x - w/2, y: targetCenter.y - h/2, width: w, height: h), display: false)
        } else {
            panel.setFrame(NSRect(x: booksFrame.midX - w/2, y: booksFrame.midY - h/2, width: w, height: h), display: false)
        }
        isUpdatingFromBooks = false
    }

    // MARK: - NSWindowDelegate
    func windowDidMove(_ notification: Notification) {
        guard !isUpdatingFromBooks else { return }
        guard !engine.zenMode else { return } // Ignore dragging updates while in Zen Mode!
        guard let booksWin = BooksWindowTracker.readingWindow() else { return }
        let booksFrame = BooksWindowTracker.appKitFrame(from: booksWin.frame)
        guard let panel = panel else { return }
        
        let panelCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let booksCenter = NSPoint(x: booksFrame.midX, y: booksFrame.midY)
        
        self.relativeOffset = NSPoint(x: panelCenter.x - booksCenter.x, y: panelCenter.y - booksCenter.y)
        self.hasUserDragged = true
    }

    private func buildPanel() {
        let view = RSVPOverlayView(engine: engine, onClose: onClose)
        let hostingView = FocusReaderHostingView(rootView: view)
        
        let p = FocusReaderPanel(
            contentRect: NSRect(x: 0, y: 0, width: 740, height: 400),
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        
        // Wrap the panel in true Liquid Glass using NSVisualEffectView
        let visualEffect = NSVisualEffectView()
        visualEffect.blendingMode = .behindWindow
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        hostingView.frame = visualEffect.bounds
        hostingView.autoresizingMask = [.width, .height]
        visualEffect.addSubview(hostingView)
        
        p.contentView = visualEffect
        
        // Configure layer *after* setting contentView
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 24 // Subtly curved overlays
        visualEffect.layer?.masksToBounds = true
        
        if let themeFrame = p.contentView?.superview {
            themeFrame.wantsLayer = true
            themeFrame.layer?.cornerRadius = 24
            themeFrame.layer?.masksToBounds = true
        }
        p.isOpaque       = false
        p.backgroundColor = .clear
        p.hasShadow      = true
        p.level          = .floating
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovable = true
        p.isMovableByWindowBackground = true
        p.delegate = self
        p.keyEventHandler = { [weak self] event in
            guard let self else { return false }
            return self.handlePanelKeyEvent(event)
        }
        
        self.panel = p
    }
}

// MARK: - FocusReaderPanel
/// A custom NSPanel subclass that overrides canBecomeKey to allow borderless panels to receive keyboard focus.
final class FocusReaderPanel: NSPanel {
    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }

    var keyEventHandler: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if keyEventHandler?(event) == true {
                return // Swallowed!
            }
        }
        super.sendEvent(event)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if !self.styleMask.contains(.nonactivatingPanel) {
            if !self.isKeyWindow {
                self.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

// MARK: - FocusReaderHostingView
/// A custom NSHostingView subclass that overrides acceptsFirstMouse to allow click-through,
/// so buttons and sliders respond immediately to the first click even if the window is in the background.
final class FocusReaderHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}
