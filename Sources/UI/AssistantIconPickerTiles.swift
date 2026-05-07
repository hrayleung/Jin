import AppKit
import SwiftUI

struct AssistantSFSymbolPickerTile: View {
    private static let tileSide: CGFloat = 44
    private static let symbolPointSize: CGFloat = 19

    let symbolName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil {
                    Image(systemName: symbolName)
                        .font(.system(size: Self.symbolPointSize, weight: .medium))
                        .imageScale(.medium)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                } else {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: Self.symbolPointSize, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: Self.tileSide, height: Self.tileSide)
            .jinSurface(isSelected ? .selected : .neutral, cornerRadius: JinRadius.medium)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct AssistantEmojiPickerRow: View, Equatable {
    private static let placeholderHeight: CGFloat = 40

    let emojis: [String]
    let selectedEmoji: String
    let columnCount: Int
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: JinSpacing.small) {
            ForEach(0..<columnCount, id: \.self) { index in
                Group {
                    if index < emojis.count {
                        let emoji = emojis[index]
                        AssistantEmojiPickerTile(
                            emoji: emoji,
                            isSelected: selectedEmoji == emoji
                        ) {
                            onSelect(emoji)
                        }
                    } else {
                        Color.clear
                            .frame(height: Self.placeholderHeight)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    static func == (lhs: AssistantEmojiPickerRow, rhs: AssistantEmojiPickerRow) -> Bool {
        lhs.emojis == rhs.emojis &&
        lhs.columnCount == rhs.columnCount &&
        lhs.selectionState == rhs.selectionState
    }

    private var selectionState: String? {
        emojis.contains(selectedEmoji) ? selectedEmoji : nil
    }
}

private struct AssistantEmojiPickerTile: View, Equatable {
    private static let tileSide: CGFloat = 40
    private static let fontSize: CGFloat = 25

    let emoji: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(emoji)
                    .font(.system(size: Self.fontSize))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
            }
            .frame(width: Self.tileSide, height: Self.tileSide)
            .jinSurface(isSelected ? .selected : .neutral, cornerRadius: JinRadius.medium)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    static func == (lhs: AssistantEmojiPickerTile, rhs: AssistantEmojiPickerTile) -> Bool {
        lhs.emoji == rhs.emoji && lhs.isSelected == rhs.isSelected
    }
}
