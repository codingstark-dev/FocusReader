import AppKit
import ApplicationServices

// MARK: - Books Text Extraper
/// Uses macOS Accessibility APIs (AXUIElement) to scrape the visible page text from the frontmost Books window.
/// Bypasses SQLite flush delays to give instant, 100% correct page updates.
struct BooksTextExtractor {

    /// Scrapes all visible text from Apple Books' active reading view.
    static func extractVisiblePageText() -> String? {
        // 1. Get the running Books process
        let apps = NSWorkspace.shared.runningApplications
        guard let booksApp = apps.first(where: { $0.bundleIdentifier == "com.apple.iBooksX" }) else {
            return nil
        }
        let pid = booksApp.processIdentifier
        
        // 2. Create the AX application node
        let appElement = AXUIElementCreateApplication(pid)
        
        // 3. Retrieve the frontmost window
        var activeWindowRef: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &activeWindowRef)
        
        var targetWindow: AXUIElement?
        if windowResult == .success {
            targetWindow = (activeWindowRef as! AXUIElement)
        } else {
            // Fallback: search all windows and pick the largest one
            var windowsRef: CFTypeRef?
            let allWindowsResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
            if allWindowsResult == .success, let windows = windowsRef as? [AXUIElement], !windows.isEmpty {
                // Find the window with the largest dimensions
                targetWindow = windows.max(by: { w1, w2 in
                    let size1 = windowSize(w1)
                    let size2 = windowSize(w2)
                    return size1.width * size1.height < size2.width * size2.height
                })
            }
        }
        
        guard let window = targetWindow else { return nil }
        
        // 4. Locate the AXWebArea (isolated EPUB content canvas)
        var textAccumulator = ""
        if let webArea = findWebArea(in: window) {
            // If found, recursively extract text ONLY from the reading viewport
            traverseAndExtract(webArea, text: &textAccumulator)
        } else {
            // Fallback: Scrape the entire window if AXWebArea isn't resolved (e.g. PDF view or older macOS)
            traverseAndExtract(window, text: &textAccumulator)
        }
        
        let cleanedText = cleanText(textAccumulator)
        return cleanedText.isEmpty ? nil : cleanedText
    }
    
    // MARK: - Private Helpers
    
    private static func windowSize(_ element: AXUIElement) -> CGSize {
        var sizeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success {
            var size = CGSize.zero
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
            return size
        }
        return .zero
    }

    /// Recursively searches the accessibility tree for the AXWebArea element
    private static func findWebArea(in element: AXUIElement) -> AXUIElement? {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        
        if role == "AXWebArea" {
            return element
        }
        
        var childrenRef: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        if childrenResult == .success, let children = childrenRef as? [AXUIElement] {
            for child in children {
                if let found = findWebArea(in: child) {
                    return found
                }
            }
        }
        return nil
    }

    /// Traverse nodes and accumulate text content
    private static func traverseAndExtract(_ element: AXUIElement, text: inout String) {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        
        // Exclude common UI controls that don't house reading text
        let excludedRoles = ["AXButton", "AXSlider", "AXScrollBar", "AXImage", "AXPopUpButton", "AXMenuButton", "AXColorWell", "AXList"]
        if excludedRoles.contains(role) {
            return
        }
        
        // Query the node's value attribute
        var valueRef: CFTypeRef?
        let valueRes = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        if valueRes == .success, let valStr = valueRef as? String, !valStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text += valStr + " "
        } else {
            // Fallback: Query the node's title attribute if value is blank and element is a static text field
            if role == "AXStaticText" {
                var titleRef: CFTypeRef?
                let titleRes = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
                if titleRes == .success, let titleStr = titleRef as? String, !titleStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    text += titleStr + " "
                }
            }
        }
        
        // Recursively inspect child elements
        var childrenRef: CFTypeRef?
        let childrenRes = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        if childrenRes == .success, let children = childrenRef as? [AXUIElement] {
            for child in children {
                traverseAndExtract(child, text: &text)
            }
        }
    }
    
    /// Normalizes and cleans the scraped text stream
    private static func cleanText(_ rawText: String) -> String {
        var txt = rawText
        // Replace multiple whitespaces/newlines with single space
        txt = txt.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return txt.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
