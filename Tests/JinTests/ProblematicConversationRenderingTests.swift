import AppKit
import SwiftUI
import XCTest
@testable import Jin

@MainActor
final class ProblematicConversationRenderingTests: XCTestCase {
    func testMobiHocNSDIAnswerParsesExpectedTable() {
        let theme = MarkdownTheme.resolved(appFontFamily: "", codeFontFamily: "")
        let key = NativeMarkdownCache.Key(
            markdownText: Self.mobiHocNSDIAnswer,
            isStreaming: false,
            renderPlainText: false,
            appFontFamily: "",
            codeFontFamily: ""
        )

        let parsed = NativeMarkdownCache.compute(key: key, theme: theme)

        let tableGroups = parsed.groups.compactMap { group -> (header: [InlineRun], rows: [[InlineRun]])? in
            guard case let .table(header, alignments, rows, _) = group else { return nil }
            XCTAssertEqual(alignments.count, header.count)
            return (header, rows)
        }
        XCTAssertEqual(tableGroups.count, 1)
        XCTAssertEqual(tableGroups.first?.header.map { $0.plainText }, ["维度", "MobiHoc", "NSDI"])
        XCTAssertEqual(tableGroups.first?.rows.count, 5)
    }

    func testMobiHocNSDIAnswerLayoutCompletes() {
        let theme = MarkdownTheme.resolved(appFontFamily: "", codeFontFamily: "")
        let key = NativeMarkdownCache.Key(
            markdownText: Self.mobiHocNSDIAnswer,
            isStreaming: false,
            renderPlainText: false,
            appFontFamily: "",
            codeFontFamily: ""
        )
        let parsed = NativeMarkdownCache.compute(key: key, theme: theme)

        let host = NSHostingView(rootView: markdownGroupsView(parsed.groups, theme: theme))
        host.frame = CGRect(x: 0, y: 0, width: 760, height: 1)
        host.layoutSubtreeIfNeeded()

        let size = host.fittingSize
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
        XCTAssertLessThan(size.height, 4_000)
    }

    func testThinkingBlockWithMobiHocNSDIReasoningLayoutCompletes() {
        let previousMode = UserDefaults.standard.string(forKey: AppPreferenceKeys.thinkingBlockDisplayMode)
        UserDefaults.standard.set(ThinkingBlockDisplayMode.expanded.rawValue, forKey: AppPreferenceKeys.thinkingBlockDisplayMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: AppPreferenceKeys.thinkingBlockDisplayMode)
            } else {
                UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.thinkingBlockDisplayMode)
            }
        }

        let host = NSHostingView(rootView: ThinkingBlockView(thinking: ThinkingBlock(text: Self.mobiHocNSDIThinking)))
        host.frame = CGRect(x: 0, y: 0, width: 760, height: 1)
        host.layoutSubtreeIfNeeded()

        let size = host.fittingSize
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
        XCTAssertLessThan(size.height, 2_000)
    }

    func testConstrainedWidthMessageLikeStackLayoutCompletes() {
        let host = NSHostingView(
            rootView: ConstrainedWidth(360) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "network")
                        Text("Assistant")
                        Text("model-preview")
                            .font(.caption2)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(Self.messageLikeLongText)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            Text("Tool")
                            Spacer(minLength: 0)
                            Text("Complete")
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.12)))

                    HStack(spacing: 8) {
                        Text("Copy")
                        Spacer(minLength: 0)
                        Text("2:43 PM")
                    }
                    .padding(.horizontal, 12)
                }
                .layoutValue(key: ConstrainedWidthContentVersionKey.self, value: .version(1))
            }
        )
        host.frame = CGRect(x: 0, y: 0, width: 760, height: 1)
        host.layoutSubtreeIfNeeded()

        let size = host.fittingSize
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
        XCTAssertLessThanOrEqual(size.width, 760)
        XCTAssertLessThan(size.height, 800)
    }

    private func markdownGroupsView(_ groups: [NativeMarkdownGroup], theme: MarkdownTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { offset, group in
                NativeGroupView(group: group, path: [offset])
            }
        }
        .frame(width: 760, alignment: .leading)
        .environment(\.markdownTheme, theme)
    }

    private static let messageLikeLongText = """
    This message exercises the same nested stack shape as a chat row: a compact \
    header, a padded message surface, and a footer with spacers. It is long \
    enough to require wrapping under the constrained bubble width.
    """

    private static let mobiHocNSDIThinking = """
    **Comparing MobiHoc and NSDI**

    I'm currently evaluating MobiHoc and NSDI, two distinct yet valuable conferences. My focus is on understanding their specific contributions to distributed systems and networking research. I'm particularly interested in how their publication scopes and accepted work differ, and what this implies for researchers in these overlapping fields.

    **Analyzing Conference Characteristics**

    My current thinking is focused on dissecting the core attributes of MobiHoc. This involves detailing its full name, its specific research emphasis on mobile and ad hoc networking, and its historical standing within the academic community. I'm also investigating the associated SIG MOBILE, a key aspect of its identity.

    **Comparing Network Conference Themes**

    I'm currently analyzing the core focuses of MobiHoc, particularly its emphasis on mobile ad hoc networks, wireless communication, and mobile computing. This allows me to begin drawing distinctions with other related conferences.

    **Distinguishing Research Trajectories**

    I'm now comparing MobiHoc's broad scope in wireless and mobile networks, including its historical theoretical bent and recent systems expansion, against NSDI's systems-focused, practical evaluation of networked systems. This comparison highlights differences in their core methodologies.

    **Synthesizing Conference Methodologies**

    I'm contrasting MobiHoc's historical strength in theoretical, algorithmic, and simulation-based approaches for wireless and mobile networks with NSDI's firm grounding in practical system design, implementation, and rigorous real-world evaluation for large-scale networked and distributed systems. This highlights their distinct research paradigms.

    **Evaluating Conference Criteria**

    I am now contrasting MobiHoc's typical 15-20% acceptance rate and its focused impact on wireless theory and protocols with NSDI's similarly selective rate, but broader systems impact and hyper-scaler adoption, to understand their community reach.

    **Understanding Community Focus**

    I'm delving into the specific communities each conference serves. MobiHoc is firmly within ACM SIGMOBILE, while NSDI attracts a broader range of systems and networking researchers, influencing production deployments significantly.

    **Identifying Key Distinctions**

    I'm now focusing on the contrasting industry presence and community affiliations. MobiHoc leans academic with some telecom ties, whereas NSDI boasts significant hyperscaler involvement and draws from broader systems research communities.

    **Refining Core Distinctions**

    I'm refining my understanding by comparing MobiHoc's theoretical and algorithmic focus in wireless, versus NSDI's practical systems design and real-world evaluation emphasis. This highlights their distinct research paradigms and impact on industry.

    **Clarifying Academic Tiers**

    I'm now processing the academic prestige, noting NSDI as CCF-A while MobiHoc is CCF-B. This distinction immediately clarifies their differing tiers of influence and recognition within the broader computer science landscape.

    **Guiding Future Submissions**

    I'm now synthesizing the information to provide actionable advice. My focus is on directing research towards NSDI for highly scalable, cloud, or ML systems work, and towards MobiHoc for theoretical wireless, mobile network optimization, or ad-hoc routing problems, while acknowledging MobiHoc's strong academic standing within the wireless community.
    """

    private static let mobiHocNSDIAnswer = """
    **MobiHoc** 和 **NSDI** 都是计算机网络与通信领域的顶级学术会议，但它们在**学术定位、研究侧重点、方法论以及工业界影响力**上有着非常显著的差异。

    以下从多个维度对这两个会议进行深度对比：

    ---

    ### 1. 基本信息与学术声誉

    | 维度 | MobiHoc | NSDI |
    | :--- | :--- | :--- |
    | **全称** | ACM International Symposium on Theory, Algorithmic Foundations, and Protocol Design for Mobile Networks and Mobile Computing | USENIX Symposium on Networked Systems Design and Implementation |
    | **主办组织** | ACM SIGMOBILE | USENIX（联合 ACM SIGCOMM/SIGOPS） |
    | **CCF 推荐分区** | **CCF-B 类**（网络与通信方向） | **CCF-A 类**（网络与通信方向） |
    | **学术地位** | 移动自组织网络（Ad Hoc）和移动计算领域的**经典高水平会议**，偏重理论与算法。 | 计算机系统与网络领域的**四大顶会之一**（与 SIGCOMM、SOSP、OSDI 并列），含金量极高。 |
    | **录用率** | 通常在 **15% ~ 20%** 左右（竞争非常激烈）。 | 通常在 **15% ~ 20%** 左右（投稿量极大，审稿极严）。 |

    ---

    ### 2. 研究方向与核心议题（Research Scope）

    #### **MobiHoc：聚焦“移动、无线与网络理论”**
    MobiHoc 最初专注于移动自组织网络（Ad Hoc）和传感器网络，近年来其范围已扩展到下一代无线网络、移动计算和动态网络系统。
    *   **核心主题**：5G/6G 蜂窝网络、Open-RAN、通感一体化（ISAC）、毫米波/太赫兹通信、可重构智能表面（RIS）、物联网（IoT）、移动边缘计算（MEC）、无线网络中的联邦学习等。
    *   **研究对象**：通常是**无线链路、移动节点、拓扑动态变化的网络**。

    #### **NSDI：聚焦“大规模网络系统设计与实现”**
    NSDI 的核心是 **“System”（系统）**。它关注如何设计、实现和评估大规模的、实用的网络化和分布式系统。
    *   **核心主题**：数据中心网络（Datacenter Networks）、云基础设施、软件定义网络（SDN）、RDMA/智能网卡（SmartNIC）、分布式存储、大模型（LLM）分布式训练与推理系统（如 GPU 集群网络优化）、网络虚拟化等。
    *   **研究对象**：通常是**有线网络、大规模分布式系统、云平台、数据中心**。

    ---

    ### 3. 研究方法论（Methodology）的差异

    这是两者最本质的区别：

    *   **MobiHoc 偏向“理论、算法与数学建模”**：
        *   MobiHoc 非常看重**理论深度**。论文中常见排队论、博弈论、李雅普诺夫优化（Lyapunov Optimization）、凸优化、图论等数学工具。
        *   虽然近年来 MobiHoc 也开始接收系统和实验类论文，但其主流依然偏向于通过数学建模、算法设计和网络仿真（如 ns-3）来解决无线网络中的资源分配、路由和调度问题。
    *   **NSDI 严格遵循“Design and Implementation”（设计与实现）**：
        *   NSDI 是一门**硬核系统课**。论文必须包含一个**真实构建的系统（Working System）**，并进行大规模的真实部署或原型评估。
        *   NSDI 几乎不接收纯理论、纯数学推导或仅靠简单仿真的论文。它要求作者说清楚“系统是如何解决实际工程瓶颈的”，并提供详实的实验数据（如吞吐量、延迟、CPU/GPU 开销等）。

    ---

    ### 4. 工业界影响力与社区生态

    *   **MobiHoc 的社区**：
        *   主要由学术界（尤其是无线通信、网络优化、移动计算领域的学者）和部分电信巨头（如高通、爱立信、华为等无线研究部门）组成。
        *   研究成果偏向于前沿探索和理论奠基，距离真正的工业界大规模落地通常有一定距离。
    *   **NSDI 的社区**：
        *   由顶尖学术界与头部互联网/云计算巨头（如 Google、Meta、微软、阿里、字节跳动等）共同主导。
        *   NSDI 上的很多论文直接来自于这些巨头的实际生产系统（例如 Google 的 TPU 集群网络、字节跳动的大模型训练网络优化等）。其研究成果往往能直接推动工业界下一代数据中心和云架构的变革。

    ---

    ### 总结：我该投哪一个？

    *   **选择投 MobiHoc 的情况**：
        *   你的研究背景是**无线通信、移动计算或物联网**。
        *   你的论文核心贡献是**算法设计、数学证明、网络建模或协议优化**（例如：设计了一个无线边缘计算的在线调度算法，并证明了其竞争比）。
        *   你没有条件搭建大规模的真实物理系统，主要依赖仿真（Simulation）来验证想法。
    *   **选择投 NSDI 的情况**：
        *   你的研究背景是**计算机系统、分布式系统、云计算或网络架构**。
        *   你**亲手实现了一个系统原型**（写了成千上万行代码），并在真实测试床（Testbed）或真实网络环境中进行了评测。
        *   你的工作解决了大规模网络系统中的实际痛点（例如：如何让 10000 张 GPU 在大模型训练时的网络通信效率提升 30%）。
    """
}
