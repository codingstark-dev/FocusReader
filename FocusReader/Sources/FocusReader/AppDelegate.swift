import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem?
    let engine = RSVPEngine()
    private var toolbar: AttachedToolbar?
    private var booksObserver: Any?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var updateCancellable: AnyCancellable?
    private var updateMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenuBar()
        setupWorkspaceObserver()
        setupKeyboardMonitors()
        // Auto-show toolbar if Books is already open with a book
        checkAndShowToolbar()

        // Start update check in the background
        UpdateChecker.shared.checkForUpdates()

        // Observe update checker using Combine
        updateCancellable = UpdateChecker.shared.$updateAvailable
            .combineLatest(UpdateChecker.shared.$latestVersion)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] available, latest in
                guard let self = self else { return }
                if available, let latest = latest {
                    self.updateMenuItem?.title = "✨ Update Available (v\(latest))"
                    self.updateMenuItem?.isHidden = false
                } else {
                    self.updateMenuItem?.isHidden = true
                }
            }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let booksObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(booksObserver)
        }
    }

    // MARK: - Menu Bar
    private func buildMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let btn = statusItem?.button else { return }
        btn.image = NSImage(systemSymbolName: "book.fill", accessibilityDescription: "Focus Reader")
        btn.image?.isTemplate = true
        btn.toolTip = "Focus Reader for Books"

        let menu = NSMenu()

        let title = NSMenuItem(title: "⚡ Focus Reader for Books", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        // Dynamic update menu item, hidden by default
        let updateItem = NSMenuItem(title: "✨ Update Available", action: #selector(openUpdatePage), keyEquivalent: "")
        updateItem.target = self
        updateItem.isHidden = true
        menu.addItem(updateItem)
        self.updateMenuItem = updateItem

        menu.addItem(.separator())

        let showToolbar = NSMenuItem(title: "Show Toolbar on Books", action: #selector(showToolbarAction), keyEquivalent: "")
        showToolbar.target = self
        menu.addItem(showToolbar)

        let readNow = NSMenuItem(title: "Focus Read Current Book", action: #selector(readNow), keyEquivalent: "")
        readNow.target = self
        menu.addItem(readNow)

        let openLibrary = NSMenuItem(title: "Open Local EPUB Library...", action: #selector(openLocalLibraryAction), keyEquivalent: "l")
        openLibrary.target = self
        menu.addItem(openLibrary)

        menu.addItem(.separator())

        let reload = NSMenuItem(title: "Reload Book from Library", action: #selector(reloadBook), keyEquivalent: "r")
        reload.target = self
        menu.addItem(reload)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    // MARK: - Workspace Observer
    // Auto-show toolbar when user opens Books
    private func setupWorkspaceObserver() {
        booksObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.iBooksX" else { return }
            Task { @MainActor [weak self] in
                self?.checkAndShowToolbar()
            }
        }
    }

    private func checkAndShowToolbar() {
        // Only show if a Books reading window exists
        guard BooksWindowTracker.readingWindow() != nil else { return }
        ensureToolbar()
        if !engine.hasContent {
            toolbar?.loadCurrentBook()
        }
        toolbar?.show()
    }

    private func ensureToolbar() {
        if toolbar == nil {
            toolbar = AttachedToolbar(engine: engine)
        }
    }

    // MARK: - Keyboard Shortcuts
    private func setupKeyboardMonitors() {
        // Global monitor for Option + Command + R (⌥⌘R)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let optionPressed = event.modifierFlags.contains(.option)
            let commandPressed = event.modifierFlags.contains(.command)
            if optionPressed && commandPressed && (event.charactersIgnoringModifiers?.lowercased() == "r") {
                Task { @MainActor [weak self] in
                    self?.readNow()
                }
            }
        }

        // Local monitor for Option + Command + R (⌥⌘R) when app is focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event -> NSEvent? in
            let optionPressed = event.modifierFlags.contains(.option)
            let commandPressed = event.modifierFlags.contains(.command)
            if optionPressed && commandPressed && (event.charactersIgnoringModifiers?.lowercased() == "r") {
                Task { @MainActor [weak self] in
                    self?.readNow()
                }
                return nil // Swallowed
            }
            return event
        }
    }

    // MARK: - Menu Actions
    @MainActor @objc func showToolbarAction() {
        ensureToolbar()
        toolbar?.loadCurrentBook()
        toolbar?.show()
    }

    @MainActor @objc func readNow() {
        ensureToolbar()
        toolbar?.startFocusRead()
    }

    @MainActor @objc func openLocalLibraryAction() {
        engine.isLibraryMode = true
        ensureToolbar()
        toolbar?.showLibraryDirectly()
    }

    @MainActor @objc func reloadBook() {
        toolbar?.loadCurrentBook()
    }

    @MainActor @objc func openUpdatePage() {
        UpdateChecker.shared.openDownloadPage()
    }
}
