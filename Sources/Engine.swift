import AppKit
import Combine
import CryptoKit
import Foundation

struct EngineError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

struct Release: Decodable {
    struct Asset: Decodable {
        let name: String
        let digest: String
        let browser_download_url: URL
    }
    let tag_name: String
    let assets: [Asset]

    static let repository = URL(string: "https://github.com/HuskerMinion/techo5")!
    static let endpoint = URL(string: "https://api.github.com/repos/HuskerMinion/techo5/releases/latest")!

    static func latest() async throws -> Release {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           http.statusCode == 429 || (http.statusCode == 403 && http.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0") {
            return try await latestFromReleasePage()
        }
        try check(response)
        return try JSONDecoder().decode(Release.self, from: data)
    }

    private static func latestFromReleasePage() async throws -> Release {
        let latestPage = repository.appending(path: "releases/latest")
        let (_, redirect) = try await URLSession.shared.data(for: URLRequest(url: latestPage, timeoutInterval: 30))
        try check(redirect)
        guard let tagPage = redirect.url, tagPage.host == repository.host,
              tagPage.path.hasPrefix(repository.path + "/releases/tag/"),
              tagPage.lastPathComponent.range(of: "^v[0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil else {
            throw EngineError("GitHub did not redirect to a versioned TECHO5 release.")
        }
        let tag = tagPage.lastPathComponent
        let assetsPage = repository.appending(path: "releases/expanded_assets").appending(component: tag)
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: assetsPage, timeoutInterval: 30))
        try check(response)
        let html = String(decoding: data, as: UTF8.self)
        let assets = ["arm64", "amd64"].compactMap { architecture -> Asset? in
            let name = "techo5-deck-macos-\(architecture)"
            let label = NSRegularExpression.escapedPattern(for: "Copy to clipboard digest for \(name)")
            let pattern = #"aria-label=""# + label + #""[^>]*value="(sha256:[0-9a-f]{64})""#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let digest = Range(match.range(at: 1), in: html) else { return nil }
            return Asset(name: name, digest: String(html[digest]), browser_download_url: downloadURL(tag: tag, name: name))
        }
        return Release(tag_name: tag, assets: assets)
    }

    private static func downloadURL(tag: String, name: String) -> URL {
        repository.appending(path: "releases/download").appending(component: tag).appending(component: name)
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw EngineError("GitHub returned HTTP \(code). Try again later.")
        }
    }

    static func digest(_ file: URL) throws -> String {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        return "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func engineAsset() throws -> Asset {
        var appleSilicon: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.optional.arm64", &appleSilicon, &size, nil, 0)
        let architecture = result == 0 && appleSilicon == 1 ? "arm64" : "amd64"
        let name = "techo5-deck-macos-\(architecture)"
        let expected = Self.downloadURL(tag: tag_name, name: name)
        guard let asset = assets.first(where: { $0.name == name }),
              asset.browser_download_url == expected,
              asset.digest.range(of: "^sha256:[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw EngineError("GitHub did not provide a verifiable \(name) asset.")
        }
        return asset
    }
}

@MainActor
final class Engine: ObservableObject {
    static let shared = Engine()

    @Published private(set) var running = false
    @Published private(set) var installed = false
    @Published private(set) var busy: String?
    @Published private(set) var message: String?
    @Published private(set) var key: String?
    @Published private(set) var version: String?

    private struct Receipt: Codable {
        let version: String
        let digest: String
    }

    private let files = FileManager.default
    private let port: Int
    private let settings: URL
    let directory: URL
    private var executable: URL { directory.appending(path: "techo5-deck") }
    private var receipt: URL { directory.appending(path: "release.json") }
    private var backup: URL { directory.appending(path: "previous-engine") }
    private var keyFile: URL { settings.appending(path: "key") }
    private var process: Process?
    private var bootstrapped = false

    var computerName: String { Host.current().localizedName ?? ProcessInfo.processInfo.hostName }

    init(settings: URL? = nil, port: Int = 4470) {
        self.port = port
        self.settings = settings ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "TECHO5 Deck", directoryHint: .isDirectory)
        directory = self.settings.appending(path: "Menu Bar Engine", directoryHint: .isDirectory)
        refresh()
    }

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        if files.fileExists(atPath: backup.path) {
            await perform("Recovering agent…") {
                try self.replace(self.backup, withDestination: self.executable)
                self.refresh()
                try await self.launch()
            }
        } else if installed {
            await start()
        } else {
            await update()
        }
    }

    func start() async { await perform("Starting agent…") { try await self.launch() } }
    func stop() async { await perform("Stopping agent…") { try await self.stopProcess() } }

    func restart() async {
        await perform("Restarting agent…") {
            try await self.stopProcess()
            try await self.launch()
        }
    }

    func regenerate() async {
        await perform("Generating pairing key…") {
            try await self.stopProcess()
            try await self.launch(newKey: true)
            self.message = "New key generated. Pair your Echo Show again."
        }
    }

    func update() async {
        await perform("Checking GitHub for agent updates…") {
            let release = try await Release.latest()
            let asset = try release.engineAsset()
            let expectedDigest = asset.digest
            if self.installed, try Release.digest(self.executable) == expectedDigest {
                try self.saveReceipt(release.tag_name, digest: expectedDigest)
                self.message = "Agent \(release.tag_name) is up to date."
                return
            }

            self.busy = "Downloading agent \(release.tag_name)…"
            let (download, response) = try await URLSession.shared.download(from: asset.browser_download_url)
            try Release.check(response)
            defer { try? self.files.removeItem(at: download) }
            let digest = try Release.digest(download)
            guard digest == expectedDigest else { throw EngineError("The agent download failed its SHA-256 check.") }

            try self.files.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let staged = self.directory.appending(path: UUID().uuidString)
            defer { try? self.files.removeItem(at: staged) }
            try self.files.copyItem(at: download, to: staged)
            try self.files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staged.path)

            self.busy = "Installing agent \(release.tag_name)…"
            try await self.install(staged, version: release.tag_name, digest: digest)
            self.message = "Agent \(release.tag_name) installed."
        }
    }

    private func install(_ staged: URL, version: String, digest: String) async throws {
        let wasRunning = running
        let hadEngine = installed
        guard !files.fileExists(atPath: backup.path) else {
            throw EngineError("A previous agent is awaiting recovery. Quit and reopen TECHO5 Deck.")
        }
        let oldReceipt = try? Data(contentsOf: receipt)
        try await stopProcess()
        var replaced = false
        do {
            if hadEngine {
                let backupStage = directory.appending(path: UUID().uuidString)
                defer { try? files.removeItem(at: backupStage) }
                try files.copyItem(at: executable, to: backupStage)
                try replace(backupStage, withDestination: backup)
            }
            try replace(staged, withDestination: executable)
            replaced = true
            try await launch()
            if hadEngine && !wasRunning { try await stopProcess() }
            try saveReceipt(version, digest: digest)
            if hadEngine { try files.removeItem(at: backup) }
        } catch {
            let updateError = error
            do {
                try await stopProcess()
                if replaced && hadEngine {
                    try replace(backup, withDestination: executable)
                } else if replaced {
                    try files.removeItem(at: executable)
                } else if files.fileExists(atPath: backup.path) {
                    try files.removeItem(at: backup)
                }
                if let oldReceipt {
                    try oldReceipt.write(to: receipt, options: .atomic)
                } else if files.fileExists(atPath: receipt.path) {
                    try files.removeItem(at: receipt)
                }
                if wasRunning { try await launch() }
            } catch {
                throw EngineError("Update failed. Recovery also failed: \(error.localizedDescription)")
            }
            throw EngineError("Agent installation failed. \(updateError.localizedDescription)")
        }
    }

    private func replace(_ source: URL, withDestination target: URL) throws {
        if rename(source.path, target.path) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private func saveReceipt(_ version: String, digest: String) throws {
        try JSONEncoder().encode(Receipt(version: version, digest: digest)).write(to: receipt, options: .atomic)
    }

    private func perform(_ label: String, _ work: () async throws -> Void) async {
        guard busy == nil else { return }
        busy = label
        message = nil
        defer {
            refresh()
            busy = nil
        }
        do { try await work() } catch { message = error.localizedDescription }
    }

    private func launch(newKey: Bool = false) async throws {
        guard process == nil else { return }
        guard files.isExecutableFile(atPath: executable.path) else {
            throw EngineError("Install the agent before starting it.")
        }
        let child = Process()
        child.executableURL = executable
        child.arguments = ["-dir", settings.path, "-port", String(port)] + (newKey ? ["-new-key"] : [])
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        child.terminationHandler = { [weak self] ended in
            Task { @MainActor in
                guard let self, self.process === ended else { return }
                self.process = nil
                self.running = false
                if self.busy == nil {
                    self.message = "Agent exited (\(ended.terminationStatus))."
                }
            }
        }
        try child.run()
        process = child
        try await Task.sleep(for: .seconds(2))
        guard child.isRunning else {
            throw EngineError("The agent exited during startup. Check whether another Deck agent is using port \(port).")
        }
        running = true
        refreshKey()
    }

    private func stopProcess() async throws {
        guard let child = process else { return }
        if child.isRunning { child.terminate() }
        for _ in 0..<30 {
            if !child.isRunning {
                process = nil
                running = false
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw EngineError("The agent did not stop. Its files were left in place.")
    }

    func quit() {
        process?.terminate()
    }

    private func refresh() {
        installed = files.isExecutableFile(atPath: executable.path)
        version = nil
        if installed, let data = try? Data(contentsOf: receipt),
           let info = try? JSONDecoder().decode(Receipt.self, from: data),
           (try? Release.digest(executable)) == info.digest {
            version = info.version
        }
        refreshKey()
    }

    private func refreshKey() {
        let value = (try? String(contentsOf: keyFile, encoding: .utf8))?
            .filter { !$0.isWhitespace && $0 != "-" }
        key = value?.range(of: "^[A-Za-z0-9]{32}$", options: .regularExpression) == nil ? nil : value
    }
}
