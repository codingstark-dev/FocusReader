import AppKit
import CoreGraphics

// MARK: - Books Window Tracker
/// Uses CGWindowListCopyWindowInfo (no permissions needed) to track
/// the Books reading window position and attach our toolbar to it.

final class BooksWindowTracker {

    struct BooksWindowInfo {
        let windowID: CGWindowID
        let frame:    CGRect       // Screen coordinates (top-left origin)
        let title:    String
    }

    /// Returns the Books reading window (largest Books window on screen).
    static func readingWindow() -> BooksWindowInfo? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return nil }
        let booksWindows = list.compactMap { win -> BooksWindowInfo? in
            guard let owner = win[kCGWindowOwnerName as String] as? String,
                  owner == "Books",
                  let layer = win[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = win[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  let wid = win[kCGWindowNumber as String] as? Int,
                  bounds.width > 400, bounds.height > 300  // Reading window is large
            else { return nil }
            let title = win[kCGWindowName as String] as? String ?? "Apple Book"
            return BooksWindowInfo(windowID: CGWindowID(wid), frame: bounds, title: title)
        }
        // Return the largest window (the reading window, not palette/library)
        return booksWindows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
    }

    /// Converts CGWindowList frame (top-left origin) to AppKit frame (bottom-left origin)
    static func appKitFrame(from cgFrame: CGRect) -> NSRect {
        guard let screen = NSScreen.main else { return cgFrame }
        let screenH = screen.frame.height
        return NSRect(
            x: cgFrame.minX,
            y: screenH - cgFrame.maxY,
            width: cgFrame.width,
            height: cgFrame.height
        )
    }
}
