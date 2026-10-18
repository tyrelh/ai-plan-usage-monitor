import AppKit
import Observation
import ServiceManagement

@MainActor @Observable
final class ProviderStore {
    let provider: Provider
    private(set) var reading: UsageReading?
    private(set) var error: String?
    private(set) var isRefreshing = false
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let client = UsageClient()

    init(provider: Provider) { self.provider = provider }
    var windows: [UsageWindow] { reading?.windows ?? [.unavailable, .unavailable] }
    var marker: String { error != nil ? "!" : (reading == nil ? "…" : "") }
    var status: String {
        if isRefreshing { return "Refreshing…" }
        if error != nil { return reading == nil ? "Unavailable" : "Stale · showing last successful reading" }
        return reading == nil ? "Waiting for first reading" : "Updated successfully"
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        onChange?()
        Task {
            do {
                reading = try await client.fetch(provider)
                error = nil
            } catch { self.error = error.localizedDescription }
            isRefreshing = false
            onChange?()
        }
    }
}

@MainActor @Observable
final class LoginSettings {
    private(set) var enabled = false
    private(set) var needsApproval = false
    private(set) var error: String?

    init() { reload() }
    func reload() {
        let status = SMAppService.mainApp.status
        enabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }
    func setEnabled(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch { self.error = "Could not change launch at login: \(error.localizedDescription)" }
        reload()
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
