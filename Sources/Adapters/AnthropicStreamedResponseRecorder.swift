import Foundation

/// Rebuilds one streamed Messages API response the way the official SDK accumulators do, so a
/// `pause_turn` response can be sent back as-is.
///
/// `parseJSONLine` maps events onto Jin's UI model and keeps only what the timeline shows: it
/// merges consecutive thinking blocks and drops `server_tool_use` / `web_search_tool_result`
/// blocks (with their `encrypted_content`). A paused turn can only be resumed with the exact
/// blocks the API returned, so this records them as raw JSON alongside the parser.
struct AnthropicStreamedResponseRecorder {
    private var blocksByIndex: [Int: [String: Any]] = [:]
    private var partialInputJSONByIndex: [Int: String] = [:]
    private(set) var stopReason: String?
    /// The code execution container the response ran in. Each request otherwise gets a new
    /// container, so a resumed turn would lose the files it created before the pause.
    private(set) var containerID: String?

    /// Content blocks in response order.
    var content: [[String: Any]] {
        blocksByIndex.keys.sorted().compactMap { blocksByIndex[$0] }
    }

    mutating func record(_ line: String) {
        guard let data = line.data(using: .utf8),
              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = event["type"] as? String else {
            return
        }

        switch type {
        case "message_start":
            captureContainer((event["message"] as? [String: Any])?["container"])

        case "content_block_start":
            guard let index = event["index"] as? Int,
                  let block = event["content_block"] as? [String: Any] else { return }
            blocksByIndex[index] = block

        case "content_block_delta":
            guard let index = event["index"] as? Int,
                  let delta = event["delta"] as? [String: Any] else { return }
            applyDelta(delta, at: index)

        case "content_block_stop":
            guard let index = event["index"] as? Int else { return }
            finishToolInput(at: index)

        case "message_delta":
            guard let delta = event["delta"] as? [String: Any] else { return }
            if let reason = delta["stop_reason"] as? String {
                stopReason = reason
            }
            captureContainer(delta["container"])

        default:
            break
        }
    }

    private mutating func applyDelta(_ delta: [String: Any], at index: Int) {
        guard var block = blocksByIndex[index] else { return }

        switch delta["type"] as? String {
        case "text_delta":
            block["text"] = ((block["text"] as? String) ?? "") + ((delta["text"] as? String) ?? "")
        case "thinking_delta":
            block["thinking"] = ((block["thinking"] as? String) ?? "") + ((delta["thinking"] as? String) ?? "")
        case "signature_delta":
            // The SDKs assign rather than append: the block opens with `"signature": ""`.
            block["signature"] = delta["signature"]
        case "citations_delta":
            guard let citation = delta["citation"] else { return }
            var citations = (block["citations"] as? [Any]) ?? []
            citations.append(citation)
            block["citations"] = citations
        case "input_json_delta":
            partialInputJSONByIndex[index, default: ""] += (delta["partial_json"] as? String) ?? ""
            return
        default:
            return
        }

        blocksByIndex[index] = block
    }

    /// `tool_use` / `server_tool_use` input streams as partial JSON strings; the block's
    /// `input` is only an object again once the block closes.
    private mutating func finishToolInput(at index: Int) {
        guard let json = partialInputJSONByIndex.removeValue(forKey: index),
              !json.isEmpty,
              let data = json.data(using: .utf8),
              let input = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var block = blocksByIndex[index] else {
            return
        }
        block["input"] = input
        blocksByIndex[index] = block
    }

    private mutating func captureContainer(_ value: Any?) {
        if let id = (value as? [String: Any])?["id"] as? String, !id.isEmpty {
            containerID = id
        }
    }
}
