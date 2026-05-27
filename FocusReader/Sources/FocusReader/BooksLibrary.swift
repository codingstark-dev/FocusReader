import Foundation
import SQLite3
import CryptoKit

// MARK: - BooksLibrary
/// Reads the BKLibrary SQLite database that Books maintains.
/// No Accessibility permission required — this is the actual Books data on disk.
struct BooksLibrary {

    struct BookEntry {
        let title:           String
        let author:          String
        let epubPath:        String
        let readingProgress: Double   // 0.0 – 1.0
        let lastOpenDate:    Date?
    }

    static let dbPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Containers/com.apple.iBooksX/Data/Documents/BKLibrary/BKLibrary-1-091020131601.sqlite"
    }()

    /// Returns all books with local EPUB files, sorted by most recently opened.
    static func allBooks() -> [BookEntry] {
        var db: OpaquePointer?
        // Open read-only to avoid corrupting Books' data
        guard sqlite3_open_v2(dbPath, &db,
                              SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let db else { return [] }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT ZTITLE, ZAUTHOR, ZPATH, ZREADINGPROGRESS, ZLASTOPENDATE
            FROM ZBKLIBRARYASSET
            WHERE ZPATH IS NOT NULL AND ZPATH != ''
            ORDER BY ZLASTOPENDATE DESC
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        var entries: [BookEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func text(_ col: Int32) -> String {
                guard let ptr = sqlite3_column_text(stmt, col) else { return "" }
                return String(cString: ptr)
            }
            let title    = text(0)
            let author   = text(1)
            let path     = text(2)
            let progress = sqlite3_column_double(stmt, 3)
            // Books stores dates as Apple epoch (seconds since 2001-01-01)
            let rawDate  = sqlite3_column_double(stmt, 4)
            let date     = rawDate > 0 ? Date(timeIntervalSinceReferenceDate: rawDate) : nil

            // Only include books where the EPUB path actually exists
            if FileManager.default.fileExists(atPath: path) {
                entries.append(BookEntry(title: title, author: author,
                                         epubPath: path, readingProgress: progress,
                                         lastOpenDate: date))
            }
        }
        return entries
    }

    /// Returns the most recently opened book.
    static func mostRecentBook() -> BookEntry? {
        allBooks().first
    }
}

// MARK: - EPUB Parser
/// Reads EPUB files directly from the BKAgentService storage.
/// EPUBs are stored as unzipped folders (Books extracts them internally).
struct EPUBParser {

    struct Chapter {
        let title: String
        let text:  String
        let wordCount: Int
    }

    /// Parses all chapters from an EPUB path.
    static func parseChapters(at epubPath: String) -> [Chapter] {
        let resolvedPath = getExtractedPath(for: epubPath)
        print("📖 FocusReader: Parsing chapters at resolved path: \(resolvedPath)")
        
        // Determine OEBPS directory (standard EPUB layout)
        let oebpsPath = findOEBPSPath(at: resolvedPath)
        guard let oebpsPath else {
            print("⚠️ FocusReader: findOEBPSPath returned nil for \(resolvedPath)")
            return []
        }
        print("📂 FocusReader: Found OEBPS path: \(oebpsPath)")

        // Read the OPF spine to get reading order
        guard let opfPath = findOPFPath(in: oebpsPath) else {
            print("⚠️ FocusReader: findOPFPath returned nil in \(oebpsPath)")
            return []
        }
        print("📄 FocusReader: Found OPF path: \(opfPath)")
        
        guard let spineHrefs = parseSpine(opfPath: opfPath, oebpsBase: oebpsPath) else {
            print("⚠️ FocusReader: parseSpine returned nil for OPF \(opfPath)")
            return []
        }
        print("🔗 FocusReader: Found \(spineHrefs.count) spine items")

        var chapters: [Chapter] = []
        for href in spineHrefs {
            let text = extractText(fromXHTML: href)
            if text.count > 50 { // Skip tiny/nav files
                let words = text.split(separator: " ").count
                let titleFromPath = URL(fileURLWithPath: href).deletingPathExtension().lastPathComponent
                    .replacingOccurrences(of: "_", with: " ")
                chapters.append(Chapter(title: titleFromPath, text: text, wordCount: words))
            }
        }
        print("📚 FocusReader: Successfully parsed \(chapters.count) chapters from \(epubPath)")
        return chapters
    }

    /// Returns flat word list from entire book, starting at readingProgress offset.
    static func wordsFrom(epubPath: String, progress: Double) -> (words: [String], startIndex: Int, title: String) {
        let resolvedPath = getExtractedPath(for: epubPath)
        let chapters = parseChapters(at: resolvedPath)
        let allWords = chapters.flatMap { $0.text.components(separatedBy: .whitespacesAndNewlines) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        let startIdx = max(0, Int(Double(allWords.count) * progress) - 5)
        let bookTitle = URL(fileURLWithPath: resolvedPath).deletingPathExtension().lastPathComponent
        let metadata = parseMetadata(at: epubPath)
        let title = metadata.title ?? bookTitle.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return (allWords, startIdx, title)
    }

    /// Parses metadata (title and author) from an EPUB.
    static func parseMetadata(at epubPath: String) -> (title: String?, author: String?) {
        let resolvedPath = getExtractedPath(for: epubPath)
        guard let oebpsPath = findOEBPSPath(at: resolvedPath),
              let opfPath = findOPFPath(in: oebpsPath) else {
            return (nil, nil)
        }
        
        guard let data = FileManager.default.contents(atPath: opfPath),
              let xml = String(data: data, encoding: .utf8) else {
            return (nil, nil)
        }
        
        let titlePattern = #"<dc:title[^>]*>([^<]+)</dc:title>"#
        let authorPattern = #"<dc:creator[^>]*>([^<]+)</dc:creator>"#
        
        func extract(pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)) else {
                return nil
            }
            if let range = Range(match.range(at: 1), in: xml) {
                return String(xml[range])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .replacingOccurrences(of: "&apos;", with: "'")
            }
            return nil
        }
        
        let title = extract(pattern: titlePattern)
        let author = extract(pattern: authorPattern)
        return (title, author)
    }

    private static func getExtractedPath(for epubPath: String) -> String {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: epubPath, isDirectory: &isDir) {
            if isDir.boolValue {
                print("ℹ️ FocusReader: EPUB path is already a directory: \(epubPath)")
                return epubPath
            }
        }
        
        // It's a file, unzip it to Caches directory
        let fileURL = URL(fileURLWithPath: epubPath)
        guard let cachesURL = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            print("⚠️ FocusReader: Caches directory not found, using raw path")
            return epubPath
        }
        let baseExtractionURL = cachesURL.appendingPathComponent("com.focusreader.books/ExtractedEPUBs")
        
        // Clean folder name from path hash to avoid collision (use stable SHA256 of path)
        let pathData = Data(epubPath.utf8)
        let hashed = SHA256.hash(data: pathData)
        let hashString = hashed.compactMap { String(format: "%02x", $0) }.joined()
        let folderName = "\(fileURL.deletingPathExtension().lastPathComponent)_\(hashString)"
        let extractionURL = baseExtractionURL.appendingPathComponent(folderName)
        let extractionPath = extractionURL.path
        
        // Check if already extracted
        if fm.fileExists(atPath: extractionPath) {
            print("ℹ️ FocusReader: EPUB already unzipped at: \(extractionPath)")
            return extractionPath
        }
        
        print("📦 FocusReader: Unzipping EPUB \(epubPath) to \(extractionPath)...")
        // Create directory
        try? fm.createDirectory(at: extractionURL, withIntermediateDirectories: true, attributes: nil)
        
        // Run unzip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", epubPath, "-d", extractionPath]
        
        do {
            try process.run()
            process.waitUntilExit()
            print("📦 FocusReader: Unzip process finished with status \(process.terminationStatus)")
            if process.terminationStatus == 0 {
                return extractionPath
            }
        } catch {
            print("❌ FocusReader: Failed to unzip EPUB at \(epubPath): \(error)")
        }
        
        return epubPath // fallback
    }

    // MARK: - Private Helpers

    private static func findOEBPSPath(at epubPath: String) -> String? {
        let candidates = ["OEBPS", "OPS", "content", "epub", ""]
        for c in candidates {
            let p = c.isEmpty ? epubPath : "\(epubPath)/\(c)"
            if FileManager.default.fileExists(atPath: p + "/") ||
               (c.isEmpty && FileManager.default.fileExists(atPath: p)) {
                // Check for OPF inside
                if findOPFPath(in: p) != nil { return p }
            }
        }
        // Search recursively for .opf file up to depth 3
        return findByExtension(".opf", in: epubPath, maxDepth: 3)
            .first.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
    }

    private static func findOPFPath(in dir: String) -> String? {
        // Check container.xml first
        let containerPath = "\(URL(fileURLWithPath: dir).deletingLastPathComponent().path)/META-INF/container.xml"
        if let data = FileManager.default.contents(atPath: containerPath),
           let xml = String(data: data, encoding: .utf8),
           let range = xml.range(of: #"full-path="([^"]+\.opf)"#, options: .regularExpression),
           let pathRange = xml[range].range(of: #"(?<=full-path=")[^"]+"#, options: .regularExpression) {
            let relativePath = String(xml[range][pathRange])
            let basePath = URL(fileURLWithPath: dir).deletingLastPathComponent().path
            return "\(basePath)/\(relativePath)"
        }
        // Fallback: find any .opf file
        return findByExtension(".opf", in: dir, maxDepth: 2).first
    }

    private static func parseSpine(opfPath: String, oebpsBase: String) -> [String]? {
        guard let data = FileManager.default.contents(atPath: opfPath),
              let xml = String(data: data, encoding: .utf8) else { return nil }

        // Parse manifest: id → href (supporting any attribute order and quotes)
        var idToHref: [String: String] = [:]
        
        let itemRegex = try? NSRegularExpression(pattern: #"<item\s+([^>]+)/?>"#, options: [.caseInsensitive])
        let idRegex = try? NSRegularExpression(pattern: #"\bid\s*=\s*['"]([^'"]+)['"]"#, options: [.caseInsensitive])
        let hrefRegex = try? NSRegularExpression(pattern: #"\bhref\s*=\s*['"]([^'"]+)['"]"#, options: [.caseInsensitive])
        
        let nsXml = xml as NSString
        itemRegex?.enumerateMatches(in: xml, range: NSRange(xml.startIndex..., in: xml)) { match, _, _ in
            guard let match = match else { return }
            let itemContent = nsXml.substring(with: match.range(at: 1))
            
            let itemRange = NSRange(itemContent.startIndex..., in: itemContent)
            
            var matchedId: String? = nil
            if let idMatch = idRegex?.firstMatch(in: itemContent, range: itemRange) {
                if let r = Range(idMatch.range(at: 1), in: itemContent) {
                    matchedId = String(itemContent[r])
                }
            }
            
            var matchedHref: String? = nil
            if let hrefMatch = hrefRegex?.firstMatch(in: itemContent, range: itemRange) {
                if let r = Range(hrefMatch.range(at: 1), in: itemContent) {
                    matchedHref = String(itemContent[r])
                }
            }
            
            if let id = matchedId, let href = matchedHref {
                idToHref[id] = href
            }
        }

        // Parse spine: ordered list of idrefs
        let spineRegex = try? NSRegularExpression(pattern: #"\bidref\s*=\s*['"]([^'"]+)['"]"#, options: [.caseInsensitive])
        var hrefs: [String] = []
        spineRegex?.enumerateMatches(in: xml, range: NSRange(xml.startIndex..., in: xml)) { m, _, _ in
            guard let m, m.numberOfRanges >= 2 else { return }
            let idref = nsXml.substring(with: m.range(at: 1))
            if let href = idToHref[idref] {
                let fullPath = "\(oebpsBase)/\(href)"
                hrefs.append(fullPath)
            }
        }
        return hrefs.isEmpty ? nil : hrefs
    }

    private static func extractText(fromXHTML path: String) -> String {
        guard let data = FileManager.default.contents(atPath: path),
              let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return ""
        }
        // Strip all HTML tags, decode entities
        var text = raw
        // Remove script/style blocks
        text = text.replacingOccurrences(of: #"<(script|style)[^>]*>[\s\S]*?</\1>"#,
                                         with: " ", options: .regularExpression)
        // Remove all remaining tags
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        // Decode common HTML entities
        text = text
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#8217;", with: "'")
            .replacingOccurrences(of: "&#8220;", with: "\"")
            .replacingOccurrences(of: "&#8221;", with: "\"")
            .replacingOccurrences(of: "&#8212;", with: "—")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
        // Collapse whitespace
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func findByExtension(_ ext: String, in dir: String, maxDepth: Int) -> [String] {
        guard maxDepth > 0,
              let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        var results: [String] = []
        for item in items {
            let full = "\(dir)/\(item)"
            if item.hasSuffix(ext) {
                results.append(full)
            } else {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                    results += findByExtension(ext, in: full, maxDepth: maxDepth - 1)
                }
            }
        }
        return results
    }
}
