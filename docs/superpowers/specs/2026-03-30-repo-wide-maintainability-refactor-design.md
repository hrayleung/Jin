# Repo-wide Maintainability Refactor Design

**Date:** 2026-03-30  
**Status:** Draft approved in conversation, written for review  
**Requested by:** User  
**Primary goal:** Aggressively decompose large files across the Jin codebase to improve clarity, local reasoning, and long-term maintainability while preserving user-visible behavior.

---

## 1. Outcome

Refactor the repository in broad, repo-wide waves rather than a single blind sweep. The refactor will aggressively reshape internal boundaries and internal APIs, but it will not intentionally change user-visible behavior.

The chosen strategy is **domain waves**:

1. **UI/state wave**
2. **Adapters/networking wave**
3. **Persistence/tooling wave**

Each wave follows the same structural pattern:

- keep current entry points stable first
- extract focused collaborators behind those entry points
- migrate logic into the new collaborators
- reduce the original large file into a thin façade or coordinator
- prove behavior parity with targeted tests before moving on

This gives the codebase smaller, more understandable units without turning the refactor into a high-risk rewrite.

---

## 2. Goals and Non-goals

### Goals

- Break up oversized files with mixed responsibilities.
- Make file ownership and responsibility obvious at a glance.
- Improve testability by separating pure logic from orchestration and UI shells.
- Reduce cascade risk by giving each subsystem clearer seams.
- Preserve the app’s current behavior and user flows.
- Use agents aggressively, but only on non-overlapping file clusters.

### Non-goals

- No intentional feature redesign or user-facing workflow changes.
- No large architecture rewrite for its own sake.
- No new framework or pattern migration unless required by the refactor.
- No speculative domain reorganization unrelated to the identified hotspots.
- No broad “rename everything” pass without clear responsibility wins.

---

## 3. Codebase Findings

Three independent audit passes converged on the same maintainability hotspots.

### 3.1 UI/state hotspots

Highest-priority UI/state files include:

- `Sources/UI/ChatControlMenuViews.swift`
- `Sources/UI/ChatMessageStageViews.swift`
- `Sources/UI/ChatMessageRenderPipeline.swift`
- `Sources/UI/ChatView+ControlNormalization.swift`
- `Sources/UI/ChatView+Streaming.swift`
- closely related consumers such as `Sources/UI/MessageRowView.swift`

Observed problems:

- rendering policy, layout logic, and view composition are mixed together
- control validation and capability resolution are mixed with view state handling
- streaming lifecycle logic is spread across callbacks and extensions
- menu infrastructure is repeated inside large files instead of being composed from smaller pieces

### 3.2 Adapter/networking hotspots

Highest-priority adapter/networking files include:

- `Sources/Adapters/VertexAIAdapter.swift`
- `Sources/Adapters/AnthropicAdapter.swift`
- `Sources/Adapters/OpenAIWebSocketAdapter.swift`
- `Sources/Adapters/OpenAIChatCompletionsCore.swift`
- `Sources/Adapters/ResponsesAPITypes.swift`
- related networking helpers such as `Sources/Networking/CloudflareR2Uploader.swift`

Observed problems:

- adapters mix orchestration, auth, request building, feature checks, and parsing
- stream state machines live beside higher-level adapter coordination
- provider-specific normalization logic is often embedded in adapter entry files
- wire types and business logic are sometimes combined in the same file

### 3.3 Persistence/tooling hotspots

Highest-priority persistence/tooling files include:

- `Sources/Persistence/AppSnapshotManager.swift`
- `Sources/Persistence/SwiftDataModels.swift`
- `Sources/Tools/AgentToolHub.swift`
- `Sources/Tools/BuiltinSearchProviders.swift`
- `Sources/Tools/RTKRuntimeSupport.swift`

Observed problems:

- snapshot capture, validation, restore, and file operations live together
- many SwiftData entities are co-located in one large file
- tool definition, routing, validation, and execution concerns are blended
- runtime setup and provider-specific behavior are not cleanly isolated

---

## 4. Refactor Architecture

### 4.1 Global refactor rules

Every extraction in every wave follows these rules:

1. **Behavior-preserving at the user level.** Internal APIs may change aggressively; user-visible behavior should not.
2. **Entry points stay stable first.** The original file remains the initial integration shell while logic moves outward.
3. **Pure logic moves first.** Parsing, validation, transformation, capability checks, and policy logic are extracted before orchestration code.
4. **Coordinators stay thin.** After extraction, the original large file becomes a façade, coordinator, or actor shell.
5. **Responsibility over technical purity.** Files are split by what they do, not merely by whether they are a view, model, or helper.
6. **Smaller but not fragmented.** Preferred target size is roughly 150–300 LOC, with a soft ceiling around 400 LOC unless a single type genuinely needs more.
7. **Cross-layer touch is allowed only when it clarifies a seam.** Related `Sources/Domain/` support may be adjusted when needed, but there is no separate domain-only rewrite wave.

### 4.2 Wave 1 — UI/state

The UI/state wave focuses on separating rendering policy, rendering data preparation, menu composition, control normalization, and streaming lifecycle state.

Planned boundaries:

- `ChatMessageRenderPipeline.swift` becomes a coordinator over smaller render-building units, such as a decoder/build stage and payload-estimation heuristics.
- `ChatMessageStageViews.swift` splits rendering policy and layout/timeline behavior out of view-heavy composition code.
- `ChatControlMenuViews.swift` splits into smaller menu-specific view files plus any shared menu infrastructure.
- `ChatView+ControlNormalization.swift` moves validation and capability-resolution logic into focused service-style helpers.
- `ChatView+Streaming.swift` moves send/stream lifecycle state into a thinner orchestration layer backed by focused collaborators or state containers.

Expected result:

- clearer UI file ownership
- less duplicated decision logic
- easier targeted tests for rendering and control behavior
- fewer ChatView extension files acting as mixed-responsibility buckets

### 4.3 Wave 2 — Adapters/networking

The adapter/networking wave isolates provider auth, request shaping, feature resolution, event parsing, and wire-format handling.

Planned boundaries:

- `VertexAIAdapter.swift` separates token/auth handling, request building, cached-content operations, and stream parsing.
- `AnthropicAdapter.swift` separates request-building and provider-specific normalization from actor-level orchestration.
- `OpenAIWebSocketAdapter.swift` separates websocket event handling and response lifecycle parsing from transport orchestration.
- `OpenAIChatCompletionsCore.swift` separates decode/orchestration from stream transformation and accumulation logic.
- `ResponsesAPITypes.swift` retains pure wire types while business/UI-oriented interpretation moves elsewhere.

Expected result:

- adapters become readable coordination shells
- request/response logic becomes easier to unit test in isolation
- provider-specific quirks become easier to audit
- streaming bugs become more local to the parser/handler layer

### 4.4 Wave 3 — Persistence/tooling

The persistence/tooling wave separates data schema, snapshot lifecycle, tool routing, and runtime/provider setup.

Planned boundaries:

- `AppSnapshotManager.swift` splits snapshot codec, validation, directory/file operations, and restore/rollback behavior.
- `SwiftDataModels.swift` splits entity definitions into focused files while keeping shared schema/migration declarations in a dedicated schema file.
- `AgentToolHub.swift` separates tool definitions, routing, and concrete execution concerns.
- `BuiltinSearchProviders.swift` separates providers from selection/factory logic.
- `RTKRuntimeSupport.swift` separates environment building, initialization, and tool/runtime registration.

Expected result:

- storage and recovery code becomes easier to reason about safely
- entity files align better with the repo’s “one primary type per file” guidance
- tool runtime changes stop cascading through a single hub file
- MCP/runtime support becomes less opaque

---

## 5. Execution Model

The user explicitly requested agent-driven execution, so the implementation should use agents heavily, but with strict isolation.

### 5.1 Agent structure

- One coordinator owns the wave plan and review checkpoints.
- Worker agents receive **non-overlapping file clusters**.
- Worker agents do not edit the same files concurrently.
- For broad investigation, read-only scout/research agents may run in parallel.
- For code changes, each worker should operate in an isolated branch or worktree context when practical.

### 5.2 Unit of work

A worker should receive a small, bounded cluster such as:

- one large file plus its immediate extracted collaborators
- one parser/request-builder split
- one snapshot sub-area
- one menu/render-policy decomposition

Each unit should be independently understandable, independently testable, and independently reviewable.

### 5.3 Standard refactor sequence per cluster

1. Establish the existing behavior and relevant tests.
2. Add or tighten regression tests for the seam being extracted.
3. Extract pure logic/helpers first.
4. Introduce the new collaborator or focused type.
5. Migrate call sites.
6. Reduce the original file to a thin façade/coordinator.
7. Run targeted verification.
8. Only then move to the next cluster.

This preserves momentum without turning the whole repo into a single unstable in-flight refactor.

---

## 6. Verification Strategy

### 6.1 Baseline policy

Before each wave begins:

- identify the subsystem’s guarding tests
- run those tests to establish a known baseline
- note any missing seam-specific coverage that should be added first

### 6.2 Refactor-specific guardrails

UI/state work should be guarded by tests around:

- chat render pipeline behavior
- artifact extraction
- rendering heuristics
- streaming orchestration
- control normalization

Adapter/networking work should be guarded by tests around:

- request construction
- model capability resolution
- stream parsing and event ordering
- adapter integration behavior

Persistence/tooling work should be guarded by tests around:

- snapshot capture and restore behavior
- entity/domain mapping and serialization
- tool routing/execution boundaries
- MCP/runtime setup behavior

### 6.3 Required verification checkpoints

- **Per cluster:** run the targeted tests that cover the touched seam.
- **Per wave:** run `swift test`.
- **At the end of the full refactor:** run both:
  - `swift test`
  - `bash Packaging/package.sh`

This matches repository guidance and keeps confidence high as the refactor fans out.

---

## 7. Risks and Mitigations

### Risk 1: Parallel agents collide on the same subsystem

**Mitigation:** assign non-overlapping file clusters only; keep one coordinator responsible for reservations and sequencing.

### Risk 2: Extracted helpers become artificial indirection

**Mitigation:** split only when a new file has a crisp responsibility and a stable interface. Avoid “Utils.swift” dumping grounds.

### Risk 3: Behavior drifts during large UI decompositions

**Mitigation:** preserve current entry points first, add seam-focused regression tests, and keep rendering policy logic explicit.

### Risk 4: Provider adapters drift in capability behavior

**Mitigation:** guard with exact request/capability tests and keep provider-specific logic close to provider-specific files after extraction.

### Risk 5: Snapshot or persistence refactors introduce recovery regressions

**Mitigation:** isolate codec/validation/restore concerns incrementally and retain end-to-end recovery tests before any deeper cleanup.

---

## 8. Success Criteria

The refactor is successful when:

- the current large hotspot files are decomposed into smaller, responsibility-focused units
- original façade files are materially thinner and easier to read
- targeted regression coverage exists for extracted seams
- `swift test` passes after each wave and at the end of the full effort
- `bash Packaging/package.sh` succeeds at the end of the implementation
- developers can locate rendering, streaming, adapter parsing, snapshot, and tool-routing behavior without reading a monolithic file

---

## 9. Recommended Implementation Order

1. Start with **UI/state**, because it contains the densest user-facing logic and the most obvious oversized files.
2. Move to **adapters/networking**, where decomposition can happen cleanly once UI/state boundaries are clearer.
3. Finish with **persistence/tooling**, where schema, snapshot, and tool runtime splits can be executed with strong test coverage.

Within each wave, prefer extracting the lowest-risk pure logic first, then parser/validation/state collaborators, and leave broader coordinator thinning for the last step in the cluster.

---

## 10. Handoff Summary

This design intentionally chooses **broad scope with disciplined structure**:

- repo-wide rather than single-file cleanup
- aggressive internal API cleanup rather than cosmetic splitting
- agent-driven execution with strict isolation
- behavior-preserving user experience
- repeated extraction pattern across all waves

The next step is to turn this design into a detailed implementation plan with task-by-task sequencing, file lists, verification commands, and execution strategy.