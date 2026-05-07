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
            HStack(alignment: .center, spacing: JinSpacing.small) {
                Text(title)
                    .font(.headline)

                Spacer()

                Text(isEnabled ? "On" : "Off")
                    .jinTagStyle(foreground: isEnabled ? .accentColor : .secondary)

                accessoryTags()
            }

            Toggle(toggleTitle, isOn: $isEnabled)
                .toggleStyle(.switch)
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
