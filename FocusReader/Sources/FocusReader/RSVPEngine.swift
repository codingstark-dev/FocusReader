import Foundation
import Combine
import AppKit
import SwiftUI

// MARK: - ORP Calculator
struct ORPCalculator {
    /// Returns the display-ready word with trailing/closing punctuation stripped,
    /// while preserving internal punctuation (hyphens, apostrophes).
    static func clean(_ word: String) -> String {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        
        let stripChars = ",;:.!?\"'`()[]{}<>—–-—*_*~+=|\\/«»„“”‘’&#;"
        var startIdx = trimmed.startIndex
        var endIdx = trimmed.endIndex
        
        while startIdx < trimmed.endIndex {
            let char = trimmed[startIdx]
            if stripChars.contains(char) {
                startIdx = trimmed.index(after: startIdx)
            } else {
                break
            }
        }
        
        while endIdx > startIdx {
            let prevIdx = trimmed.index(before: endIdx)
            let char = trimmed[prevIdx]
            if stripChars.contains(char) {
                endIdx = prevIdx
            } else {
                break
            }
        }
        
        if startIdx >= endIdx {
            return ""
        }
        
        return String(trimmed[startIdx..<endIdx])
    }

    static func split(_ word: String) -> (prefix: String, focus: Character?, suffix: String) {
        let chars = Array(word)
        guard !chars.isEmpty else { return ("", nil, "") }
        
        let length = chars.count
        let idx: Int
        switch length {
        case 0...1:   idx = 0
        case 2...5:   idx = 1
        case 6...9:   idx = 2
        case 10...13: idx = 3
        default:      idx = 4
        }
        
        let safeIdx = min(idx, length - 1)
        return (
            String(chars[0..<safeIdx]),
            chars[safeIdx],
            safeIdx + 1 < length ? String(chars[(safeIdx + 1)...]) : ""
        )
    }
}

// MARK: - Glass Theme Definitions
enum GlassTheme: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case aurora = "Aurora Violet"
    case sunset = "Sunset Gold"
    case emerald = "Emerald Forest"
    case cobalt = "Cobalt Depths"

    var id: String { self.rawValue }

    var accentColor: Color {
        switch self {
        case .default: return Color(red: 1.0, green: 0.23, blue: 0.19) // Neon Red
        case .aurora:  return Color(red: 0.68, green: 0.33, blue: 1.0) // Electric Purple
        case .sunset:  return Color(red: 1.0, green: 0.58, blue: 0.0) // Warm Orange/Gold
        case .emerald: return Color(red: 0.18, green: 0.8, blue: 0.44) // Mint/Emerald
        case .cobalt:  return Color(red: 0.12, green: 0.53, blue: 0.9) // Cobalt Blue
        }
    }
}

// MARK: - Local Book Representation
struct LocalBook: Codable, Identifiable, Hashable {
    var id: String { epubPath }
    let title: String
    let author: String
    let epubPath: String
    var readingProgress: Double // 0.0 to 1.0
    var lastReadDate: Date
}

// MARK: - RSVP Engine
@MainActor
final class RSVPEngine: ObservableObject {
    @Published var words:         [String] = []
    @Published var currentIndex:  Int      = 0
    @Published var isPlaying:     Bool     = false
    @Published var wpm:           Double   = 250 {
        didSet {
            triggerHaptics()
            if isPlaying { reschedule() }
        }
    }
    @Published var bookTitle:     String   = "Open Books → press ⌥⌘R"
    @Published var bookAuthor:    String   = ""

    // ── Local Library State ──
    @Published var localLibrary:          [LocalBook] = []
    @Published var isLibraryMode:         Bool        = false
    @Published var selectedLocalBookPath: String?     = nil

    // ── UI Settings State ──
    @Published var fontFamily:    String   = "Serif"       // "Serif", "Sans", "Mono"
    @Published var fontSize:      Double   = 52.0          // 40.0, 52.0, 64.0, 80.0
    @Published var displayMode:   String   = "Flow"        // "Single" (word), "Flow" (Context Stream)
    @Published var showGuide:     Bool     = true
    @Published var smartPacing:   Bool     = true
    @Published var selectedTheme: GlassTheme = .default
    @Published var zenMode:       Bool     = false
    @Published var punctuationPauseMultiplier: Double = 2.0
    @Published var backgroundDimOpacity: Double = 0.4
    @Published var enableHaptics: Bool = true
    @Published var isLoading:     Bool = false

    var currentWord: String {
        guard !words.isEmpty, words.indices.contains(currentIndex) else { return "" }
        return words[currentIndex]
    }

    /// Returns the current word with trailing/closing punctuation stripped for clean display.
    var displayWord: String {
        ORPCalculator.clean(currentWord)
    }
    var progress:    Double { words.isEmpty ? 0 : Double(currentIndex) / Double(max(1, words.count - 1)) }
    var hasContent:  Bool   { !words.isEmpty }
    var wordCount:   Int    { words.count }
    var etaMinutes:  Double { wpm > 0 ? Double(max(0, words.count - currentIndex)) / wpm : 0 }

    // Swift Concurrency timing loop task
    private var timingTask: Task<Void, Never>?

    init() {
        // Automatically restore local library if folder is already saved
        if let savedFolder = UserDefaults.standard.string(forKey: "com.focusreader.books.libraryFolder") {
            scanFolder(at: savedFolder)
        }
    }

    func load(words: [String], startAt: Int, title: String, author: String) {
        let cleaned = words.filter { !ORPCalculator.clean($0).isEmpty }
        self.words = cleaned
        self.currentIndex = max(0, min(startAt, cleaned.count - 1))
        self.bookTitle  = title
        self.bookAuthor = author
        self.isLibraryMode = false
        self.selectedLocalBookPath = nil
        stop()
    }

    func play() {
        guard hasContent else { return }
        isPlaying = true
        triggerHaptics()
        startTimingLoop()
    }

    func pause() {
        isPlaying = false
        triggerHaptics()
        timingTask?.cancel()
        timingTask = nil
        persistLocalProgress()
    }

    func stop()  { pause() }

    func togglePlayPause() { isPlaying ? pause() : play() }
    
    func skipBack() {
        currentIndex = max(0, currentIndex - 15)
        triggerHaptics()
        persistLocalProgress()
        if isPlaying { reschedule() }
    }
    
    func skipForward() {
        currentIndex = min(words.count - 1, currentIndex + 15)
        triggerHaptics()
        persistLocalProgress()
        if isPlaying { reschedule() }
    }
    
    func increaseWPM() { wpm = min(800, wpm + 25) }
    func decreaseWPM() { wpm = max(60,  wpm - 25) }
    
    func seekTo(_ fraction: Double) {
        let targetIndex = Int(Double(words.count - 1) * min(max(fraction, 0.0), 1.0))
        if currentIndex != targetIndex {
            currentIndex = targetIndex
            persistLocalProgress()
            // Only perform light haptics while dragging to avoid spamming system haptic queue
            if targetIndex % 20 == 0 {
                triggerHaptics(.alignment)
            }
        }
    }

    private func startTimingLoop() {
        timingTask?.cancel()
        timingTask = Task { @MainActor in
            while isPlaying && currentIndex < words.count {
                let word = words[currentIndex]
                let delay = intervalFor(word)
                
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    // Task was cancelled
                    break
                }
                
                guard isPlaying && !Task.isCancelled else { break }
                
                currentIndex += 1
                
                // Periodically save progress while reading (every 10 words)
                if currentIndex % 10 == 0 {
                    persistLocalProgress()
                }
            }
            if currentIndex >= words.count {
                pause()
            }
        }
    }

    private func pacingCharFor(_ w: String) -> Character? {
        let trimmed = w.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip trailing quotes/brackets/braces/parentheses/double quotes first to find actual punctuation
        let quoteChars = "\"'`)]}>»”’"
        var endIdx = trimmed.endIndex
        while endIdx > trimmed.startIndex {
            let prevIdx = trimmed.index(before: endIdx)
            let char = trimmed[prevIdx]
            if quoteChars.contains(char) {
                endIdx = prevIdx
            } else {
                break
            }
        }
        guard endIdx > trimmed.startIndex else { return nil }
        let prevIdx = trimmed.index(before: endIdx)
        return trimmed[prevIdx]
    }

    private func intervalFor(_ w: String) -> Double {
        let base = 60.0 / wpm
        
        // Word-length multiplier: longer words need more processing time.
        // Research on RSVP reading comprehension shows optimal display duration
        // scales with word length (Rayner, 1998; Brysbaert, 2019).
        let alphaCount = Double(w.filter { $0.isLetter || $0.isNumber }.count)
        let lengthMultiplier: Double
        switch alphaCount {
        case 1:       lengthMultiplier = 0.6
        case 2...3:   lengthMultiplier = 0.85
        case 4...7:   lengthMultiplier = 1.0
        case 8...11:  lengthMultiplier = 1.25
        default:      lengthMultiplier = 1.5
        }
        
        guard smartPacing else { return base * lengthMultiplier }
        
        let punctuationMultiplier: Double
        if let lastChar = pacingCharFor(w) {
            switch lastChar {
            case ".", "!", "?": punctuationMultiplier = punctuationPauseMultiplier
            case ",", ";", ":": punctuationMultiplier = min(1.6, punctuationPauseMultiplier * 0.75)
            case "—", "–":     punctuationMultiplier = min(1.4, punctuationPauseMultiplier * 0.65)
            default:            punctuationMultiplier = 1.0
            }
        } else {
            punctuationMultiplier = 1.0
        }
        
        return base * lengthMultiplier * punctuationMultiplier
    }
    
    private func reschedule() {
        if isPlaying {
            startTimingLoop()
        }
    }

    // ── Standalone Local Folder Library Scanning & Persistence ──
    
    func scanFolder(at path: String) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }
        
        // Persist folder URL
        UserDefaults.standard.set(path, forKey: "com.focusreader.books.libraryFolder")
        
        self.isLoading = true
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let files = self.findEPUBFiles(in: path, maxDepth: 2)
            var scanned: [LocalBook] = []
            
            for file in files {
                let progressKey = "com.focusreader.books.progress:\(file)"
                let progressVal = UserDefaults.standard.double(forKey: progressKey)
                
                let chapters = EPUBParser.parseChapters(at: file)
                guard !chapters.isEmpty else { continue } // Ensure it's a valid parsed EPUB
                
                let title = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                
                scanned.append(LocalBook(
                    title: title,
                    author: "Local Library Book",
                    epubPath: file,
                    readingProgress: progressVal,
                    lastReadDate: Date()
                ))
            }
            
            let sortedBooks = scanned.sorted(by: { $0.lastReadDate > $1.lastReadDate })
            
            await MainActor.run {
                self.localLibrary = sortedBooks
                self.isLibraryMode = !sortedBooks.isEmpty
                self.isLoading = false
            }
        }
    }
    
    nonisolated private func findEPUBFiles(in dir: String, maxDepth: Int) -> [String] {
        guard maxDepth > 0,
              let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        var results: [String] = []
        for item in items {
            let full = "\(dir)/\(item)"
            if item.hasSuffix(".epub") {
                results.append(full)
            } else {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                    results += findEPUBFiles(in: full, maxDepth: maxDepth - 1)
                }
            }
        }
        return results
    }
    
    func persistLocalProgress() {
        guard let path = selectedLocalBookPath else { return }
        let progressVal = progress
        let progressKey = "com.focusreader.books.progress:\(path)"
        UserDefaults.standard.set(progressVal, forKey: progressKey)
        
        if let idx = localLibrary.firstIndex(where: { $0.epubPath == path }) {
            var book = localLibrary[idx]
            book.readingProgress = progressVal
            book.lastReadDate = Date()
            localLibrary[idx] = book
        }
    }
    
    func loadLocalBook(_ book: LocalBook) {
        self.selectedLocalBookPath = book.epubPath
        self.isLoading = true
        self.isLibraryMode = false
        
        let path = book.epubPath
        let progressVal = book.readingProgress
        let title = book.title
        let author = book.author
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let (words, startIdx, _) = EPUBParser.wordsFrom(epubPath: path, progress: progressVal)
            
            await MainActor.run {
                self.load(words: words, startAt: startIdx, title: title, author: author)
                self.isLoading = false
                self.play()
            }
        }
    }

    // ── Haptic Feedback Integration ──
    func triggerHaptics(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) {
        guard enableHaptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
    }
}
