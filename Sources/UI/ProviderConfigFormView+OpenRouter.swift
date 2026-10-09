import SwiftUI

// MARK: - OpenRouter Usage

extension ProviderConfigFormView {

    var openRouterUsageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API Usage").font(.callout.weight(.medium))
                Spacer()
                if openRouterUsageStatus == .loading {
                    ProgressView().controlSize(.small)
                }
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await refreshOpenRouterUsage(force: true) }
                }
                .controlSize(.small)
                .disabled(isOpenRouterUsageRefreshDisabled)
            }

            if let usage = openRouterUsage {
                LabeledContent("Used", value: formatUSD(usage.used))
                LabeledContent("Remaining", value: usage.remainingText(formatter: formatUSD))
            } else {
                Text(openRouterUsageHintText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case .failure(let message) = openRouterUsageStatus {
                JinSettingsErrorText(text: message)
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
        let normalizedBaseURL = OpenRouterProviderSupport.normalizedBaseURL(provider.baseURL)

        guard let url = URL(string: "\(normalizedBaseURL)/key") else {
            throw LLMError.invalidRequest(message: "Invalid OpenRouter base URL.")
        }

        let request = makeGETRequest(
            url: url,
            apiKey: apiKey,
            additionalHeaders: OpenRouterProviderSupport.appIdentityHeaders,
            includeUserAgent: false
        )

        let (data, _) = try await networkManager.sendRequest(request)

        let response = try JSONDecoder.snakeCaseConverting().decode(OpenRouterKeyResponse.self, from: data)

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

        let request = makeGETRequest(
            url: url,
            apiKey: apiKey,
            additionalHeaders: OpenRouterProviderSupport.appIdentityHeaders,
            includeUserAgent: false
        )

        let (data, _) = try await networkManager.sendRequest(request)

        let response = try JSONDecoder.snakeCaseConverting().decode(OpenRouterCreditsResponse.self, from: data)

        guard let totalCredits = response.data.totalCredits,
              let totalUsage = response.data.totalUsage else {
            return nil
        }

        return max(totalCredits - totalUsage, 0)
    }

    // MARK: - OpenRouter Usage Helpers

    var openRouterUsagePresentation: ProviderFormSupport.OpenRouterUsagePresentation {
        ProviderFormSupport.openRouterUsagePresentation(
            apiKey: apiKey,
            status: openRouterUsageStatus
        )
    }

    var isOpenRouterUsageRefreshDisabled: Bool {
        openRouterUsagePresentation.isRefreshDisabled
    }

    var openRouterUsageHintText: String {
        openRouterUsagePresentation.hintText
    }

    func formatUSD(_ value: Double) -> String {
        "$" + value.formatted(.number.precision(.fractionLength(0...8)))
    }
}
