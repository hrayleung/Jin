enum AppPreferenceKeys {

    // MARK: - New Chat Defaults

    static let newChatModelMode = "newChatModelMode"
    static let newChatFixedProviderID = "newChatFixedProviderID"
    static let newChatFixedModelID = "newChatFixedModelID"

    static let newChatMCPMode = "newChatMCPMode"
    static let newChatFixedMCPEnabled = "newChatFixedMCPEnabled"
    static let newChatFixedMCPUseAllServers = "newChatFixedMCPUseAllServers"
    static let newChatFixedMCPServerIDsJSON = "newChatFixedMCPServerIDsJSON"

    // MARK: - Appearance

    static let appAppearanceMode = "appAppearanceMode"
    static let appFontFamily = "appFontFamily"
    static let codeFontFamily = "codeFontFamily"
    static let useOverlayScrollbars = "useOverlayScrollbars"

    // MARK: - Chat

    static let sendWithCommandEnter = "sendWithCommandEnter"
    static let notifyOnBackgroundResponseCompletion = "notifyOnBackgroundResponseCompletion"
    static let keyboardShortcuts = "keyboardShortcuts.v1"
    static let thinkingBlockDisplayMode = "thinkingBlockDisplayMode"
    static let codexToolDisplayMode = "codexToolDisplayMode"
    static let codeExecutionDisplayMode = "codeExecutionDisplayMode"
    static let codeBlockDisplayMode = "codeBlockDisplayMode"
    static let codexWorkingDirectoryPresetsJSON = "codexWorkingDirectoryPresetsJSON"
    static let codeBlockShowLineNumbers = "codeBlockShowLineNumbers"
    static let codeBlockCollapseLineThreshold = "codeBlockCollapseLineThreshold"
    static let mainSidebarWidth = "mainSidebarWidth"

    // Agent Mode
    static let agentModeEnabled = "agentModeEnabled"
    static let agentModeWorkingDirectory = "agentModeWorkingDirectory"
    static let agentModeAllowedCommandPrefixesJSON = "agentModeAllowedCommandPrefixesJSON"
    static let agentModeDefaultSafePrefixesJSON = "agentModeDefaultSafePrefixesJSON"
    static let agentModeCommandTimeoutSeconds = "agentModeCommandTimeoutSeconds"
    static let agentModeAutoApproveFileReads = "agentModeAutoApproveFileReads"
    static let agentModeToolShell = "agentModeToolShell"
    static let agentModeToolFileRead = "agentModeToolFileRead"
    static let agentModeToolFileWrite = "agentModeToolFileWrite"
    static let agentModeToolFileEdit = "agentModeToolFileEdit"
    static let agentModeToolGlob = "agentModeToolGlob"
    static let agentModeToolGrep = "agentModeToolGrep"
    static let agentModeBypassPermissions = "agentModeBypassPermissions"
    static let agentToolDisplayMode = "agentToolDisplayMode"

    // MARK: - Updates

    // Update checker
    static let updateAutoCheckOnLaunch = "updateAutoCheckOnLaunch"
    static let updateAllowPreRelease = "updateAllowPreRelease"

    // MARK: - Extensions

    // Plugin visibility toggles (default: true)
    static let pluginTextToSpeechEnabled = "pluginTextToSpeechEnabled"
    static let pluginSpeechToTextEnabled = "pluginSpeechToTextEnabled"
    static let pluginMistralOCREnabled = "pluginMistralOCREnabled"
    static let pluginMineruOCREnabled = "pluginMineruOCREnabled"
    static let pluginDeepSeekOCREnabled = "pluginDeepSeekOCREnabled"
    static let pluginOpenRouterOCREnabled = "pluginOpenRouterOCREnabled"
    static let pluginFirecrawlOCREnabled = "pluginFirecrawlOCREnabled"
    static let pluginChatNamingEnabled = "pluginChatNamingEnabled"
    static let pluginCloudflareR2UploadEnabled = "pluginCloudflareR2UploadEnabled"
    static let pluginWebSearchEnabled = "pluginWebSearchEnabled"

    static let pluginMistralOCRAPIKey = "pluginMistralOCRAPIKey"
    static let pluginMineruOCRAPIToken = "pluginMineruOCRAPIToken"
    static let pluginMineruOCRUserIdentifier = "pluginMineruOCRUserIdentifier"
    static let pluginMineruOCRLanguage = "pluginMineruOCRLanguage"
    static let pluginDeepSeekOCRAPIKey = "pluginDeepSeekOCRAPIKey"
    static let pluginOpenRouterOCRAPIKey = "pluginOpenRouterOCRAPIKey"
    static let pluginOpenRouterOCRModelID = "pluginOpenRouterOCRModelID"
    static let pluginWebSearchDefaultProvider = "pluginWebSearchDefaultProvider"
    static let pluginWebSearchDefaultMaxResults = "pluginWebSearchDefaultMaxResults"
    static let pluginWebSearchDefaultRecencyDays = "pluginWebSearchDefaultRecencyDays"
    static let pluginWebSearchExaAPIKey = "pluginWebSearchExaAPIKey"
    static let pluginWebSearchBraveAPIKey = "pluginWebSearchBraveAPIKey"
    static let pluginWebSearchJinaAPIKey = "pluginWebSearchJinaAPIKey"
    static let pluginWebSearchFirecrawlAPIKey = "pluginWebSearchFirecrawlAPIKey"
    static let pluginWebSearchExaSearchType = "pluginWebSearchExaSearchType"
    static let pluginWebSearchBraveCountry = "pluginWebSearchBraveCountry"
    static let pluginWebSearchBraveLanguage = "pluginWebSearchBraveLanguage"
    static let pluginWebSearchBraveSafesearch = "pluginWebSearchBraveSafesearch"
    static let pluginWebSearchJinaReadPages = "pluginWebSearchJinaReadPages"
    static let pluginWebSearchFirecrawlExtractContent = "pluginWebSearchFirecrawlExtractContent"
    static let pluginWebSearchTavilyAPIKey = "pluginWebSearchTavilyAPIKey"
    static let pluginWebSearchPerplexityAPIKey = "pluginWebSearchPerplexityAPIKey"
    static let pluginWebSearchTavilySearchDepth = "pluginWebSearchTavilySearchDepth"
    static let pluginWebSearchTavilyTopic = "pluginWebSearchTavilyTopic"

    // Cloudflare R2 Upload
    static let cloudflareR2AccountID = "cloudflareR2AccountID"
    static let cloudflareR2AccessKeyID = "cloudflareR2AccessKeyID"
    static let cloudflareR2SecretAccessKey = "cloudflareR2SecretAccessKey"
    static let cloudflareR2Bucket = "cloudflareR2Bucket"
    static let cloudflareR2PublicBaseURL = "cloudflareR2PublicBaseURL"
    static let cloudflareR2KeyPrefix = "cloudflareR2KeyPrefix"

    // Chat naming
    static let chatNamingMode = "chatNamingMode"
    static let chatNamingProviderID = "chatNamingProviderID"
    static let chatNamingModelID = "chatNamingModelID"

    // Text to Speech
    static let ttsMiniPlayerEnabled = "ttsMiniPlayerEnabled"
    static let ttsProvider = "ttsProvider"

    static let ttsOpenAIAPIKey = "ttsOpenAIAPIKey"
    static let ttsOpenAIBaseURL = "ttsOpenAIBaseURL"
    static let ttsOpenAIModel = "ttsOpenAIModel"
    static let ttsOpenAIVoice = "ttsOpenAIVoice"
    static let ttsOpenAIResponseFormat = "ttsOpenAIResponseFormat"
    static let ttsOpenAISpeed = "ttsOpenAISpeed"
    static let ttsOpenAIInstructions = "ttsOpenAIInstructions"

    static let ttsGroqAPIKey = "ttsGroqAPIKey"
    static let ttsGroqBaseURL = "ttsGroqBaseURL"
    static let ttsGroqModel = "ttsGroqModel"
    static let ttsGroqVoice = "ttsGroqVoice"
    static let ttsGroqResponseFormat = "ttsGroqResponseFormat"

    static let ttsMiMoAPIKey = "ttsMiMoAPIKey"
    static let ttsMiMoBaseURL = "ttsMiMoBaseURL"
    static let ttsMiMoModel = "ttsMiMoModel"
    static let ttsMiMoVoice = "ttsMiMoVoice"
    static let ttsMiMoResponseFormat = "ttsMiMoResponseFormat"
    static let ttsMiMoStyleInstruction = "ttsMiMoStyleInstruction"
    static let ttsMiMoVoiceCloneSamplePath = "ttsMiMoVoiceCloneSamplePath"

    static let ttsElevenLabsAPIKey = "ttsElevenLabsAPIKey"
    static let ttsElevenLabsBaseURL = "ttsElevenLabsBaseURL"
    static let ttsElevenLabsModelID = "ttsElevenLabsModelID"
    static let ttsElevenLabsVoiceID = "ttsElevenLabsVoiceID"
    static let ttsElevenLabsOutputFormat = "ttsElevenLabsOutputFormat"
    static let ttsElevenLabsOptimizeStreamingLatency = "ttsElevenLabsOptimizeStreamingLatency"
    static let ttsElevenLabsEnableLogging = "ttsElevenLabsEnableLogging"
    static let ttsElevenLabsStability = "ttsElevenLabsStability"
    static let ttsElevenLabsSimilarityBoost = "ttsElevenLabsSimilarityBoost"
    static let ttsElevenLabsStyle = "ttsElevenLabsStyle"
    static let ttsElevenLabsUseSpeakerBoost = "ttsElevenLabsUseSpeakerBoost"

    // Networking / Debug
    static let networkDebugLoggingEnabled = "networkDebugLoggingEnabled"
    static let chatDiagnosticLoggingEnabled = "chatDiagnosticLoggingEnabled"

    // Speech to Text
    static let sttProvider = "sttProvider"
    static let sttAddRecordingAsFile = "sttAddRecordingAsFile"

    static let sttOpenAIAPIKey = "sttOpenAIAPIKey"
    static let sttOpenAIBaseURL = "sttOpenAIBaseURL"
    static let sttOpenAIModel = "sttOpenAIModel"
    static let sttOpenAILanguage = "sttOpenAILanguage"
    static let sttOpenAIPrompt = "sttOpenAIPrompt"
    static let sttOpenAITranslateToEnglish = "sttOpenAITranslateToEnglish"
    static let sttOpenAIResponseFormat = "sttOpenAIResponseFormat"
    static let sttOpenAITemperature = "sttOpenAITemperature"
    static let sttOpenAITimestampGranularitiesJSON = "sttOpenAITimestampGranularitiesJSON"

    static let sttGroqAPIKey = "sttGroqAPIKey"
    static let sttGroqBaseURL = "sttGroqBaseURL"
    static let sttGroqModel = "sttGroqModel"
    static let sttGroqLanguage = "sttGroqLanguage"
    static let sttGroqPrompt = "sttGroqPrompt"
    static let sttGroqTranslateToEnglish = "sttGroqTranslateToEnglish"
    static let sttGroqResponseFormat = "sttGroqResponseFormat"
    static let sttGroqTemperature = "sttGroqTemperature"
    static let sttGroqTimestampGranularitiesJSON = "sttGroqTimestampGranularitiesJSON"

    static let sttMistralAPIKey = "sttMistralAPIKey"
    static let sttMistralBaseURL = "sttMistralBaseURL"
    static let sttMistralModel = "sttMistralModel"
    static let sttMistralLanguage = "sttMistralLanguage"
    static let sttMistralPrompt = "sttMistralPrompt"
    static let sttMistralResponseFormat = "sttMistralResponseFormat"
    static let sttMistralTemperature = "sttMistralTemperature"
    static let sttMistralTimestampGranularitiesJSON = "sttMistralTimestampGranularitiesJSON"

    static let sttElevenLabsAPIKey = "sttElevenLabsAPIKey"
    static let sttElevenLabsBaseURL = "sttElevenLabsBaseURL"
    static let sttElevenLabsModel = "sttElevenLabsModel"
    static let sttElevenLabsLanguageCode = "sttElevenLabsLanguageCode"
    static let sttElevenLabsTagAudioEvents = "sttElevenLabsTagAudioEvents"
    static let sttElevenLabsNoVerbatim = "sttElevenLabsNoVerbatim"
    static let sttElevenLabsDiarize = "sttElevenLabsDiarize"
    static let sttElevenLabsNumSpeakers = "sttElevenLabsNumSpeakers"
    static let sttElevenLabsTimestampsGranularity = "sttElevenLabsTimestampsGranularity"
    static let sttElevenLabsFileFormat = "sttElevenLabsFileFormat"
    static let sttElevenLabsTemperature = "sttElevenLabsTemperature"

    // WhisperKit STT (On-Device)
    static let sttWhisperKitModel = "sttWhisperKitModel"
    static let sttWhisperKitLanguage = "sttWhisperKitLanguage"
    static let sttWhisperKitTranslateToEnglish = "sttWhisperKitTranslateToEnglish"

    // TTSKit (On-Device)
    static let ttsTTSKitModel = "ttsTTSKitModel"
    static let ttsTTSKitLanguage = "ttsTTSKitLanguage"
    static let ttsTTSKitVoice = "ttsTTSKitVoice"
    static let ttsTTSKitPlaybackMode = "ttsTTSKitPlaybackMode"
    static let ttsTTSKitStyleInstruction = "ttsTTSKitStyleInstruction"
}
