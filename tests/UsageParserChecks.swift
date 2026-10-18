import Foundation

@main
struct UsageParserChecks {
    static func parse(_ json: String, _ provider: Provider) throws -> UsageReading {
        try UsageParser.parse(Data(json.utf8), provider: provider)
    }
    static func rejects(_ json: String, _ provider: Provider) {
        do { _ = try parse(json, provider); fatalError("Accepted malformed \(provider) response") }
        catch {}
    }
    static func main() throws {
        let claude = try parse(#"{"five_hour":{"utilization":50.9,"resets_at":"2026-10-18T19:00:00.123+00:00"},"seven_day":{"utilization":0,"resets_at":"2026-10-22T19:00:00Z"},"extra_usage":{"is_enabled":true,"used_credits":12,"monthly_limit":100,"currency":"USD"}}"#, .claude)
        precondition(claude.windows.map(\.label) == ["5h", "7d"])
        precondition(claude.windows[0].percent == "50%")
        precondition(claude.windows[1].utilization == 0)
        precondition(claude.windows.allSatisfy { $0.resetsAt != nil })
        precondition(claude.extra?.usedCredits == 12)
        let missing = try parse(#"{"five_hour":null,"seven_day":{"resets_at":null}}"#, .claude)
        precondition(missing.windows.allSatisfy { $0.utilization == nil && $0.percent == "—" })
        let omitted = try parse(#"{"five_hour":{"utilization":10}}"#, .claude)
        precondition(omitted.windows[1].utilization == nil)
        let codex = try parse(#"{"rate_limit":{"primary_window":{"limit_window_seconds":604800,"used_percent":76,"reset_at":1792695600},"secondary_window":{"limit_window_seconds":10800,"used_percent":25,"reset_at":1792346400}}}"#, .codex)
        precondition(codex.windows.map(\.label) == ["3h", "7d"])
        precondition(codex.windows[1].utilization == 76)
        let one = try parse(#"{"rate_limit":{"primary_window":{"limit_window_seconds":5400,"used_percent":0}}}"#, .codex)
        precondition(one.windows[0].label == "90m")
        precondition(one.windows[0].percent == "0%" && one.windows[1].percent == "—")
        rejects(#"{"error":"unauthorized"}"#, .claude)
        rejects(#"{"rate_limit":null}"#, .codex)
        rejects(#"{"five_hour":{"utilization":"50"},"seven_day":null}"#, .claude)
        rejects(#"{"five_hour":{"utilization":-1},"seven_day":null}"#, .claude)
        rejects(#"{"five_hour":{"utilization":101},"seven_day":null}"#, .claude)
        rejects(#"{"five_hour":{"resets_at":"tomorrow"},"seven_day":null}"#, .claude)
        rejects(#"{"rate_limit":{"primary_window":{"used_percent":12}}}"#, .codex)
        print("Usage parsing checks passed: percentages, dates, credits, changed durations, missing windows, malformed responses.")
    }
}
