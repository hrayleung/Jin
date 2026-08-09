import AppKit
import SwiftUI
@testable import Jin

/// Shared fixtures for the timeline geometry probes. The prose is the real
/// content of the conversation that reproduced the "clipped bubble + giant
/// gap" report (markdown headings, bold runs, numbered weaknesses, a CJK
/// tail) — the shapes where SwiftUI's ideal size and its width-wrapped size
/// diverge, which is what the whole bug family turns on.
@MainActor
enum TimelineRowFixtures {

    // MARK: - Rows

    static func item(
        role: String,
        text: String? = nil,
        blocks: [RenderedMessageBlock]? = nil,
        copyText: String? = nil
    ) -> MessageRenderItem {
        MessageRenderItem(
            id: UUID(),
            role: role,
            timestamp: Date(timeIntervalSince1970: 1),
            renderedBlocks: blocks ?? [.content(anchorID: "text-0", part: .text(text ?? ""))],
            toolCalls: [],
            searchActivities: [],
            codeExecutionActivities: [],
            assistantModelLabel: role == "assistant" ? "gpt-5.6-sol" : nil,
            assistantProviderIconID: nil,
            responseMetrics: nil,
            copyText: copyText ?? text ?? "",
            preferredRenderMode: .fullWeb,
            isMemoryIntensiveAssistantContent: false,
            collapsedPreview: nil,
            canEditUserMessage: role == "user",
            canDeleteResponse: role == "assistant",
            perMessageMCPServerNames: []
        )
    }

    static func thinkingItem(text: String, thinking: String) -> MessageRenderItem {
        item(
            role: "assistant",
            blocks: [
                .content(anchorID: "thinking-0", part: .thinking(ThinkingBlock(text: thinking))),
                .content(anchorID: "text-0", part: .text(text)),
            ],
            copyText: text
        )
    }

    /// The shape of the row reported as "top of the reply is missing until I
    /// scroll": a web-search strip plus a collapsed thinking block and NO text
    /// body, so the row is short chrome-only content whose height moves as the
    /// search/thinking rows resolve.
    static func searchAndThinkingOnlyItem() -> MessageRenderItem {
        let activities = (0..<8).map { index in
            SearchActivity(
                id: "search-\(index)",
                type: index == 0 ? "web_search_call" : "open_page",
                status: .completed,
                arguments: [
                    "query": AnyCodable("the weepies 是不活跃了吗"),
                    "url": AnyCodable("https://example\(index).com/the-weepies"),
                ]
            )
        }
        return MessageRenderItem(
            id: UUID(),
            role: "assistant",
            timestamp: Date(timeIntervalSince1970: 1),
            renderedBlocks: [
                .content(anchorID: "thinking-0", part: .thinking(ThinkingBlock(text: thinkingText))),
            ],
            toolCalls: [],
            searchActivities: activities,
            codeExecutionActivities: [],
            assistantModelLabel: "Qwen3.8 Max",
            assistantProviderIconID: nil,
            responseMetrics: nil,
            copyText: "",
            preferredRenderMode: .fullWeb,
            isMemoryIntensiveAssistantContent: false,
            collapsedPreview: nil,
            canEditUserMessage: false,
            canDeleteResponse: true,
            perMessageMCPServerNames: []
        )
    }

    /// Same shape as the reported conversation (7 turns): long user paste,
    /// long reasoning reply, short user follow-up, reply, two long CJK user
    /// turns, final reply.
    static func reportedConversation() -> [MessageRenderItem] {
        [
            item(role: "user", text: reportedUserMessage),
            thinkingItem(text: assistantReply, thinking: thinkingText),
            item(role: "user", text: "review简洁些，ai味道别太重了"),
            thinkingItem(text: shortAssistantReply, thinking: thinkingText),
            item(role: "user", text: cjkUserFollowUp),
            item(role: "user", text: cjkUserFollowUp),
            thinkingItem(text: assistantReply, thinking: thinkingText),
            // Code + table: the blocks whose height lands LATE (async syntax
            // highlighting swaps bold/italic runs, which can re-wrap), so the
            // row must still end up matching what it paints.
            item(role: "assistant", text: codeAndTableReply),
            item(role: "user", text: "the weepies是不活跃了吗"),
            searchAndThinkingOnlyItem(),
            item(role: "assistant", text: wideCodeReply),
        ]
    }

    // MARK: - Environment

    static func shared(columnWidth: CGFloat) -> ChatTimelineSharedInputs {
        ChatTimelineSharedInputs(
            maxBubbleWidth: ChatConversationLayoutMetrics.assistantBubbleMaxWidth(for: columnWidth),
            columnWidth: columnWidth,
            layoutCenterOffset: 0,
            assistantDisplayName: "Jin",
            providerType: .openai,
            providerIconID: nil,
            eagerCodeHighlightStartIndex: 0,
            payloadResolver: .noop,
            toolResultsByCallID: [:],
            messageEntitiesByID: [:],
            interaction: interaction(),
            onOpenArtifact: { _ in },
            // `.fullWeb` is the normal rich path: markdown blocks, tables and
            // code blocks. `.nativeText` is the degraded plain-text mode for
            // huge messages and renders NO code blocks at all — fixtures on it
            // silently skip most of the view tree these probes exist to cover.
            effectiveRenderMode: { _, _ in .fullWeb },
            onExpandCollapsedContent: { _ in },
            colorScheme: .dark
        )
    }

    static func epoch(entityCount: Int) -> ChatTimelineContentEpoch {
        ChatTimelineContentEpoch(
            renderRevision: 0,
            hiddenCount: 0,
            eagerCodeHighlightStartIndex: 0,
            layoutCenterOffsetBucket: 0,
            assistantDisplayName: "Jin",
            providerType: .openai,
            providerIconID: nil,
            toolResultsByCallID: [:],
            entityCount: entityCount,
            editingUserMessageID: nil,
            editSlashCommandKey: .inactive,
            textToSpeechEnabled: false,
            textToSpeechConfigured: false,
            textToSpeechPlaybackState: .idle,
            expandedCollapsedMessageIDs: [],
            colorScheme: .dark,
            appFontFamily: "",
            codeFontFamily: "",
            streamingObjectID: nil,
            streamingModelLabel: nil,
            streamingModelID: nil
        )
    }

    static func interaction() -> ChatMessageInteractionContext {
        ChatMessageInteractionContext(
            textToSpeechEnabled: false,
            textToSpeechConfigured: false,
            textToSpeechPlaybackState: .idle,
            editingUserMessageID: nil,
            editingUserMessageText: .constant(""),
            editingUserMessageFocused: .constant(false),
            textToSpeechIsGenerating: { _ in false },
            textToSpeechIsPlaying: { _ in false },
            textToSpeechIsPaused: { _ in false },
            onToggleSpeakAssistantMessage: { _, _ in },
            onStopSpeakAssistantMessage: { _ in },
            onRegenerate: { _ in },
            onEditUserMessage: { _ in },
            onSubmitUserEdit: { _ in },
            onCancelUserEdit: {},
            onDeleteMessage: { _ in },
            onDeleteResponse: { _ in },
            onQuoteSelection: { _, _, _ in },
            onCreateHighlight: { _ in },
            onRemoveHighlights: { _ in },
            editSlashCommand: .inactive
        )
    }

    // MARK: - Prose

    static let thinkingText = String(
        repeating: "**Evaluating the paper**\n\nWeighing the claims against the measurements. ",
        count: 12
    )

    static let reportedUserMessage = """
    ## Review

    **Recommendation:** Borderline / Weak Accept
    **Confidence:** 4/5

    ### Summary

    FlexDiT is a serving system for DiT-based image and video generation. Its main idea is to avoid assigning one fixed GPU group to an entire request. It chooses a target DoP from offline profiles, allows DiT requests to start with fewer GPUs and scale up at denoising-step boundaries, and allocates DiT and VAE separately. The system is implemented on VideoSys and SGLang Diffusion and evaluated with OpenSora and Z-Image.

    ### Strengths

    S1.The problem is important, and the motivation is convincing. In particular, the measurements showing resolution-dependent DiT scaling and different DiT/VAE behavior are useful.

    S2.The design is practical. Restricting reallocation to step boundaries avoids full preemption while still allowing released GPUs to be reused.

    S3.The evaluation covers both T2V and T2I, two runtimes, and several relevant ablations. The ablations on phase decoupling and promotion policy are especially helpful.

    ### Weaknesses

    W1.**The paper talks a lot about resource efficiency, but does not measure it directly.** Most results are latency and SLO attainment. I would like to see GPU seconds per request, utilization, and goodput. Otherwise, it is hard to tell how much of the gain comes from using resources more efficiently versus changing request ordering.

    W2.**The high-load results need more explanation.** The paper says the queue grows continuously after saturation. In that case, P90/P99 depend on the trace length and number of requests. These details, along with variance across runs and per-resolution latency, should be reported.

    W3.**Some conclusions are specific to the evaluated runtimes.** The VAE result partly comes from VideoSys and SGLang replicating VAE work across ranks. Likewise, the T2I batching conclusion is mostly inferred rather than directly measured. The observations are still valuable, but the claims should be scoped more carefully.

    W4.**The scale-out claim is somewhat limited.** In the two-node experiment, each request remains within one node, and the 64-GPU experiment is simulated. This demonstrates cluster-level scheduling, but not cross-node elastic execution.

    ### Overall

    The problem is well motivated and the experiments suggest that the approach is useful. My main concern is that the evaluation does not directly support the paper's resource efficiency claim, and some of the broader conclusions are based on runtime-specific behavior. These issues seem fixable, so I am currently **borderline, leaning weak accept**.你觉得这个review怎么样，帮我改改，看能不能改成weak reject吧，SoCC2026
    """

    static let assistantReply = """
    ### Weaknesses

    W1.**The paper talks a lot about resource efficiency, but does not measure it directly.** Most results are latency and SLO attainment. I would like to see GPU seconds per request, utilization, and goodput.

    W2.**The high-load results need more explanation.** The paper says the queue grows continuously after saturation. In that case, P90/P99 depend on the trace length and number of requests. These details, along with variance across runs and per-resolution latency, should be reported.

    W3.**Some conclusions are specific to the evaluated runtimes.** The VAE result partly comes from VideoSys and SGLang replicating VAE work across ranks.

    W4.**The scale-out claim is somewhat limited.** In the two-node experiment, each request remains within one node, and the 64-GPU experiment is simulated.

    **Recommendation:** Weak Reject
    """

    static let shortAssistantReply = """
    如果你真实判断这些问题已经影响论文核心结论，那么可以合理改成 **Weak Reject**。关键不是单纯调低分数，而是明确：

    1. 论文形式化目标包含 GPU-time，但实验没有测量它，属于**核心 claim–evidence mismatch**。
    2. 饱和后的 tail latency 实验缺少必要方法细节，headline 结果可能不可复现、不可稳定解释。
    3. 这些问题需要补做实验，不太可能只靠 rebuttal 澄清。
    """

    /// A code block with a line far wider than the column, so its horizontal
    /// scroll view actually claims the wheel gesture (the only case that traps
    /// vertical scrolling).
    static let wideCodeReply = """
    ```swift
    let result = controller.performHeightAudit(reason: "apply-settle", tableView: tableView, rows: rows, spacing: tableView.intercellSpacing.height, visibleTop: scrollView.documentVisibleRect.minY, now: ProcessInfo.processInfo.systemUptime)
    ```
    """

    static let codeAndTableReply = """
    下面是一个最小实现，注意 `intercellSpacing` 的处理：

    ```swift
    func performHeightAudit(reason: String) {
        tableView.enumerateAvailableRowViews { rowView, row in
            // rect(ofRow:) carries the intercell spacing; heightOfRow does not.
            let applied = rowView.frame.height - tableView.intercellSpacing.height
            let measured = cell.measuredContentHeight()
            guard abs(applied - measured) > 1 else { return }
            noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
        }
    }
    ```

    | 数值来源 | 含 intercellSpacing | 用途 |
    | --- | --- | --- |
    | `heightOfRow` | 否 | 行高的唯一真源 |
    | `rect(ofRow:)` | 是 | 文档坐标 |
    | `rowView.frame` | 是 | 行容器 |
    | `cell.frame` | 否 | 裁剪边界 |

    所以审计里必须减掉一次 spacing，否则每一行都会被判定为"高了 16pt"。
    """

    static let cjkUserFollowUp = """
    总体判断：**weakness 的写法比上一版扎实得多，但分数和理由现在脱钩了。** 具体说，W1–W4 全部属于"没测 / 没说清"，而 Overall 段用来支撑降到 Weak Reject 的理由是"这些需要新实验而非澄清"——这句话对你自己列的四条并不成立。

    ## 核心问题：多数 ask 其实是澄清或改写

    逐条对一下作者在 rebuttal 里能做什么：

    - W1 要 GPU-seconds / 利用率 / goodput：这三个量作者手里的 trace 基本都能直接算出来，属于补表格而不是补实验。
    - W2 要 trace 长度、请求数、跨 run 方差：这是方法细节，写清楚即可。
    - W3 要把结论 scope 到具体 runtime：这是措辞修改。
    - W4 要 cross-node elastic execution：这条才是真正需要新实验的。

    所以四条里只有一条支撑"需要新实验"的说法。如果最终仍要给 Weak Reject，理由应该收敛到 claim–evidence mismatch 本身，而不是"需要新实验"。
    """
}
