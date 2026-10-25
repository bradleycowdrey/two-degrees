import Foundation
import AppKit
import CryptoKit

/// Checks GitHub Releases for a newer Two Degrees and installs it in place.
///
/// Flow: fetch the latest release → compare versions → download the versioned DMG →
/// verify its SHA-256 against the published .sha256 → mount, copy the app out, unmount →
/// quit, swap the app bundle, relaunch (done by a tiny shell helper once we've exited).
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum Phase: Equatable {
        case idle, checking, upToDate, available, downloading, installing
        case failed(String)
    }

    struct Release: Equatable {
        let version: String
        let notes: String
        let dmg: URL
        let sha256: URL?
        let page: URL
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var latest: Release?
    @Published private(set) var lastChecked: Date?
    /// Short status shown inline in the panel (never a modal alert: a menu bar app's panel
    /// floats above normal windows, so alerts end up hidden behind it).
    @Published private(set) var notice: Notice?
    /// True while a check the user asked for is running, so the panel can show "Checking…".
    @Published private(set) var userChecking = false

    struct Notice: Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }
    @Published var automatic: Bool { didSet { UserDefaults.standard.set(automatic, forKey: "updates.automatic") } }

    let currentVersion: String
    /// Swapped for a stubbed session in unit tests.
    var session: URLSession = .shared
    /// Set when the user asks while an automatic check is already running, so its result is shown.
    private var userWaiting = false
    private var timer: Timer?
    /// Automatic checks run once a day (manual checks any time).
    private static let interval: TimeInterval = 24 * 3600

    init(currentVersion: String? = nil) {
        self.currentVersion = currentVersion ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        automatic = UserDefaults.standard.object(forKey: "updates.automatic") as? Bool ?? true
        lastChecked = UserDefaults.standard.object(forKey: "updates.lastChecked") as? Date
    }

    /// Only a real, installed .app can update itself (not `swift run`).
    var canSelfUpdate: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var isBusy: Bool { phase == .checking || phase == .downloading || phase == .installing }

    func start() {
        guard canSelfUpdate, timer == nil else { return }
        // Once a day: at launch if the last check was over 24 hours ago, then whenever a day
        // has passed while running (checked every 30 minutes).
        Task { await checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkIfDue() }
        }
    }

    /// Checks if the last check is over a day old (also called whenever the panel opens).
    func checkIfDue() async {
        guard automatic else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.interval { return }
        await check(userInitiated: false)
    }

    // MARK: Check

    func check(userInitiated: Bool) async {
        if isBusy {
            // Never drop a request the user made: show "Checking…" and report this check's result,
            // or say an update is already on its way.
            guard userInitiated else { return }
            if phase == .checking {
                userChecking = true
                userWaiting = true
                notice = nil
            } else {
                post("An update is already being installed.")
            }
            return
        }
        let pending = latest
        phase = .checking
        if userInitiated { userChecking = true; notice = nil }
        defer { userChecking = false; userWaiting = false }
        do {
            // The API gives release notes and exact asset names, but it rate-limits unsigned
            // requests (60 an hour per network). If it refuses, read the version from the public
            // "latest release" redirect instead, which has no such limit.
            let release: Release
            do {
                release = try await fetchFromAPI()
            } catch {
                release = try await fetchFromLatestRedirect()
            }

            lastChecked = Date()
            UserDefaults.standard.set(lastChecked, forKey: "updates.lastChecked")

            let announce = userInitiated || userWaiting
            if Self.isNewer(release.version, than: currentVersion) {
                latest = release
                phase = .available
                // The panel's banner offers "Update"; nothing modal.
            } else {
                latest = nil
                phase = .upToDate
                if announce { post("You’re up to date. Two Degrees \(currentVersion) is the newest version.") }
            }
        } catch {
            // A failed re-check never hides an update that was already found.
            phase = pending != nil ? .available : .failed(error.localizedDescription)
            if userInitiated || userWaiting { post("Couldn’t check for updates. \(error.localizedDescription)", error: true) }
        }
    }

    private func fetchFromAPI() async throws -> Release {
        var request = URLRequest(url: Brand.releasesAPI, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TwoDegrees/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.status(status) }
        return try Self.parse(data)
    }

    /// github.com/<repo>/releases/latest redirects to …/releases/tag/v<version>; the release
    /// assets follow a fixed naming scheme (see .github/workflows/release.yml).
    private func fetchFromLatestRedirect() async throws -> Release {
        var request = URLRequest(url: Brand.repository.appendingPathComponent("releases/latest"), timeoutInterval: 20)
        request.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.server }
        guard http.statusCode == 200, let final = http.url else { throw UpdateError.status(http.statusCode) }
        return try Self.release(fromTagPage: final)
    }

    nonisolated static func release(fromTagPage page: URL) throws -> Release {
        let tag = page.lastPathComponent
        guard page.pathComponents.contains("tag"), tag.hasPrefix("v") else { throw UpdateError.noDownload }
        let version = String(tag.dropFirst())
        let dmg = Brand.repository.appendingPathComponent("releases/download/\(tag)/TwoDegrees-\(version).dmg")
        return Release(version: version, notes: "", dmg: dmg,
                       sha256: dmg.deletingLastPathComponent().appendingPathComponent(dmg.lastPathComponent + ".sha256"), page: page)
    }

    // MARK: Install

    func install() async {
        guard let release = latest, !isBusy else { return }
        let target = Bundle.main.bundleURL
        phase = .downloading
        do {
            let (staged, dmg, work) = try await stage(release) { self.phase = .installing }
            guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
                // Can't replace in place (e.g. read-only location): hand the DMG to Finder instead.
                NSWorkspace.shared.open(dmg)
                phase = .available
                post("Finish in Finder: drag the new Two Degrees into Applications, replacing the old one.")
                return
            }
            try relaunch(replacing: target, with: staged, scratch: work)
        } catch {
            phase = .failed(error.localizedDescription)
            post("Update failed. \(error.localizedDescription)", error: true)
        }
    }

    /// Download → verify SHA-256 (required) → unpack → confirm the version. Shared by install()
    /// and the self-test, so CI exercises the real path. Returns the staged app, the DMG and the
    /// scratch folder.
    func stage(_ release: Release, unpacking: () -> Void = {}) async throws -> (URL, URL, URL) {
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("TwoDegreesUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let (downloaded, response) = try await session.download(from: release.dmg)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.download }
        let dmg = work.appendingPathComponent("TwoDegrees.dmg")
        try FileManager.default.moveItem(at: downloaded, to: dmg)

        guard let checksumURL = release.sha256 else { throw UpdateError.noChecksum }
        let (checksum, checksumResponse) = try await session.data(from: checksumURL)
        guard (checksumResponse as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.noChecksum }
        let expected = Self.expectedChecksum(checksum)
        guard expected.count == 64, try Self.sha256(of: dmg) == expected else { throw UpdateError.checksum }

        unpacking()
        let staged = try await Self.extractApp(from: dmg, into: work)
        let stagedVersion = Bundle(url: staged)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard stagedVersion == release.version else { throw UpdateError.wrongVersion }
        return (staged, dmg, work)
    }

    /// The first word of a `shasum -a 256` line, lowercased.
    nonisolated static func expectedChecksum(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? ""
    }

    /// Hands off to a shell helper that waits for us to quit, swaps the bundle (rolling back on
    /// failure), clears quarantine and relaunches.
    private func relaunch(replacing target: URL, with staged: URL, scratch: URL) throws {
        let script = scratch.appendingPathComponent("install.sh")
        try Self.installScript.write(to: script, atomically: true, encoding: .utf8)
        // Spawn in a new session: launchd kills an app's whole process group when it quits,
        // which would take a plain child process (and the update) down with it.
        try Self.spawnDetached("/bin/sh", [script.path, String(ProcessInfo.processInfo.processIdentifier), target.path, staged.path])
        NSApp.terminate(nil)
    }

    nonisolated static let installScript = """
    #!/bin/sh
    # $1 = pid to wait for, $2 = installed app, $3 = staged new app
    PID="$1"; TARGET="$2"; NEW="$3"
    mkdir -p "$HOME/Library/Logs"
    exec >>"$HOME/Library/Logs/TwoDegrees-update.log" 2>&1
    echo "$(date) updating $TARGET from $NEW (waiting for pid $PID)"
    i=0
    while kill -0 "$PID" 2>/dev/null && [ $i -lt 300 ]; do sleep 0.1; i=$((i+1)); done
    rm -rf "$TARGET.old"
    if mv "$TARGET" "$TARGET.old"; then
      if /usr/bin/ditto "$NEW" "$TARGET"; then
        rm -rf "$TARGET.old"
      else
        rm -rf "$TARGET"; mv "$TARGET.old" "$TARGET"
      fi
    fi
    /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
    # Tell LaunchServices about the new version. Without this it keeps the old build number, and
    # macOS rejects the widget's content ("Bundle version did not match"), leaving it blank.
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TARGET"
    # End the widget process still running the old version's code (its network is cut once its app is
    # replaced, so its widgets stay grey). macOS starts the new version's widget when it's next needed.
    /usr/bin/pkill -x TwoDegreesWidget
    echo "$(date) relaunching"
    /usr/bin/open "$TARGET"
    """

    // MARK: Helpers

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let body: String?
        let html_url: URL
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]
    }

    nonisolated static func parse(_ data: Data) throws -> Release {
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        let versioned = release.assets.first { $0.name.hasPrefix("TwoDegrees-") && $0.name.hasSuffix(".dmg") }
        guard let dmg = versioned ?? release.assets.first(where: { $0.name == "TwoDegrees.dmg" }) else {
            throw UpdateError.noDownload
        }
        let checksum = release.assets.first { $0.name == dmg.name + ".sha256" }
        return Release(
            version: version,
            notes: release.body ?? "",
            dmg: dmg.browser_download_url,
            sha256: checksum?.browser_download_url,
            page: release.html_url
        )
    }

    /// Numeric dotted comparison; anything after "-" (e.g. "-dev") is ignored.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            let core = v.split(separator: "-").first.map(String.init) ?? v
            return core.split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func extractApp(from dmg: URL, into work: URL) async throws -> URL {
        let mount = work.appendingPathComponent("mount", isDirectory: true)
        let staged = work.appendingPathComponent("TwoDegrees.app", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try await run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, "-quiet"])
        defer {
            let detach = Process()
            detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detach.arguments = ["detach", mount.path, "-force", "-quiet"]
            try? detach.run()
        }
        let source = mount.appendingPathComponent("TwoDegrees.app")
        guard FileManager.default.fileExists(atPath: source.path) else { throw UpdateError.noApp }
        try await run("/usr/bin/ditto", [source.path, staged.path])
        return staged
    }

    /// posix_spawn with POSIX_SPAWN_SETSID (0x0400): the child gets its own session and process
    /// group, so it keeps running after Two Degrees exits.
    private static func spawnDetached(_ tool: String, _ arguments: [String]) throws {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(0x0400))
        let argv: [UnsafeMutablePointer<CChar>?] = ([tool] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, tool, nil, &attributes, argv, environ)
        guard status == 0 else { throw UpdateError.tool("posix_spawn", status) }
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.tool((tool as NSString).lastPathComponent, finished.terminationStatus))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    /// Shows a message in the panel. Confirmations fade after a few seconds; errors stay until dismissed.
    private func post(_ text: String, error: Bool = false) {
        let notice = Notice(text: text, isError: error)
        self.notice = notice
        guard !error else { return }
        Task {
            try? await Task.sleep(for: .seconds(6))
            if self.notice == notice { self.notice = nil }
        }
    }

    func dismissNotice() { notice = nil }

    // MARK: Self-test hooks (CI only)

    /// Runs the real download → checksum → unpack → version check for `latest`, without
    /// replacing or relaunching the app. Returns a one-line result for the report.
    func selfTestStage() async -> String {
        guard let release = latest else { return "no update to stage" }
        do {
            let (staged, _, _) = try await stage(release)
            let widget = FileManager.default.fileExists(atPath: staged.appendingPathComponent("Contents/PlugIns/TwoDegreesWidget.appex").path)
            return "PASS staged \(release.version) through the real install path: checksum OK, version matches, widget \(widget ? "present" : "MISSING")"
        } catch {
            return "FAIL \(error.localizedDescription)"
        }
    }

    /// Puts the banner into a given state so the self-test can photograph it.
    func selfTestShow(phase: Phase? = nil, notice text: String? = nil, error: Bool = false, clearLatest: Bool = false) {
        if clearLatest { latest = nil }
        if let phase { self.phase = phase }
        notice = text.map { Notice(text: $0, isError: error) }
    }

    /// Opens the release page in the browser as a manual fallback.
    func openReleasePage() {
        NSWorkspace.shared.open(latest?.page ?? Brand.repository.appendingPathComponent("releases/latest"))
    }
}

enum UpdateError: LocalizedError {
    case server, download, checksum, noDownload, noApp, wrongVersion
    case status(Int)
    case noChecksum
    case tool(String, Int32)

    var errorDescription: String? {
        switch self {
        case .server: return "GitHub didn’t respond. Check your internet connection and try again."
        case .status(let code): return "GitHub answered with an error (HTTP \(code)). Try again in a little while."
        case .download: return "The download didn’t finish."
        case .noChecksum: return "The release has no checksum to verify the download against, so it wasn’t installed."
        case .checksum: return "The download didn’t match its published checksum, so it wasn’t installed."
        case .noDownload: return "The latest release has no Mac download yet."
        case .noApp: return "The download didn’t contain Two Degrees."
        case .wrongVersion: return "The downloaded app isn’t the expected version."
        case .tool(let name, let status): return "\(name) failed (exit \(status))."
        }
    }
}
