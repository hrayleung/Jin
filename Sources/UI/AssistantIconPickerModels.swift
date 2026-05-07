import Foundation

struct AssistantIconCategory: Identifiable {
    let name: String
    let icons: [String]

    var id: String { name }
}

enum AssistantIconPickerTab: String, CaseIterable {
    case sfSymbols = "SF Symbols"
    case emoji = "Emoji"
}

struct AssistantEmojiRow: Identifiable, Equatable {
    let id: String
    let emojis: [String]
}

enum AssistantEmojiDisplayItem: Identifiable, Equatable {
    case header(String)
    case row(AssistantEmojiRow)

    var id: String {
        switch self {
        case .header(let title):
            return "header:\(title)"
        case .row(let row):
            return row.id
        }
    }
}

enum AssistantIconPickerOptions {
    static let symbolColumnCount = 6
    static let emojiColumnCount = 8

    static let iconOptions: [AssistantIconCategory] = [
        AssistantIconCategory(
            name: "Characters",
            icons: ["person.crop.circle", "person.fill", "person.2.fill", "figure.wave", "sparkles", "star.fill", "heart.fill", "face.smiling", "crown.fill", "moon.stars.fill"]
        ),
        AssistantIconCategory(
            name: "Technology",
            icons: ["laptopcomputer", "desktopcomputer", "iphone", "applewatch", "brain", "cpu", "antenna.radiowaves.left.and.right", "waveform", "bolt.fill", "lightbulb.fill"]
        ),
        AssistantIconCategory(
            name: "Communication",
            icons: ["bubble.left.and.bubble.right", "message.fill", "envelope.fill", "phone.fill", "video.fill", "mic.fill", "speaker.wave.3.fill", "quote.bubble", "megaphone.fill", "bell.fill"]
        ),
        AssistantIconCategory(
            name: "Creative",
            icons: ["paintbrush.fill", "pencil", "pencil.and.outline", "book.fill", "doc.text.fill", "photo.fill", "music.note", "film", "camera.fill", "theatermasks.fill"]
        ),
        AssistantIconCategory(
            name: "Business",
            icons: ["briefcase.fill", "chart.line.uptrend.xyaxis", "dollarsign.circle.fill", "building.2.fill", "cart.fill", "creditcard.fill", "paperplane.fill", "folder.fill", "calendar", "clock.fill"]
        ),
        AssistantIconCategory(
            name: "Science",
            icons: ["graduationcap.fill", "atom", "flask.fill", "testtube.2", "leaf.fill", "globe", "pawprint.fill", "microbe.fill", "fossil.shell.fill", "mountain.2.fill"]
        )
    ]
}
