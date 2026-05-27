# FocusReader

FocusReader is a lightweight macOS menu bar utility that provides an RSVP (Rapid Serial Visual Presentation) speed-reading overlay. It works by extracting text directly from active Apple Books windows or by opening and parsing local EPUB files.

It is designed for speed readers who want to eliminate subvocalization while reading their books on macOS.

## Key Features

- **Apple Books Integration**: Attaches a floating speed-reading toolbar directly to the active Apple Books window and extracts text using macOS Accessibility APIs.
- **Local EPUB Library**: Supports loading local EPUB books. It extracts archives, parses XML OPF spine files for correct chapter sequencing, and maintains a local cache using SHA256 file hashes.
- **Persistent Overlay**: The RSVP panel is configured with `hidesOnDeactivate = false` so that it remains visible when you click or focus other windows (such as clicking the underlying Apple Books window).
- **First Mouse Interaction**: Built using a custom `NSHostingView` subclass that overrides `acceptsFirstMouse(for:)` to return `true`. This allows you to pause, play, adjust speed, or scrub reading progress on the first click, even when the overlay window is in the background.
- **Session Preservation**: Pausing and resuming does not trigger full re-scrapes or re-compilation of the book. If the panel is hidden, clicking "Focus Read" brings it back to your exact reading position.
- **Page Estimation**: Estimates your current page (`Page X of Y`) dynamically using a standard 300 words-per-page model, alongside the exact word counter.
- **Background Update Checker**: Checks for newer releases on GitHub at launch, displaying a direct download trigger in the Settings panel and a temporary menu item in the status bar if an update is available.

## Under the Hood

### Apple Books Text Extraction
The app uses the `AXUIElement` Accessibility APIs to traverse the view hierarchy of the active Apple Books window. It extracts the visible text on the page, filters out page numbers and header noise, and feeds it directly into the RSVP timing engine.

### EPUB Spine Parsing
For local files, FocusReader unzips the EPUB archive and parses the Open Packaging Format (OPF) XML files. It extracts the manifest and spine elements to build a reliable ordered array of content documents (HTML/XHTML), which are then parsed and stripped of markup to construct the readable stream.

### AppKit Overlay
The RSVP overlay is built as a borderless `NSPanel` floating at the `.floating` level. To prevent the window from stealing focus or triggering workspace switches on activation, the panel uses the `.nonActivatingPanel` style mask and is round-clipped directly at the window's root frame.

## Keyboard Shortcuts

The reading overlay can be controlled entirely from your keyboard:

| Key | Action | Scope |
| :--- | :--- | :--- |
| `⌥⌘R` | Launch reader / Focus read current book | Global |
| `Space` | Play / Pause | Active Overlay |
| `Esc` | Close reader or settings drawer | Active Overlay |
| `←` | Skip backward 15 words | Active Overlay |
| `→` | Skip forward 15 words | Active Overlay |
| `↑` | Increase reading speed (WPM) | Active Overlay |
| `↓` | Decrease reading speed (WPM) | Active Overlay |
| `Z` | Toggle Zen mode (minimal UI) | Active Overlay |

## Requirements

- macOS 13.0 (Ventura) or later
- Accessibility Permissions enabled (required to read text from Apple Books and register the global hotkey)
- Xcode Command Line Tools (only if building from source)

## How to Install

### Using the Prebuilt DMG
1. Download the latest `FocusReader.dmg` from the GitHub releases page.
2. Double-click the DMG and drag **Focus Reader** to your `/Applications` directory.

### Building from Source
If you prefer to compile the application yourself, you can use the provided build script:

```bash
./build.sh
```

This compiles the Swift package in release mode, configures the Info.plist with the correct bundle identifier, signs the binary ad-hoc, and packages the result into a clean disk image at `FocusReaderApp/FocusReader.dmg`.

You can run the app immediately using:
```bash
open FocusReaderApp/FocusReader.app
```

## Accessibility Permissions

Because FocusReader interacts with other processes (Apple Books) to read text and uses a global shortcut to start reading, it requires macOS Accessibility permissions.

To grant access:
1. Open **System Settings**.
2. Go to **Privacy & Security** > **Accessibility**.
3. Click the `+` button, add **Focus Reader**, and ensure the toggle is enabled.
4. If you update the application, you may need to toggle this permission off and back on to clear the system's security cache.

## License

FocusReader is available under the MIT License.