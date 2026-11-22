import AppKit
import ServiceManagement
import SwiftUI

@main
struct DeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var engine = Engine.shared

    var body: some Scene {
        MenuBarExtra("TECHO5 Deck", systemImage: engine.running ? "square.grid.3x3.fill" : "square.grid.3x3") {
            DeckMenu(engine: engine)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await Engine.shared.bootstrap() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Engine.shared.quit()
    }
}

@MainActor
private final class MenuState: ObservableObject {
    @Published var showingKey = false
    @Published var confirmingKey = false
    @Published var loginStatus = SMAppService.mainApp.status
    @Published var loginError: String?
    @Published var checkingAppUpdates = false
    @Published var appUpdateStatus: String?
}

struct DeckMenu: View {
    @ObservedObject var engine: Engine
    @StateObject private var menu = MenuState()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            pairingSection
            Divider()
            engineSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 356)
        .onAppear { menu.loginStatus = SMAppService.mainApp.status }
        .onDisappear { menu.showingKey = false }
        .alert("Generate a new pairing key?", isPresented: $menu.confirmingKey) {
            Button("Cancel", role: .cancel) {}
            Button("Generate Key", role: .destructive) {
                menu.showingKey = false
                Task { await engine.regenerate() }
            }
        } message: {
            Text("Every paired Echo Show will need to pair again.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("TECHO5 Deck").font(.headline)
                Text(engine.computerName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Label(status, systemImage: "circle.fill")
                .labelStyle(StatusLabelStyle(active: engine.running))
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Pairing Key").font(.subheadline.weight(.semibold))
                Spacer()
                if let key = engine.key {
                    Button(menu.showingKey ? "Hide" : "Show") { menu.showingKey.toggle() }
                        .accessibilityLabel(menu.showingKey ? "Hide Pairing Key" : "Show Pairing Key")
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(key, forType: .string)
                    }
                    .accessibilityLabel("Copy Pairing Key")
                }
                Menu {
                    Button("Generate New Key…") { menu.confirmingKey = true }
                        .disabled(engine.busy != nil || !engine.installed)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("Pairing Options")
                }
                .fixedSize()
                .help("Pairing Options")
            }
            if menu.showingKey, let key = engine.key {
                Text(key)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            } else if engine.key == nil {
                Text("Available after the engine starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Engine").font(.subheadline.weight(.semibold))
                    if let version = engine.version {
                        Text(version).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if engine.installed {
                    Button(engine.running ? "Stop" : "Start") {
                        Task { if engine.running { await engine.stop() } else { await engine.start() } }
                    }
                    .disabled(engine.busy != nil)
                    .accessibilityLabel(engine.running ? "Stop Engine" : "Start Engine")
                    Button("Restart") { Task { await engine.restart() } }
                        .disabled(engine.busy != nil || !engine.running)
                        .accessibilityLabel("Restart Engine")
                    Menu {
                        Button("Check for Engine Updates") { Task { await engine.update() } }
                            .disabled(engine.busy != nil)
                        Button("Show Engine Folder") { NSWorkspace.shared.open(engine.directory) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel("Engine Options")
                    }
                    .fixedSize()
                    .help("Engine Options")
                } else {
                    Button("Download Engine") { Task { await engine.update() } }
                        .disabled(engine.busy != nil)
                }
            }
            if let busy = engine.busy {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(busy)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let message = engine.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Menu("Settings") {
                    Toggle("Launch at Login", isOn: Binding(
                        get: { menu.loginStatus == .enabled || menu.loginStatus == .requiresApproval },
                        set: changeLogin
                    ))
                    if menu.loginStatus == .requiresApproval {
                        Button("Approve in Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                    Divider()
                    Button("Check for App Updates…") {
                        Task { await checkForAppUpdates() }
                    }
                    .disabled(menu.checkingAppUpdates)
                }
                .fixedSize()
                Menu("Help") {
                    Button("Open Accessibility Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Deck Setup and Permissions") {
                        NSWorkspace.shared.open(URL(string: "https://github.com/HuskerMinion/techo5/blob/main/docs/deck.md#macos")!)
                    }
                }
                .fixedSize()
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .disabled(engine.busy != nil)
                    .accessibilityLabel("Quit TECHO5 Deck")
            }
            if menu.loginStatus == .requiresApproval {
                Text("Launch at Login needs approval in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let loginError = menu.loginError {
                Text(loginError).font(.caption).foregroundStyle(.secondary)
            }
            if let status = menu.appUpdateStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var status: String {
        if engine.running { return "Running" }
        return engine.installed ? "Stopped" : "Engine Not Installed"
    }

    private func checkForAppUpdates() async {
        guard !menu.checkingAppUpdates else { return }
        menu.checkingAppUpdates = true
        menu.appUpdateStatus = "Checking for app updates…"
        defer { menu.checkingAppUpdates = false }

        do {
            guard let installed = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
                throw EngineError("Couldn’t determine the installed app version.")
            }

            let latest = try await AppRelease.latest()
            guard latest.version != installed else {
                menu.appUpdateStatus = "TECHO5 Deck \(installed) is up to date."
                return
            }

            let download = try await latest.verifiedDownloadURL()
            guard NSWorkspace.shared.open(download) else {
                throw EngineError("Couldn’t open the app download in your browser.")
            }
            menu.appUpdateStatus = "Opened the \(latest.version) download in your browser."
        } catch {
            menu.appUpdateStatus = "App update check failed. \(error.localizedDescription)"
        }
    }

    private func changeLogin(_ enabled: Bool) {
        menu.loginError = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { menu.loginError = error.localizedDescription }
        menu.loginStatus = SMAppService.mainApp.status
    }
}

private struct StatusLabelStyle: LabelStyle {
    let active: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .font(.system(size: 7))
                .foregroundStyle(active ? Color.green : Color.secondary)
            configuration.title
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct AppRelease {
    private static let repository = URL(string: "https://github.com/aptonline/Techo5-Deck-Menu")!

    let tag: String
    var version: String { tag.hasPrefix("v") ? String(tag.dropFirst()) : tag }

    static func latest() async throws -> AppRelease {
        let url = repository.appending(path: "releases/latest")
        let response = try await head(url)
        let tagPrefix = repository.path + "/releases/tag/"
        guard response.statusCode == 200, let releaseURL = response.url,
              releaseURL.scheme == "https", releaseURL.host == repository.host,
              releaseURL.path == tagPrefix + releaseURL.lastPathComponent,
              releaseURL.lastPathComponent.range(of: #"^v?[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil else {
            throw EngineError("GitHub didn’t return a published app version.")
        }
        return AppRelease(tag: releaseURL.lastPathComponent)
    }

    func verifiedDownloadURL() async throws -> URL {
        let filename = "TECHO5-Deck-\(version)-macOS-universal.zip"
        let url = Self.repository.appending(path: "releases/download")
            .appending(component: tag).appending(component: filename)
        let response = try await Self.head(url)
        guard response.statusCode == 200 else {
            throw EngineError("GitHub didn’t provide the Mac app ZIP for release \(tag) (HTTP \(response.statusCode)).")
        }
        return url
    }

    private static func head(_ url: URL) async throws -> HTTPURLResponse {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw EngineError("GitHub returned an invalid response.")
        }
        return http
    }
}
