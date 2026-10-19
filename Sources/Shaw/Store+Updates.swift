import AppKit

/// Check for Updates: compares this copy of Shaw with the latest release on GitHub.
extension Store {
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/sshane/shaw/releases/latest")!

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    /// Whether a release tag ("v0.2.0") is a newer version than `current` ("0.1.0").
    static func isNewer(_ tag: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(tag), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
    }

    func checkForUpdates() {
        var request = URLRequest(url: Store.latestReleaseAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let release = data.flatMap { try? JSONDecoder().decode(Release.self, from: $0) }
            DispatchQueue.main.async { self.showUpdate(release) }
        }.resume()
    }

    private func showUpdate(_ release: Release?) {
        let current = Store.appVersion
        guard let release else {
            showAlert("Couldn't check for updates", "Shaw couldn't reach GitHub. Check your internet connection and try again.")
            return
        }
        guard Store.isNewer(release.tag_name, than: current) else {
            showAlert("Shaw is up to date", "You have the newest version, \(current).")
            return
        }
        let version = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let a = NSAlert()
        a.messageText = "Shaw \(version) is available"
        var notes = (release.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.count > 600 { notes = String(notes.prefix(600)) + "…" }
        a.informativeText = "You have \(current). Download the new version from GitHub, then replace the Shaw in your Applications folder."
            + (notes.isEmpty ? "" : "\n\n" + notes)
        a.addButton(withTitle: "Download")
        a.addButton(withTitle: "Later")
        if a.runModal() == .alertFirstButtonReturn, let url = URL(string: release.html_url) {
            NSWorkspace.shared.open(url)
        }
    }
}
