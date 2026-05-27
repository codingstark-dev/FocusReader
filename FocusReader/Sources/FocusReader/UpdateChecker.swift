import Foundation
import Combine
import AppKit

// MARK: - Update Checker
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published var latestVersion: String?
    @Published var updateAvailable: Bool = false
    @Published var downloadURL: String?
    @Published var releaseNotes: String?
    @Published var isChecking: Bool = false

    /// The GitHub repo in "owner/repo" format
    private let repo = "codingstark-dev/FocusReader"

    /// Current app version from the bundle or fallback
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.3"
    }

    private init() {}

    /// Check GitHub for the latest release
    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true

        let urlString = "https://api.github.com/repos/\(repo)/releases/latest"
        guard let url = URL(string: urlString) else {
            isChecking = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        Task.detached(priority: .utility) {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    await MainActor.run { self.isChecking = false }
                    return
                }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    await MainActor.run { self.isChecking = false }
                    return
                }

                let tagName = (json["tag_name"] as? String) ?? ""
                let remoteVersion = tagName.trimmingCharacters(in: CharacterSet.letters) // strip "v" prefix
                let notes = json["body"] as? String
                let htmlURL = json["html_url"] as? String

                // Find the DMG download URL from release assets
                var dmgURL: String? = htmlURL
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String,
                           name.hasSuffix(".dmg"),
                           let browserURL = asset["browser_download_url"] as? String {
                            dmgURL = browserURL
                            break
                        }
                    }
                }

                let finalDmgURL = dmgURL
                await MainActor.run {
                    self.latestVersion = remoteVersion
                    self.releaseNotes = notes
                    self.downloadURL = finalDmgURL
                    self.updateAvailable = self.isNewerVersion(remoteVersion, than: self.currentVersion)
                    self.isChecking = false
                }
            } catch {
                await MainActor.run {
                    self.isChecking = false
                }
            }
        }
    }

    /// Semantic version comparison: returns true if `remote` > `current`
    private func isNewerVersion(_ remote: String, than current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        let maxLen = max(remoteParts.count, currentParts.count)
        for i in 0..<maxLen {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }

    /// Open the download URL in the default browser
    func openDownloadPage() {
        guard let urlStr = downloadURL, let url = URL(string: urlStr) else { return }
        NSWorkspace.shared.open(url)
    }
}
