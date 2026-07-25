import Foundation

/// Corpus of real-LLM-shaped markdown documents for the no-text-loss suites.
///
/// `documents` must always pass every tier. `pendingFixDocuments` reproduce
/// known text-swallowing bugs — each entry names the fix that graduates it
/// into `documents`; the suites run them with the same assertions, so a fix
/// lands together with its corpus move (red → green).
enum MarkdownTextLossCorpus {
    struct Entry {
        let name: String
        let text: String
        /// True when the text contains `$…$` / `\(…\)` shapes — Tier 3 skips
        /// those because inline math legitimately collapses spans to U+FFFC.
        var containsInlineMathSyntax: Bool {
            text.contains("$") || text.contains("\\(")
        }
    }

    static let documents: [Entry] = [
        Entry(name: "cjkBoldFlanking", text: """
        **新加坡国际仲裁中心（SIAC）**对该裁决具有管辖权。**美国联邦储备委员会（Fed）**的决议显示，\
        通胀压力仍然存在。他**——副标题里的破折号**也要保持加粗。
        """),

        Entry(name: "latinExponents", text: """
        计算 f(x)**2 与 g(y)**3 的差值，再加上 h(z)**4 的修正项。Python 里写作 a**b 表示幂运算。
        """),

        Entry(name: "currencyAndTickers", text: """
        预算在 $100–$200 之间；另外 $5 和 $10 的差价可以忽略。关注 $AAPL、$TSLA 两只股票，\
        以及 100$~200$ 的区间报价。转义写法 \\$50 也常见。
        """),

        Entry(name: "displayMathCleanPair", text: """
        质能方程如下：

        $$
        E = mc^2
        $$

        其中 m 是质量，c 是光速。
        """),

        Entry(name: "displayMathBracketPair", text: """
        积分形式：

        \\[
        \\int_0^1 x^2 \\, dx = \\frac{1}{3}
        \\]

        以上推导完毕。
        """),

        Entry(name: "displayMathSingleLineStandalone", text: """
        下面给出单行公式：

        $$E = mc^2$$

        说明结束。
        """),

        Entry(name: "displayMathUnclosedStreamingTail", text: """
        推导过程：

        $$
        \\int_0^1 x \\, dx
        """),

        Entry(name: "inlineMathSimple", text: """
        当 $x > 0$ 时函数 $f(x) = x^2$ 单调递增，且 \\(g(x) = e^x\\) 恒为正。
        """),

        Entry(name: "escapedEmphasisMultiRun", text: """
        - \\*\\*要点一\\*\\*：说明文字，以及 \\*\\*要点二\\*\\*：补充说明。
        - \\*单星号转义\\* 也应该被还原。
        """),

        Entry(name: "smushedBoldTitleHeading", text: """
        ## 投资分析**核心观点与风险提示**
        正文从这里开始，需要完整保留。
        """),

        Entry(name: "headingCamelIdentifier", text: """
        ## MarkdownRenderPreparation 模块详解
        正文内容在这里继续，描述模块的职责与边界。
        """),

        Entry(name: "cjkEmbeddedHeading", text: """
        前一段总结了整场战役###1.早期阶段的部署与后勤补给情况，需要拆分成标题。
        """),

        Entry(name: "inlineTableGlued", text: """
        下面是对比表：| 维度 | A 方案 | B 方案 | | :--- | :--- | :--- | | 成本 | 低 | 高 |
        """),

        Entry(name: "fencedCodeWithMarkdownChars", text: """
        示例代码：

        ```python
        # 不是标题
        price = "$100"
        bold = "**not bold**"
        path = "C:\\\\Users\\\\test\\\\*.txt"
        $$ = "literal dollars"
        ```

        代码结束后的正文。
        """),

        Entry(name: "inlineCodeWindowsPath", text: """
        路径写作 `C:\\Users\\test\\*.txt`，注意反斜杠；命令是 `grep -- "--flag"`。
        """),

        Entry(name: "healthyDocWithTrailingUnclosedBold", text: """
        ## 季度总结

        本季度营收稳定增长，毛利率维持在合理区间。研发投入持续增加，新产品按计划推进。

        - 营收同比增长 12%
        - 毛利率 38.5%
        - 经营现金流为正

        下季度展望：**重点关注供应链风险
        """),

        Entry(name: "nestedLooseList", text: """
        改造方案分为三步：

        1. 准备阶段

           评估现有架构，列出依赖清单。

           - 盘点 **核心模块** 与 [文档](https://example.com/docs)
           - 标记 `deprecated` 接口

        2. 实施阶段

           按模块逐个迁移，保持双跑。

        3. 验收阶段
        """),

        Entry(name: "taskList", text: """
        发布前检查：

        - [x] 单元测试全绿
        - [ ] 更新 CHANGELOG
        - [ ] 通知相关团队
        """),

        Entry(name: "quoteWithList", text: """
        引用原文如下：

        > 第一段引用文字。
        >
        > - 引用里的列表项一
        > - 引用里的列表项二
        >
        > 引用的结尾段落。
        """),

        Entry(name: "orderedListWideMarkers", text: """
        条款列表（从 95 开始）：

        95. 第九十五条的内容
        96. 第九十六条的内容
        97. 第九十七条的内容
        """),

        Entry(name: "linkHeavy", text: """
        参考 [官方文档](https://example.com/docs?q=1&lang=zh) 与 https://news.example.org/a/b，\
        另见 <https://auto.example.net/path>。
        """),

        Entry(name: "mermaidBlock", text: """
        流程如下：

        ```mermaid
        graph TD
            A[开始] --> B{判断}
            B -->|是| C[结束]
        ```

        图后说明文字。
        """),

        Entry(name: "htmlBlockAndInline", text: """
        正文里有 <b>内联标签</b> 和实体 &amp; 符号。

        <div class="note">
        独立的 HTML 块内容。
        </div>

        结尾段落。
        """),

        Entry(name: "brLineBreaksInTable", text: """
        | 评价维度 | 组合 A | 组合 B |
        | :--- | :--- | :--- |
        | **计算机顶级荣誉** | **ACM SIGOPS Ritchie Award**<br>*(全球 Systems 领域最高奖)* | AMD Spotlight Award、<br>省科技进步特等奖 |
        | 系统 / 架构顶级会议<br>(EuroSys/NSDI/ASPLOS) | 12 篇<br>(EuroSys × 5, NSDI × 3) | 4–5 篇<br>(ASPLOS × 2) |

        表格之外的段落也会出现 <br> 换行，<br/>以及自闭合写法。
        """),

        Entry(name: "thematicBreakGlued", text: """
        上一段落的结尾---### 新的小节
        小节正文内容。
        """),

        Entry(name: "emojiAndVariationSelectors", text: """
        ✅️ 已完成事项 👍，**加粗的表情 🎉 文本**，以及组合 emoji 👨‍👩‍👧‍👦 一家。
        """),

        Entry(name: "strikethroughAndUnderscore", text: """
        ~~已删除的内容~~ 仍要可读；snake_case_identifier 与 __双下划线__ 共存。
        """),

        Entry(name: "kitchenSink", text: """
        # 综合示例

        段落一包含 **加粗**、*斜体*、`code` 与 [链接](https://example.com)。

        ## 数据表

        | 指标 | 数值 |
        | :--- | ---: |
        | 收入 | 1,234 |
        | 成本 | 567 |

        > 引用：注意 **引用里的加粗（带括号）**对齐问题。

        1. 第一步
        2. 第二步

        ```swift
        let value = compute(input: "**raw**")
        ```

        ---

        结尾段落。
        """),

        Entry(name: "longCJKDocumentOver4000", text: Self.longCJKDocument),

        // Graduated by the display-math delimiter unification.
        Entry(name: "displayMathOrphanCloser", text: """
        前文段落需要保留。

        $$E = mc^2
        $$

        这一段以及下面的标题不能消失。

        ## 后续标题

        收尾句子也要在。
        """),

        Entry(name: "displayMathCloserWithContent", text: """
        $$
        E = mc^2 $$

        后文不能被吞，包括这句话。

        ## 后续小节

        小节正文。
        """),

        Entry(name: "displayMathCloserWithLeadingProseRemainder", text: """
        $$
        E = mc^2
        $$结论写在闭合符后面。

        正文继续。
        """),

        // Graduated by removing `.parseBlockDirectives` from the parse options.
        Entry(name: "atPrefixedProse", text: """
        响应式样式写法：

        @media (max-width: 600px) { display: none; }

        上面的 CSS 片段必须原样可见。
        """),
    ]

    /// Known-lossy reproductions. Each names the fix that moves it up.
    static let pendingFixDocuments: [Entry] = []

    static var allDocuments: [Entry] { documents + pendingFixDocuments }

    // MARK: - Long document (> 4000 characters, exercises the plain streaming path)

    private static let longCJKDocument: String = {
        var sections: [String] = ["# 大规模分布式系统设计综述\n"]
        for index in 1...14 {
            sections.append("""
            ## 第 \(index) 章：一致性与可用性的权衡

            在大规模分布式系统中，**一致性（Consistency）**、可用性（Availability）与分区容忍性\
            （Partition tolerance）之间的权衡是设计的核心命题。工程实践中常见的做法是按业务语义\
            分级：交易链路选择强一致，读多写少的旁路场景选择最终一致。第 \(index) 章给出的参考实现\
            使用了租约（lease）机制与多数派写入，配合 `quorum = n/2 + 1` 的读写约束。

            - 写路径：客户端 → 协调者 → 多数派副本，超时 \(100 + index) ms 重试
            - 读路径：本地副本优先，落后超过阈值时触发 read-repair
            - 故障检测：phi-accrual，阈值 \(8 + index % 3)

            > 注意：**跨机房复制（geo-replication）**的延迟尾部通常由慢盘与 GC 停顿主导，\
            > 而不是网络本身。

            ```text
            replica_set_\(index): [node-a, node-b, node-c]
            commit_index: \(1000 + index * 7)
            ```
            """)
        }
        return sections.joined(separator: "\n")
    }()
}
