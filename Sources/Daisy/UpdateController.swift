// Daisy — checks GitHub Releases for a newer Daisy, verifies the DMG and swaps the app in place.
import AppKit
import CryptoKit
import SwiftUI

struct AppRelease: Equatable {
    let version: String
    let notes: String
    let pageURL: URL
    let dmgURL: URL
    let dmgSize: Int
    /// Lowercase hex SHA-256 of the DMG.
    let sha256: String
}

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(AppRelease)
    case downloading(Double)
    case installing
    case failed(String)
}

enum AppVersion {
    /// Numeric components of "v1.2.3" / "1.2"; non-numeric suffixes are ignored.
    static func components(_ version: String) -> [Int] {
        let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return trimmed.split(separator: ".").map { part in
            Int(part.prefix(while: \.isNumber)) ?? 0
        }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate), b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

final class UpdateController: NSObject, ObservableObject {
    static let shared = UpdateController()

    static let repository = "kpostaagasi/daisy"
    static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let lastCheckKey = "lastUpdateCheck"
    private static let skippedVersionKey = "skippedUpdateVersion"

    @Published private(set) var state: UpdateState = .idle

    /// Returns true while conversions run; installing would kill them.
    var isBusy: () -> Bool = { false }

    private let settings = AppSettings.shared
    private var timer: Timer?
    private var window: NSPanel?
    private var session: URLSession?
    private var downloadTask: URLSessionDownloadTask?
    private var pendingRelease: AppRelease?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var lastCheck: Date? {
        UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
    }

    var availableRelease: AppRelease? {
        if case .available(let release) = state { return release }
        return nil
    }

    // MARK: Scheduling

    /// Checks shortly after launch and then hourly whenever the last check is a day old.
    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.checkIfDue()
        }
    }

    private func checkIfDue() {
        guard settings.automaticallyChecksForUpdates else { return }
        if let last = lastCheck, Date().timeIntervalSince(last) < Self.checkInterval { return }
        check(userInitiated: false)
    }

    // MARK: Checking

    func check(userInitiated: Bool) {
        switch state {
        case .checking, .downloading, .installing:
            if userInitiated { showWindow(activate: true) }
            return
        default:
            break
        }
        state = .checking
        if userInitiated { showWindow(activate: true) }

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Daisy/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let result = Self.parseRelease(data: data, response: response, error: error)
            DispatchQueue.main.async { self?.finishCheck(result, userInitiated: userInitiated) }
        }.resume()
    }

    private func finishCheck(_ result: Result<AppRelease, Error>, userInitiated: Bool) {
        switch result {
        case .failure(let error):
            state = .failed("Couldn’t check for updates: \(error.localizedDescription)")
            if !userInitiated { window?.close() }
        case .success(let release):
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            guard AppVersion.isNewer(release.version, than: currentVersion) else {
                state = .upToDate
                return
            }
            state = .available(release)
            let skipped = UserDefaults.standard.string(forKey: Self.skippedVersionKey)
            if userInitiated || skipped != release.version {
                showWindow(activate: userInitiated)
            }
        }
    }

    private static func parseRelease(data: Data?, response: URLResponse?, error: Error?) -> Result<AppRelease, Error> {
        if let error { return .failure(error) }
        guard let http = response as? HTTPURLResponse, let data else {
            return .failure(UpdateError("No response from GitHub."))
        }
        guard http.statusCode == 200 else {
            return .failure(UpdateError("GitHub returned HTTP \(http.statusCode)."))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]]
        else { return .failure(UpdateError("Unexpected release data.")) }

        let notes = json["body"] as? String ?? ""
        guard let dmg = assets.first(where: { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }),
              let urlString = dmg["browser_download_url"] as? String,
              let url = URL(string: urlString)
        else { return .failure(UpdateError("The latest release has no DMG.")) }

        // GitHub's asset digest; older releases only list the checksum in their notes.
        var sha = (dmg["digest"] as? String).flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }
        if sha == nil, let range = notes.range(of: #"SHA-256:\s*`?([0-9a-fA-F]{64})"#, options: .regularExpression) {
            sha = String(notes[range].suffix(64))
        }
        guard let sha, sha.count == 64 else {
            return .failure(UpdateError("The latest release has no SHA-256 checksum."))
        }

        return .success(AppRelease(
            version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
            notes: notes,
            pageURL: page,
            dmgURL: url,
            dmgSize: dmg["size"] as? Int ?? 0,
            sha256: sha.lowercased()
        ))
    }

    // MARK: User choices

    func skip(_ release: AppRelease) {
        UserDefaults.standard.set(release.version, forKey: Self.skippedVersionKey)
        window?.close()
    }

    func later() {
        window?.close()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        if let release = pendingRelease { state = .available(release) }
    }

    // MARK: Installing

    func install(_ release: AppRelease) {
        if isBusy() {
            state = .failed("Daisy is still converting files. Install the update when they finish.")
            return
        }
        let appURL = Bundle.main.bundleURL
        if appURL.path.contains("/AppTranslocation/") {
            state = .failed("macOS is running Daisy from a temporary location. Move Daisy to Applications, open it from there, then update.")
            return
        }
        let parent = appURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path),
              FileManager.default.isWritableFile(atPath: appURL.path)
        else {
            state = .failed("Daisy can’t replace itself in \(parent.path). Download the update from the release page instead.")
            return
        }

        pendingRelease = release
        state = .downloading(0)
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)
        self.session = session
        let task = session.downloadTask(with: release.dmgURL)
        downloadTask = task
        task.resume()
    }

    /// Verifies the downloaded DMG, stages the new app next to the current one and hands off to a swap script.
    private func installDownloaded(dmg: URL, release: AppRelease) {
        state = .installing
        let appURL = Bundle.main.bundleURL
        let expectedBundleID = Bundle.main.bundleIdentifier ?? ""

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Self.stage(dmg: dmg, release: release, over: appURL, bundleID: expectedBundleID)
            try? FileManager.default.removeItem(at: dmg.deletingLastPathComponent())
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let error):
                    self.state = .failed(error.localizedDescription)
                case .success(let staged):
                    do {
                        try Self.launchSwap(old: appURL, staged: staged)
                        NSApp.terminate(nil)
                    } catch {
                        try? FileManager.default.removeItem(at: staged)
                        self.state = .failed("Couldn’t start the installer: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private static func stage(dmg: URL, release: AppRelease, over appURL: URL, bundleID: String) -> Result<URL, Error> {
        guard let digest = sha256(of: dmg) else {
            return .failure(UpdateError("Couldn’t read the downloaded update."))
        }
        guard digest == release.sha256 else {
            return .failure(UpdateError("The downloaded update failed its SHA-256 check and was discarded."))
        }

        let mount = dmg.deletingLastPathComponent().appendingPathComponent("mount")
        let attach = ToolRunner.run("/usr/bin/hdiutil", arguments: [
            "attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path,
        ], timeout: 120)
        guard attach.succeeded else {
            return .failure(UpdateError("Couldn’t open the update disk image."))
        }
        defer { _ = ToolRunner.run("/usr/bin/hdiutil", arguments: ["detach", mount.path, "-force"], timeout: 60) }

        let contents = (try? FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)) ?? []
        guard let newApp = contents.first(where: { $0.pathExtension == "app" }),
              let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == bundleID,
              info["CFBundleShortVersionString"] as? String == release.version
        else {
            return .failure(UpdateError("The update disk image doesn’t contain Daisy \(release.version)."))
        }
        let verify = ToolRunner.run("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", newApp.path], timeout: 120)
        guard verify.succeeded else {
            return .failure(UpdateError("The update’s code signature is invalid."))
        }

        // Same volume as the installed app, so the swap is a rename.
        let staged = appURL.deletingLastPathComponent()
            .appendingPathComponent(".Daisy-update-\(UUID().uuidString).app")
        let copy = ToolRunner.run("/usr/bin/ditto", arguments: [newApp.path, staged.path], timeout: 300)
        guard copy.succeeded else {
            try? FileManager.default.removeItem(at: staged)
            return .failure(UpdateError("Couldn’t copy the update next to Daisy."))
        }
        return .success(staged)
    }

    /// Detached script: waits for Daisy to quit, swaps the bundles (restoring on failure) and relaunches.
    private static func launchSwap(old: URL, staged: URL) throws {
        let script = """
        pid="$1"; old="$2"; new="$3"; backup="$2.previous-$$"
        i=0
        while kill -0 "$pid" 2>/dev/null; do
          i=$((i + 1)); [ "$i" -gt 300 ] && { rm -rf "$new"; exit 1; }
          sleep 0.1
        done
        if mv "$old" "$backup"; then
          if mv "$new" "$old"; then rm -rf "$backup"; else mv "$backup" "$old"; rm -rf "$new"; fi
        else
          rm -rf "$new"
        fi
        open "$old"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "daisy-update",
                             String(ProcessInfo.processInfo.processIdentifier), old.path, staged.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Window

    func showWindow(activate: Bool) {
        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "Software Update"
            panel.titlebarAppearsTransparent = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentViewController = NSHostingController(rootView: UpdateView(controller: self))
            panel.center()
            window = panel
        }
        window?.orderFrontRegardless()
        if activate {
            window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

extension UpdateController: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard downloadTask == self.downloadTask else { return }
        let expected = totalBytesExpectedToWrite > 0
            ? totalBytesExpectedToWrite
            : Int64(pendingRelease?.dmgSize ?? 0)
        if expected > 0 { state = .downloading(min(1, Double(totalBytesWritten) / Double(expected))) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard downloadTask == self.downloadTask, let release = pendingRelease else { return }
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            state = .failed("Download failed: HTTP \(http.statusCode).")
            return
        }
        // The temporary file is deleted when this method returns; move it first.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("daisy-update-\(UUID().uuidString)")
        let dmg = workDir.appendingPathComponent("Daisy-\(release.version).dmg")
        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: dmg)
        } catch {
            state = .failed("Couldn’t save the update: \(error.localizedDescription)")
            return
        }
        self.downloadTask = nil
        installDownloaded(dmg: dmg, release: release)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        if self.session === session { self.session = nil }
        guard let error, task == downloadTask else { return }
        downloadTask = nil
        if (error as NSError).code == NSURLErrorCancelled { return }
        state = .failed("Download failed: \(error.localizedDescription)")
    }
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Update window

private let updateAccent = Color(nsColor: NSColor(srgbRed: 1.0, green: 0.36, blue: 0.05, alpha: 1.0))

struct UpdateView: View {
    @ObservedObject var controller: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            content
        }
        .padding(.horizontal, 20)
        .padding(.top, 34)
        .padding(.bottom, 18)
        .frame(width: 460)
    }

    private var title: String {
        switch controller.state {
        case .idle, .checking: return "Checking for updates…"
        case .upToDate: return "Daisy is up to date"
        case .available(let r): return "Daisy \(r.version) is available"
        case .downloading: return "Downloading update…"
        case .installing: return "Installing update…"
        case .failed: return "Update failed"
        }
    }

    private var subtitle: String {
        switch controller.state {
        case .available: return "You have \(controller.currentVersion). Daisy restarts after installing."
        case .upToDate: return "Version \(controller.currentVersion) is the latest release."
        case .failed(let message): return message
        case .installing: return "Verifying and replacing Daisy, then relaunching."
        default: return "Version \(controller.currentVersion)"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .idle, .checking:
            ProgressView().progressViewStyle(.linear)
            buttons { Button("Cancel") { controller.later() } }
        case .upToDate:
            buttons {
                Button("OK") { controller.later() }
                    .keyboardShortcut(.defaultAction)
            }
        case .available(let release):
            notes(release)
            HStack {
                Button("Skip This Version") { controller.skip(release) }
                Spacer()
                Button("Later") { controller.later() }
                    .keyboardShortcut(.cancelAction)
                Button("Install and Relaunch") { controller.install(release) }
                    .buttonStyle(.borderedProminent)
                    .tint(updateAccent)
                    .keyboardShortcut(.defaultAction)
            }
        case .downloading(let progress):
            ProgressView(value: progress).progressViewStyle(.linear).tint(updateAccent)
            buttons { Button("Cancel") { controller.cancelDownload() } }
        case .installing:
            ProgressView().progressViewStyle(.linear).tint(updateAccent)
        case .failed:
            buttons {
                Button("Open Releases Page") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/\(UpdateController.repository)/releases/latest")!)
                    controller.later()
                }
                Button("Close") { controller.later() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func notes(_ release: AppRelease) -> some View {
        ScrollView {
            Text(Self.renderNotes(release.notes))
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(10)
        }
        .frame(height: 170)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private func buttons<B: View>(@ViewBuilder _ content: () -> B) -> some View {
        HStack {
            Spacer()
            content()
        }
    }

    /// Release notes are Markdown: headings become bold lines, list markers become bullets,
    /// inline styles render, and the checksum line is dropped.
    static func renderNotes(_ markdown: String) -> AttributedString {
        let lines = markdown.components(separatedBy: .newlines).compactMap { raw -> String? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("SHA-256:") { return nil }
            if line.hasPrefix("#") {
                let heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                return heading.isEmpty ? "" : "**\(heading)**"
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                return "•  " + line.dropFirst(2)
            }
            return raw
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
