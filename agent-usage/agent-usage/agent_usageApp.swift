import AppKit
import SwiftUI

@main
struct AgentUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [MenuBarController] = []
    private var panel: UsagePanelController?
    private let providers = ProviderSettings()
    private let login = LoginSettings()
    private var timer: Timer?
    private var nextRefresh = Date().addingTimeInterval(600)
    private var visibleControllers: [MenuBarController] { controllers.filter(\.isVisible) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let stores = Provider.allCases.map { ProviderStore(provider: $0) }
        let panel = UsagePanelController(stores: stores, providers: providers, login: login)
        self.panel = panel
        controllers = stores.map { MenuBarController(store: $0, panel: panel) }
        controllers.forEach { $0.isVisible = providers.isShown($0.store.provider) }
        visibleControllers.forEach { $0.store.refresh() }
        providers.onChange = { [weak self] in self?.applyProviderSettings() }
        scheduleRefresh()
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--diagnostics"),
           CommandLine.arguments.indices.contains(index + 1) {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            for controller in controllers {
                Task {
                    do {
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        try controller.writeDiagnostics(to: directory)
                        while controller.store.isRefreshing {
                            try await Task.sleep(for: .milliseconds(250))
                        }
                        try controller.writeDiagnostics(to: directory)
                    } catch { NSLog("Could not write prototype diagnostics: %@", error.localizedDescription) }
                }
            }
        }
        #endif
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func scheduleRefresh() {
        timer?.invalidate()
        let timer = Timer(fire: nextRefresh, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.visibleControllers.forEach { $0.store.refresh() }
                self.nextRefresh = Date().addingTimeInterval(600)
                self.scheduleRefresh()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func applyProviderSettings() {
        for controller in controllers {
            let shown = providers.isShown(controller.store.provider)
            // A provider shown again has skipped refreshes while hidden.
            if shown && !controller.isVisible { controller.store.refresh() }
            controller.isVisible = shown
        }
        panel?.reanchor(among: visibleControllers.compactMap(\.button))
    }
    @objc private func willSleep() { timer?.invalidate() }
    @objc private func didWake() {
        // Skip missed ticks instead of issuing an extra request on wake.
        while nextRefresh <= Date() { nextRefresh = nextRefresh.addingTimeInterval(600) }
        scheduleRefresh()
    }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
