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
    @Published var appUpdatesURL = UserDefaults.standard.string(forKey: "AppUpdatesURL").flatMap { URL(string: $0) }
    @Published var appUpdateError: String?
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
                        if let url = menu.appUpdatesURL {
                            openAppUpdates(url)
                        } else {
                            editAppUpdatesURL(openAfterSaving: true)
                        }
                    }
                    if menu.appUpdatesURL != nil {
                        Button("Change App Updates URL…") { editAppUpdatesURL(openAfterSaving: false) }
                    }
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
            if let error = menu.appUpdateError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var status: String {
        if engine.running { return "Running" }
        return engine.installed ? "Stopped" : "Engine Not Installed"
    }

    private func editAppUpdatesURL(openAfterSaving: Bool) {
        menu.appUpdateError = nil
        let alert = NSAlert()
        alert.messageText = "App Updates URL"
        alert.informativeText = "Enter the HTTPS address where you download new versions of the TECHO5 Deck menu bar app."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://"
        field.stringValue = menu.appUpdatesURL?.absoluteString ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.addButton(withTitle: openAfterSaving ? "Save and Open" : "Save")
        alert.addButton(withTitle: "Cancel")

        while alert.runModal() == .alertFirstButtonReturn {
            let address = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parts = URLComponents(string: address),
                  parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
                  parts.user == nil, parts.password == nil, let url = parts.url else {
                alert.informativeText = "Enter a valid HTTPS address for the app’s release page."
                continue
            }
            // Store a string so UserDefaults preserves the full web URL.
            UserDefaults.standard.set(url.absoluteString, forKey: "AppUpdatesURL")
            menu.appUpdatesURL = url
            if openAfterSaving { openAppUpdates(url) }
            return
        }
    }

    private func openAppUpdates(_ url: URL) {
        menu.appUpdateError = NSWorkspace.shared.open(url) ? nil : "Couldn’t open the app updates page."
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
