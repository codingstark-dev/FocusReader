# FocusReader

FocusReader is a macOS menu bar app for reading text from Apple Books with an RSVP-style overlay. It also includes a local EPUB library flow and a small settings panel for reading controls.

## What it does

- Shows a menu bar item for launching the reader, reloading the current book, and opening the local EPUB library.
- Attaches a floating toolbar to the active Apple Books reading window when one is available.
- Displays an RSVP reading overlay with play/pause, seek, speed, and Zen mode controls.
- Uses macOS accessibility permissions to read content from Apple Books.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools

## Build

From the repository root:

```bash
./build.sh
```

The script builds the Swift package in release mode and packages the app at `FocusReaderApp/FocusReader.app`.

## Permissions

FocusReader needs Accessibility access to read text from Apple Books and support its global shortcut.

To grant it:

1. Open System Settings.
2. Go to Privacy & Security > Accessibility.
3. Add Focus Reader and enable the toggle.

## Keyboard shortcuts

- `⌥⌘R` - Start reading the current book
- `Space` - Play / pause
- `Esc` - Close the reader or settings panel
- `←` - Skip back 15 words
- `→` - Skip forward 15 words
- `↑` - Increase speed
- `↓` - Decrease speed
- `Z` - Toggle Zen mode

## Project layout

- `FocusReader/Package.swift` - Swift package definition
- `FocusReader/Sources/FocusReader/AppDelegate.swift` - App lifecycle and menu bar actions
- `FocusReader/Sources/FocusReader/BooksLibrary.swift` - Local library support
- `FocusReader/Sources/FocusReader/BooksTextExtractor.swift` - Apple Books text extraction
- `FocusReader/Sources/FocusReader/BooksWindowTracker.swift` - Reading window tracking
- `FocusReader/Sources/FocusReader/RSVPEngine.swift` - Reading state and playback logic
- `FocusReader/Sources/FocusReader/Views.swift` - Toolbar, overlay, and settings UI
- `build.sh` - Build and packaging script

## License

MIT