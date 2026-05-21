import AppKit
import SwiftUI

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory) // No Dock icon
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
