import Foundation
import Security
import Darwin

actor UsageClient {
    private struct ClaudeCredentials: Decodable {
        struct OAuth: Decodable { let accessToken: String; let expiresAt: Double }
        let claudeAiOauth: OAuth
    }
    private struct CodexCredentials: Decodable {
        struct Tokens: Decodable { let access_token: String; let account_id: String }
        let tokens: Tokens
    }

    func fetch(_ provider: Provider) async throws -> UsageReading {
        var request: URLRequest
        switch provider {
        case .claude:
            var credentials = try readClaudeCredentials()
            if credentials.expiresAt / 1000 < Date().timeIntervalSince1970 + 60 {
                try await renewClaude()
                credentials = try readClaudeCredentials()
                guard credentials.expiresAt / 1000 > Date().timeIntervalSince1970 + 60 else {
                    throw UsageFailure(message: "Claude credentials are still expired after automatic renewal. \(provider.loginHelp)")
                }
            }
            request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("claude-code/2.0.32", forHTTPHeaderField: "User-Agent")
        case .codex:
            let credentials = try readCodexCredentials()
            request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            request.setValue("Bearer \(credentials.access_token)", forHTTPHeaderField: "Authorization")
            request.setValue(credentials.account_id, forHTTPHeaderField: "ChatGPT-Account-Id")
            request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        // An ephemeral session keeps credentials and usage out of disk caches.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 45
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw UsageFailure(message: "\(provider.name) request failed: \(error.localizedDescription)") }
        guard let response = response as? HTTPURLResponse else {
            throw UsageFailure(message: "\(provider.name) returned a non-HTTP response.")
        }
        guard response.statusCode == 200 else {
            let retry = response.value(forHTTPHeaderField: "Retry-After").map { " Retry after: \($0)." } ?? ""
            let login = [401, 403].contains(response.statusCode) ? " \(provider.loginHelp)" : ""
            throw UsageFailure(message: "\(provider.name) usage request returned HTTP \(response.statusCode).\(retry)\(login)")
        }
        return try UsageParser.parse(data, provider: provider)
    }

    private func readClaudeCredentials() throws -> ClaudeCredentials.OAuth {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
            throw UsageFailure(message: "Cannot read Claude Code credentials: \(reason). \(Provider.claude.loginHelp)")
        }
        guard let credentials = try? JSONDecoder().decode(ClaudeCredentials.self, from: data),
              !credentials.claudeAiOauth.accessToken.isEmpty else {
            throw UsageFailure(message: "Claude Keychain credentials have an unexpected format. \(Provider.claude.loginHelp)")
        }
        return credentials.claudeAiOauth
    }

    private func readCodexCredentials() throws -> CodexCredentials.Tokens {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        guard let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")),
              let credentials = try? JSONDecoder().decode(CodexCredentials.self, from: data),
              !credentials.tokens.access_token.isEmpty, !credentials.tokens.account_id.isEmpty else {
            throw UsageFailure(message: "Cannot read Codex ChatGPT credentials. \(Provider.codex.loginHelp)")
        }
        return credentials.tokens
    }

    private func renewClaude() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [home.appendingPathComponent(".local/bin/claude").path,
                          "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/claude" }
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw UsageFailure(message: "Claude credentials expired, but the claude CLI was not found in ~/.local/bin, Homebrew, or PATH. \(Provider.claude.loginHelp)")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-p", "ok", "--model", "haiku"]
        process.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(home.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch { throw UsageFailure(message: "Could not start Claude to renew credentials. \(Provider.claude.loginHelp)") }
        let deadline = Date().addingTimeInterval(60)
        while process.isRunning && Date() < deadline {
            try await Task.sleep(for: .milliseconds(250))
        }
        if process.isRunning {
            process.terminate()
            try await Task.sleep(for: .seconds(1))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw UsageFailure(message: "Claude login renewal timed out. \(Provider.claude.loginHelp)")
        }
        // Like the script, re-read credentials even if the prompt exited nonzero:
        // the CLI may have renewed OAuth before its inference request failed.
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
