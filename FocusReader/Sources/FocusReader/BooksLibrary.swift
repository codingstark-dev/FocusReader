import Foundation
import SQLite3

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
        // Determine OEBPS directory (standard EPUB layout)
        let oebpsPath = findOEBPSPath(at: epubPath)
        guard let oebpsPath else { return [] }

        // Read the OPF spine to get reading order
        guard let opfPath = findOPFPath(in: oebpsPath),
              let spineHrefs = parseSpine(opfPath: opfPath, oebpsBase: oebpsPath) else {
            return []
        }

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
        return chapters
    }

    /// Returns flat word list from entire book, starting at readingProgress offset.
    static func wordsFrom(epubPath: String, progress: Double) -> (words: [String], startIndex: Int, title: String) {
        let chapters = parseChapters(at: epubPath)
        let allWords = chapters.flatMap { $0.text.components(separatedBy: .whitespacesAndNewlines) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        let startIdx = max(0, Int(Double(allWords.count) * progress) - 5)
        let bookTitle = URL(fileURLWithPath: epubPath).deletingPathExtension().lastPathComponent
        return (allWords, startIdx, bookTitle)
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

        // Parse manifest: id → href
        var idToHref: [String: String] = [:]
        let manifestPattern = #"<item[^>]+id="([^"]+)"[^>]+href="([^"]+)"[^>]*/>"#
        let manifestRegex = try? NSRegularExpression(pattern: manifestPattern)
        let nsXml = xml as NSString
        manifestRegex?.enumerateMatches(in: xml, range: NSRange(xml.startIndex..., in: xml)) { m, _, _ in
            guard let m, m.numberOfRanges >= 3 else { return }
            let id   = nsXml.substring(with: m.range(at: 1))
            let href = nsXml.substring(with: m.range(at: 2))
            idToHref[id] = href
        }

        // Parse spine: ordered list of idrefs
        let spinePattern = #"<itemref[^>]+idref="([^"]+)""#
        let spineRegex = try? NSRegularExpression(pattern: spinePattern)
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
