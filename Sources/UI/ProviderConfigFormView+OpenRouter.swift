import SwiftUI

// MARK: - OpenRouter Usage

extension ProviderConfigFormView {

    var openRouterUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API Usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(openRouterUsageStatusColor)
                        .frame(width: 8, height: 8)
                    Text(openRouterUsageStatusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let usage = openRouterUsage {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)

                    Text("Current key used \(formatUSD(usage.used)) (Remaining: \(usage.remainingText(formatter: formatUSD)))")
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(openRouterUsageStatusColor)
                        .frame(width: 8, height: 8)

                    Text(openRouterUsageHintText)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button {
                    Task { await refreshOpenRouterUsage(force: true) }
                } label: {
                    Label("Refresh Usage", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isOpenRouterUsageRefreshDisabled)

                if openRouterUsageStatus == .loading {
                    ProgressView()
                        .scaleEffect(0.5)
                }

                Spacer()
            }

            if case .failure(let message) = openRouterUsageStatus {
                Text(message)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - OpenRouter Usage Actions

    func scheduleOpenRouterUsageRefresh() {
        openRouterUsageTask?.cancel()
        openRouterUsageTask = Task {
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
            } catch {
                return
            }
            await refreshOpenRouterUsage(force: true)
        }
    }

    func refreshOpenRouterUsage(force: Bool) async {
        guard providerType == .openrouter else { return }

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            await MainActor.run {
                openRouterUsage = nil
                openRouterUsageStatus = .idle
            }
            return
        }

        if !force, openRouterUsageStatus == .loading {
            return
        }

        await MainActor.run {
            openRouterUsageStatus = .loading
        }

        do {
            let usage = try await fetchOpenRouterKeyUsage(apiKey: key)
            await MainActor.run {
                openRouterUsage = usage
                openRouterUsageStatus = .observed
            }
        } catch is CancellationError {
            return
        } catch {
            await MainActor.run {
                openRouterUsage = nil
                openRouterUsageStatus = .failure(error.localizedDescription)
            }
        }
    }

    func fetchOpenRouterKeyUsage(apiKey: String) async throws -> OpenRouterKeyUsage {
        let defaultBaseURL = ProviderType.openrouter.defaultBaseURL ?? "https://openrouter.ai/api/v1"
        let raw = (provider.baseURL ?? defaultBaseURL).trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw

        let lower = trimmed.lowercased()
        let normalizedBaseURL: String
        if lower.hasSuffix("/api/v1") || lower.hasSuffix("/v1") {
            normalizedBaseURL = trimmed
        } else if lower.hasSuffix("/api") {
            normalizedBaseURL = "\(trimmed)/v1"
        } else if let url = URL(string: trimmed), url.host?.lowercased().contains("openrouter.ai") == true {
            let path = url.path.lowercased()
            if path.isEmpty || path == "/" {
                normalizedBaseURL = "\(trimmed)/api/v1"
            } else {
                normalizedBaseURL = trimmed
            }
        } else {
            normalizedBaseURL = trimmed
        }

        guard let url = URL(string: "\(normalizedBaseURL)/key") else {
            throw LLMError.invalidRequest(message: "Invalid OpenRouter base URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("https://jin.app", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("Jin", forHTTPHeaderField: "X-Title")

        let (data, _) = try await networkManager.sendRequest(request)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(OpenRouterKeyResponse.self, from: data)

        let used = response.data.usage ?? 0
        var remaining: Double?
        if let limitRemaining = response.data.limitRemaining {
            remaining = max(limitRemaining, 0)
        } else if let limit = response.data.limit {
            remaining = max(limit - used, 0)
        } else {
            remaining = try await fetchOpenRouterRemainingCredits(apiKey: apiKey, baseURL: normalizedBaseURL)
        }

        return OpenRouterKeyUsage(used: used, remaining: remaining)
    }

    func fetchOpenRouterRemainingCredits(apiKey: String, baseURL: String) async throws -> Double? {
        guard let url = URL(string: "\(baseURL)/credits") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("https://jin.app", forHTTPHeaderField: "HTTP-Referer")
        request.addValue("Jin", forHTTPHeaderField: "X-Title")

        let (data, _) = try await networkManager.sendRequest(request)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(OpenRouterCreditsResponse.self, from: data)

        guard let totalCredits = response.data.totalCredits,
              let totalUsage = response.data.totalUsage else {
            return nil
        }

        return max(totalCredits - totalUsage, 0)
    }

    // MARK: - OpenRouter Usage Helpers

    var isOpenRouterUsageRefreshDisabled: Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || openRouterUsageStatus == .loading
    }

    var openRouterUsageStatusLabel: String {
        switch openRouterUsageStatus {
        case .idle, .failure:
            return "Not observed"
        case .loading:
            return "Checking"
        case .observed:
            return "Observed"
        }
    }

    var openRouterUsageStatusColor: Color {
        switch openRouterUsageStatus {
        case .observed:
            return .green
        case .loading:
            return .orange
        case .idle, .failure:
            return .secondary
        }
    }

    var openRouterUsageHintText: String {
        switch openRouterUsageStatus {
        case .idle:
            return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Enter an API key to check usage."
                : "Usage not fetched yet."
        case .loading:
            return "Fetching current key usage..."
        case .observed:
            return "No usage data returned for this key."
        case .failure:
            return "Failed to fetch usage for this key."
        }
    }

    func formatUSD(_ value: Double) -> String {
        "$" + value.formatted(.number.precision(.fractionLength(0...8)))
    }
}
