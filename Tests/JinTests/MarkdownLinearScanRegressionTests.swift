import XCTest
@testable import Jin

final class MarkdownLinearScanRegressionTests: XCTestCase {
    func testReportedCJKHeadingListAndTableAnswerParsesPromptly() async {
        let input = """
        **有的，而且现在远程 IDE 已经卷得很成熟了。 **

        B 这种「多台服务器天天直接 SSH 上去改分布式状态机（还是 Scala）」的场景，其实**完全有合适的 IDE**，只是他选择了 nvim 而已。下面按「真正能用、不拖后腿」的标准给你排个序：

        ### 1. 最推荐给 B 这种人的：VS Code Remote - SSH + Metals（Scala）
        - **体验**：本地 VS Code 界面，代码、终端、Git、调试全在远程服务器上跑。
        - 多台服务器？直接加多个 SSH target，一键切换，跟 tmux 跳 session 一样快。
        - Scala 支持：Metals 插件现在已经非常强（语义高亮、跳转、重构、调试都丝滑）。
        - 资源：本地几乎不吃内存，所有编译/索引都在服务器上。
        - lazygit 也能直接在 VS Code 集成终端里用。
        - **很多人从 nvim 切过来后就回不去了**，尤其是要看复杂 call hierarchy 或 debug 状态机的时候。

        ### 2. JetBrains 官方远程方案（Gateway / Remote Development）
        - CLion / IntelliJ / Fleet 都支持。
        - 2023 年后已经很好用了：本地只跑 UI，后端（索引、编译、调试）全在服务器。
        - 对 Scala：IntelliJ 的 Scala 插件依然是业界最强（比 Metals 还强一点，尤其是隐式、类型推断）。
        - 多机：可以同时连多台，或者用 Gateway 管理。
        - **缺点**：还是比 VS Code 重一点，启动和同步偶尔会卡（尤其是超大 monorepo）。
        - 但如果你需要强力重构、数据库工具、HTTP client 这些，它完胜。

        ### 3. 纯终端党进阶版（B 现在用的升级）
        - nvim + remote LSP（已经在用）
        - 再加 **nvim-remote** 或 **distant.nvim**，可以直接把本地 nvim 变成「远程 IDE 前端」。
        - 或者用 **Helix** / **Zed**（Zed 的 remote 也在快速完善）。

        ### 4. 云 IDE（不太适合 B）
        - GitHub Codespaces、Gitpod、Cursor Remote：更适合「从零拉仓库」，不适合「已经在跑的多台生产/测试服务器上直接改」。

        ### 真实对比（针对 B 的场景）

        | 方案                  | 多机切换速度 | Scala 支持 | 资源占用 | 调试状态机 | 学习成本 | B 会不会用？ |
        |-----------------------|--------------|------------|----------|------------|----------|--------------|
        | **nvim + lazygit**    | ★★★★★        | ★★★★       | 极低     | 靠日志     | 已精通   | 正在用       |
        | **VS Code Remote-SSH**| ★★★★★        | ★★★★★      | 低       | 图形化断点 | 极低     | 很可能会     |
        | **JetBrains Gateway** | ★★★★         | ★★★★★      | 中       | 最强       | 低       | 可能嫌重     |
        | 本地 IDE + 同步       | ★★           | ★★★★★      | 高       | 强         | -        | 绝对不用     |

        **结论：**
        - 有！而且 **VS Code Remote-SSH + Metals** 几乎是为 B 这种人量身定做的。
        - 很多和 B 一样的分布式/Scala 大佬，现在都是「nvim 写小改动 + VS Code Remote 做复杂调试/重构」双修。
        - B 坚持纯 nvim，更多是**信仰 + 极致效率**，不是「没有合适的 IDE」。

        如果你也是这种多机服务器 coding 的，我强烈建议先试一下 VS Code Remote-SSH，5 分钟就能连上，体验会让你重新思考「要不要彻底抛弃 IDE」。

        要不要我直接给你一套「Scala + 多服务器」的 VS Code Remote 最佳配置？
        """
        let theme = await MainActor.run {
            MarkdownTheme.resolved(appFontFamily: "", codeFontFamily: "")
        }
        let key = NativeMarkdownCache.Key(
            markdownText: input,
            isStreaming: false,
            renderPlainText: false,
            appFontFamily: "",
            codeFontFamily: ""
        )

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            let value = NativeMarkdownCache.compute(key: key, theme: theme)
            XCTAssertFalse(value.blocks.isEmpty)
            XCTAssertTrue(value.blocks.contains { block in
                if case .table = block { return true }
                return false
            })
        }

        XCTAssertLessThan(elapsed, .seconds(1))
    }

    func testMalformedDelimiterHeavyInputStaysBoundedAndLossless() {
        // Every backtick run has a unique length, so none can close another.
        // This is the adversarial shape that previously rescanned the complete
        // suffix once per opener in both preservation and tokenization.
        let backticks = (1...450)
            .map { String(repeating: "`", count: $0) }
            .joined(separator: "x")
        let strayDollars = String(repeating: "$a ", count: 4_000)
        let input = backticks + "\n" + strayDollars

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            let preserved = MarkdownRenderPreparation.preserveInlineCode(in: input) { $0 }
            XCTAssertEqual(preserved, input)
            _ = MarkdownInlineTokenizer.tokenize(input)
            let mathSegments = InlineMath.split(strayDollars)
            XCTAssertEqual(mathSegments, [.text(strayDollars)])
        }

        XCTAssertLessThan(elapsed, .seconds(3))
    }

    func testRegexReplacementWalksProtectedRangesInSourceOrder() {
        let input = Array(repeating: "*protected* - replace", count: 4_000)
            .joined(separator: "\n")
        let protectedRanges = MarkdownInlineTokenizer.emphasisRanges(in: input)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            let result = MarkdownRenderPreparation.replacingOutsideRanges(
                pattern: "-",
                in: input,
                protectedRanges: protectedRanges,
                with: "+"
            )
            XCTAssertEqual(result.filter { $0 == "+" }.count, 4_000)
            XCTAssertEqual(result.filter { $0 == "*" }.count, 8_000)
        }

        XCTAssertLessThan(elapsed, .seconds(3))
    }
}
