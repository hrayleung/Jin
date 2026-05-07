import SwiftUI

struct JinSettingsSheetFooter<Details: View>: View {
    let draftError: String?
    let showsDetailsWhenError: Bool
    private let details: () -> Details

    init(
        draftError: String?,
        showsDetailsWhenError: Bool = true,
        @ViewBuilder details: @escaping () -> Details
    ) {
        self.draftError = draftError
        self.showsDetailsWhenError = showsDetailsWhenError
        self.details = details
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JinSpacing.medium) {
            if let draftError {
                JinSettingsFooterError(text: draftError)
            }

            if shouldShowDetails {
                JinDetailsDisclosure {
                    details()
                }
            }
        }
    }

    private var shouldShowDetails: Bool {
        draftError == nil || showsDetailsWhenError
    }
}

struct JinSettingsFooterError: View {
    let text: String

    var body: some View {
        Text(text)
            .jinInlineErrorText()
            .padding(.horizontal, JinSpacing.small)
            .jinSurface(.subtleStrong, cornerRadius: JinRadius.small)
    }
}

struct JinSettingsFooterText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
