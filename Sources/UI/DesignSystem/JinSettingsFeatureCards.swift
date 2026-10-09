import SwiftUI

struct JinSettingsFeatureToggleCard<AccessoryTags: View>: View {
    let title: String
    let toggleTitle: String
    @Binding var isEnabled: Bool
    private let accessoryTags: () -> AccessoryTags

    init(
        title: String = "Basics",
        toggleTitle: String,
        isEnabled: Binding<Bool>,
        @ViewBuilder accessoryTags: @escaping () -> AccessoryTags
    ) {
        self.title = title
        self.toggleTitle = toggleTitle
        _isEnabled = isEnabled
        self.accessoryTags = accessoryTags
    }

    var body: some View {
        JinSettingsCard {
            if title != "Basics" {
                Text(title)
                    .font(.headline)
            }

            HStack {
                Text(toggleTitle)
                Spacer(minLength: 16)
                Toggle(toggleTitle, isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            accessoryTags()
        }
    }
}

extension JinSettingsFeatureToggleCard where AccessoryTags == EmptyView {
    init(
        title: String = "Basics",
        toggleTitle: String,
        isEnabled: Binding<Bool>
    ) {
        self.init(
            title: title,
            toggleTitle: toggleTitle,
            isEnabled: isEnabled
        ) {
            EmptyView()
        }
    }
}
