import AppKit
import Foundation

struct LobeProviderIcon: Identifiable, Hashable {
    let id: String
    let docsSlug: String
    let filename: String

    var pngFilename: String {
        filename.replacingOccurrences(of: ".svg", with: ".png")
    }

    private var pngResourceName: String {
        URL(fileURLWithPath: pngFilename).deletingPathExtension().lastPathComponent
    }

    func localPNGImage(useDarkMode: Bool) -> NSImage? {
        if let darkModeImage = cachedPNGImage(appearance: useDarkMode ? "dark" : "light") {
            return darkModeImage
        }

        // Fall back to light variant if dark asset is unexpectedly missing.
        if useDarkMode {
            return cachedPNGImage(appearance: "light")
        }
        return nil
    }

    private func cachedPNGImage(appearance: String) -> NSImage? {
        let cacheKey = "\(appearance)/\(pngFilename)"
        let resourceName = "\(appearance)_\(pngResourceName)"

        return LobeProviderIconCatalog.cachedImage(forKey: cacheKey) {
            guard let resourceURL = JinResourceBundle.url(
                forResource: resourceName,
                withExtension: "png"
            ) else {
                return nil
            }
            return NSImage(contentsOf: resourceURL)
        }
    }
}

enum LobeProviderIconCatalog {
    private final class ImageCache: @unchecked Sendable {
        private let lock = NSLock()
        private let cache: NSCache<NSString, NSImage> = {
            let cache = NSCache<NSString, NSImage>()
            cache.countLimit = 512
            return cache
        }()

        func object(forKey key: NSString) -> NSImage? {
            lock.lock()
            defer { lock.unlock() }
            return cache.object(forKey: key)
        }

        func setObject(_ image: NSImage, forKey key: NSString) {
            lock.lock()
            defer { lock.unlock() }
            cache.setObject(image, forKey: key)
        }
    }

    private static let imageCache = ImageCache()

    static func cachedImage(forKey key: String, loader: () -> NSImage?) -> NSImage? {
        let nsKey = key as NSString
        if let cached = imageCache.object(forKey: nsKey) {
            return cached
        }

        guard let image = loader() else {
            return nil
        }
        imageCache.setObject(image, forKey: nsKey)
        return image
    }

    static let all: [LobeProviderIcon] = [
        LobeProviderIcon(id: "Ai302", docsSlug: "ai302", filename: "ai302.svg"),
        LobeProviderIcon(id: "Ai360", docsSlug: "ai360", filename: "ai360.svg"),
        LobeProviderIcon(id: "AiHubMix", docsSlug: "ai-hub-mix", filename: "aihubmix.svg"),
        LobeProviderIcon(id: "AiMass", docsSlug: "ai-mass", filename: "aimass.svg"),
        LobeProviderIcon(id: "AiStudio", docsSlug: "ai-studio", filename: "aistudio.svg"),
        LobeProviderIcon(id: "AkashChat", docsSlug: "akash-chat", filename: "akashchat.svg"),
        LobeProviderIcon(id: "AlephAlpha", docsSlug: "aleph-alpha", filename: "alephalpha.svg"),
        LobeProviderIcon(id: "Alibaba", docsSlug: "alibaba", filename: "alibaba.svg"),
        LobeProviderIcon(id: "AlibabaCloud", docsSlug: "alibaba-cloud", filename: "alibabacloud.svg"),
        LobeProviderIcon(id: "AntGroup", docsSlug: "ant-group", filename: "antgroup.svg"),
        LobeProviderIcon(id: "Anthropic", docsSlug: "anthropic", filename: "anthropic.svg"),
        LobeProviderIcon(id: "Anyscale", docsSlug: "anyscale", filename: "anyscale.svg"),
        LobeProviderIcon(id: "Apple", docsSlug: "apple", filename: "apple.svg"),
        LobeProviderIcon(id: "AtlasCloud", docsSlug: "atlas-cloud", filename: "atlascloud.svg"),
        LobeProviderIcon(id: "Aws", docsSlug: "aws", filename: "aws.svg"),
        LobeProviderIcon(id: "Azure", docsSlug: "azure", filename: "azure.svg"),
        LobeProviderIcon(id: "AzureAI", docsSlug: "azure-ai", filename: "azureai.svg"),
        LobeProviderIcon(id: "Baidu", docsSlug: "baidu", filename: "baidu.svg"),
        LobeProviderIcon(id: "BaiduCloud", docsSlug: "baidu-cloud", filename: "baiducloud.svg"),
        LobeProviderIcon(id: "Bailian", docsSlug: "bailian", filename: "bailian.svg"),
        LobeProviderIcon(id: "Baseten", docsSlug: "baseten", filename: "baseten.svg"),
        LobeProviderIcon(id: "Bedrock", docsSlug: "bedrock", filename: "bedrock.svg"),
        LobeProviderIcon(id: "Bfl", docsSlug: "bfl", filename: "bfl.svg"),
        LobeProviderIcon(id: "Bilibili", docsSlug: "bilibili", filename: "bilibili.svg"),
        LobeProviderIcon(id: "BurnCloud", docsSlug: "burn-cloud", filename: "burncloud.svg"),
        LobeProviderIcon(id: "ByteDance", docsSlug: "byte-dance", filename: "bytedance.svg"),
        LobeProviderIcon(id: "CentML", docsSlug: "cent-ml", filename: "centml.svg"),
        LobeProviderIcon(id: "Cerebras", docsSlug: "cerebras", filename: "cerebras.svg"),
        LobeProviderIcon(id: "Civitai", docsSlug: "civitai", filename: "civitai.svg"),
        LobeProviderIcon(id: "Cloudflare", docsSlug: "cloudflare", filename: "cloudflare.svg"),
        LobeProviderIcon(id: "Cohere", docsSlug: "cohere", filename: "cohere.svg"),
        LobeProviderIcon(id: "CometAPI", docsSlug: "comet-api", filename: "cometapi.svg"),
        LobeProviderIcon(id: "Crusoe", docsSlug: "crusoe", filename: "crusoe.svg"),
        LobeProviderIcon(id: "DeepInfra", docsSlug: "deep-infra", filename: "deepinfra.svg"),
        LobeProviderIcon(id: "DeepMind", docsSlug: "deep-mind", filename: "deepmind.svg"),
        LobeProviderIcon(id: "DeepSeek", docsSlug: "deep-seek", filename: "deepseek.svg"),
        LobeProviderIcon(id: "Exa", docsSlug: "exa", filename: "exa.svg"),
        LobeProviderIcon(id: "Fal", docsSlug: "fal", filename: "fal.svg"),
        LobeProviderIcon(id: "Featherless", docsSlug: "featherless", filename: "featherless.svg"),
        LobeProviderIcon(id: "Fireworks", docsSlug: "fireworks", filename: "fireworks.svg"),
        LobeProviderIcon(id: "Friendli", docsSlug: "friendli", filename: "friendli.svg"),
        LobeProviderIcon(id: "GiteeAI", docsSlug: "gitee-ai", filename: "giteeai.svg"),
        LobeProviderIcon(id: "Github", docsSlug: "github", filename: "github.svg"),
        LobeProviderIcon(id: "Google", docsSlug: "google", filename: "google.svg"),
        LobeProviderIcon(id: "GoogleCloud", docsSlug: "google-cloud", filename: "googlecloud.svg"),
        LobeProviderIcon(id: "Groq", docsSlug: "groq", filename: "groq.svg"),
        LobeProviderIcon(id: "Higress", docsSlug: "higress", filename: "higress.svg"),
        LobeProviderIcon(id: "Huawei", docsSlug: "huawei", filename: "huawei.svg"),
        LobeProviderIcon(id: "HuaweiCloud", docsSlug: "huawei-cloud", filename: "huaweicloud.svg"),
        LobeProviderIcon(id: "HuggingFace", docsSlug: "hugging-face", filename: "huggingface.svg"),
        LobeProviderIcon(id: "Hyperbolic", docsSlug: "hyperbolic", filename: "hyperbolic.svg"),
        LobeProviderIcon(id: "IBM", docsSlug: "ibm", filename: "ibm.svg"),
        LobeProviderIcon(id: "IFlyTekCloud", docsSlug: "i-fly-tek-cloud", filename: "iflytekcloud.svg"),
        LobeProviderIcon(id: "Inference", docsSlug: "inference", filename: "inference.svg"),
        LobeProviderIcon(id: "Infermatic", docsSlug: "infermatic", filename: "infermatic.svg"),
        LobeProviderIcon(id: "Infinigence", docsSlug: "infinigence", filename: "infinigence.svg"),
        LobeProviderIcon(id: "InternLM", docsSlug: "intern-lm", filename: "internlm.svg"),
        LobeProviderIcon(id: "Jina", docsSlug: "jina", filename: "jina.svg"),
        LobeProviderIcon(id: "Kluster", docsSlug: "kluster", filename: "kluster.svg"),
        LobeProviderIcon(id: "Lambda", docsSlug: "lambda", filename: "lambda.svg"),
        LobeProviderIcon(id: "LeptonAI", docsSlug: "lepton-ai", filename: "leptonai.svg"),
        LobeProviderIcon(id: "LG", docsSlug: "lg", filename: "lg.svg"),
        LobeProviderIcon(id: "LmStudio", docsSlug: "lm-studio", filename: "lmstudio.svg"),
        LobeProviderIcon(id: "LobeHub", docsSlug: "lobe-hub", filename: "lobehub.svg"),
        LobeProviderIcon(id: "Menlo", docsSlug: "menlo", filename: "menlo.svg"),
        LobeProviderIcon(id: "Meta", docsSlug: "meta", filename: "meta.svg"),
        LobeProviderIcon(id: "Microsoft", docsSlug: "microsoft", filename: "microsoft.svg"),
        LobeProviderIcon(id: "Mistral", docsSlug: "mistral", filename: "mistral.svg"),
        LobeProviderIcon(id: "ModelScope", docsSlug: "model-scope", filename: "modelscope.svg"),
        LobeProviderIcon(id: "Moonshot", docsSlug: "moonshot", filename: "moonshot.svg"),
        LobeProviderIcon(id: "Nebius", docsSlug: "nebius", filename: "nebius.svg"),
        LobeProviderIcon(id: "NewAPI", docsSlug: "new-api", filename: "newapi.svg"),
        LobeProviderIcon(id: "NousResearch", docsSlug: "nous-research", filename: "nousresearch.svg"),
        LobeProviderIcon(id: "Novita", docsSlug: "novita", filename: "novita.svg"),
        LobeProviderIcon(id: "NPLCloud", docsSlug: "npl-cloud", filename: "nplcloud.svg"),
        LobeProviderIcon(id: "Nvidia", docsSlug: "nvidia", filename: "nvidia.svg"),
        LobeProviderIcon(id: "Ollama", docsSlug: "ollama", filename: "ollama.svg"),
        LobeProviderIcon(id: "OpenAI", docsSlug: "open-ai", filename: "openai.svg"),
        LobeProviderIcon(id: "OpenRouter", docsSlug: "open-router", filename: "openrouter.svg"),
        LobeProviderIcon(id: "Parasail", docsSlug: "parasail", filename: "parasail.svg"),
        LobeProviderIcon(id: "Perplexity", docsSlug: "perplexity", filename: "perplexity.svg"),
        LobeProviderIcon(id: "PPIO", docsSlug: "ppio", filename: "ppio.svg"),
        LobeProviderIcon(id: "Qiniu", docsSlug: "qiniu", filename: "qiniu.svg"),
        LobeProviderIcon(id: "Replicate", docsSlug: "replicate", filename: "replicate.svg"),
        LobeProviderIcon(id: "SambaNova", docsSlug: "samba-nova", filename: "sambanova.svg"),
        LobeProviderIcon(id: "Search1API", docsSlug: "search1-api", filename: "search1api.svg"),
        LobeProviderIcon(id: "SearchApi", docsSlug: "search-api", filename: "searchapi.svg"),
        LobeProviderIcon(id: "SiliconCloud", docsSlug: "silicon-cloud", filename: "siliconcloud.svg"),
        LobeProviderIcon(id: "Snowflake", docsSlug: "snowflake", filename: "snowflake.svg"),
        LobeProviderIcon(id: "SophNet", docsSlug: "soph-net", filename: "sophnet.svg"),
        LobeProviderIcon(id: "Stability", docsSlug: "stability", filename: "stability.svg"),
        LobeProviderIcon(id: "StateCloud", docsSlug: "state-cloud", filename: "statecloud.svg"),
        LobeProviderIcon(id: "Straico", docsSlug: "straico", filename: "straico.svg"),
        LobeProviderIcon(id: "StreamLake", docsSlug: "stream-lake", filename: "streamlake.svg"),
        LobeProviderIcon(id: "SubModel", docsSlug: "sub-model", filename: "submodel.svg"),
        LobeProviderIcon(id: "Targon", docsSlug: "targon", filename: "targon.svg"),
        LobeProviderIcon(id: "Tencent", docsSlug: "tencent", filename: "tencent.svg"),
        LobeProviderIcon(id: "TencentCloud", docsSlug: "tencent-cloud", filename: "tencentcloud.svg"),
        LobeProviderIcon(id: "TII", docsSlug: "tii", filename: "tii.svg"),
        LobeProviderIcon(id: "Together", docsSlug: "together", filename: "together.svg"),
        LobeProviderIcon(id: "Upstage", docsSlug: "upstage", filename: "upstage.svg"),
        LobeProviderIcon(id: "Vercel", docsSlug: "vercel", filename: "vercel.svg"),
        LobeProviderIcon(id: "VertexAI", docsSlug: "vertex-ai", filename: "vertexai.svg"),
        LobeProviderIcon(id: "Vllm", docsSlug: "vllm", filename: "vllm.svg"),
        LobeProviderIcon(id: "Volcengine", docsSlug: "volcengine", filename: "volcengine.svg"),
        LobeProviderIcon(id: "WorkersAI", docsSlug: "workers-ai", filename: "workersai.svg"),
        LobeProviderIcon(id: "XAI", docsSlug: "xai", filename: "xai.svg"),
        LobeProviderIcon(id: "Xinference", docsSlug: "xinference", filename: "xinference.svg"),
        LobeProviderIcon(id: "Yandex", docsSlug: "yandex", filename: "yandex.svg"),
        LobeProviderIcon(id: "ZenMux", docsSlug: "zen-mux", filename: "zenmux.svg"),
        LobeProviderIcon(id: "ZeroOne", docsSlug: "zero-one", filename: "zeroone.svg"),
        LobeProviderIcon(id: "Zhipu", docsSlug: "zhipu", filename: "zhipu.svg"),
    ]

    private static let iconByLowercasedID: [String: LobeProviderIcon] = Dictionary(uniqueKeysWithValues: all.map { icon in
        (icon.id.lowercased(), icon)
    })

    static func icon(forID id: String?) -> LobeProviderIcon? {
        guard let id else { return nil }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return iconByLowercasedID[trimmed.lowercased()]
    }

    static func defaultIconID(for providerType: ProviderType) -> String {
        switch providerType {
        case .openai:
            return "OpenAI"
        case .openaiWebSocket:
            return "OpenAI"
        case .codexAppServer:
            return "OpenAI"
        case .openaiCompatible:
            return "OpenAI"
        case .openrouter:
            return "OpenRouter"
        case .anthropic:
            return "Anthropic"
        case .perplexity:
            return "Perplexity"
        case .groq:
            return "Groq"
        case .cohere:
            return "Cohere"
        case .mistral:
            return "Mistral"
        case .deepinfra:
            return "DeepInfra"
        case .xai:
            return "XAI"
        case .deepseek:
            return "DeepSeek"
        case .fireworks:
            return "Fireworks"
        case .cerebras:
            return "Cerebras"
        case .gemini:
            return "AiStudio"
        case .vertexai:
            return "VertexAI"
        }
    }
}

extension ProviderConfigEntity {
    var resolvedProviderIconID: String? {
        if let iconID {
            let trimmed = iconID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        guard let providerType = ProviderType(rawValue: typeRaw) else { return nil }
        return LobeProviderIconCatalog.defaultIconID(for: providerType)
    }
}
