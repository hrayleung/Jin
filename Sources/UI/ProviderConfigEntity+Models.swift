import Foundation

private struct ProviderModelsSnapshot: Equatable {
    let byteCount: Int
    let storageAddress: Int
    let edgeDigest: UInt64
}

private struct ProviderResolvedModels {
    let all: [ModelInfo]
    let enabled: [ModelInfo]
}

private final class ProviderModelsDecodeCache: @unchecked Sendable {
    private struct CacheEntry {
        let snapshot: ProviderModelsSnapshot
        let resolved: ProviderResolvedModels
    }

    private let lock = NSLock()
    private var entries: [ObjectIdentifier: CacheEntry] = [:]

    func resolvedModels(for provider: ProviderConfigEntity) -> ProviderResolvedModels {
        let data = provider.modelsData
        let snapshot = makeSnapshot(for: data)
        let providerObjectID = ObjectIdentifier(provider)

        lock.lock()
        if let cached = entries[providerObjectID], cached.snapshot == snapshot {
            let resolved = cached.resolved
            lock.unlock()
            return resolved
        }
        lock.unlock()

        let allModels = (try? JSONDecoder().decode([ModelInfo].self, from: data)) ?? []
        let resolved = ProviderResolvedModels(
            all: allModels,
            enabled: allModels.filter(\.isEnabled)
        )

        lock.lock()
        entries[providerObjectID] = CacheEntry(snapshot: snapshot, resolved: resolved)
        if entries.count > 256 {
            entries.remove(at: entries.startIndex)
        }
        lock.unlock()

        return resolved
    }

    private func makeSnapshot(for data: Data) -> ProviderModelsSnapshot {
        var storageAddress = 0
        var digest: UInt64 = 1_469_598_103_934_665_603 // FNV-1a offset basis

        data.withUnsafeBytes { rawBuffer in
            storageAddress = rawBuffer.baseAddress.map { Int(bitPattern: $0) } ?? 0

            let count = rawBuffer.count
            guard count > 0 else { return }

            let prefixCount = min(count, 16)
            for index in 0..<prefixCount {
                digest = (digest ^ UInt64(rawBuffer[index])) &* 1_099_511_628_211
            }

            let suffixStart = max(prefixCount, count - 16)
            if suffixStart < count {
                for index in suffixStart..<count {
                    digest = (digest ^ UInt64(rawBuffer[index])) &* 1_099_511_628_211
                }
            }
        }

        return ProviderModelsSnapshot(
            byteCount: data.count,
            storageAddress: storageAddress,
            edgeDigest: digest
        )
    }
}

extension ProviderConfigEntity {
    private static let modelsCache = ProviderModelsDecodeCache()

    var allModels: [ModelInfo] {
        Self.modelsCache.resolvedModels(for: self).all
    }

    var enabledModels: [ModelInfo] {
        Self.modelsCache.resolvedModels(for: self).enabled
    }
}
