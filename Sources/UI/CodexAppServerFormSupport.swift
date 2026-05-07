import SwiftUI

@MainActor
enum CodexAppServerFormSupport {
    enum StatusTone: Equatable {
        case success
        case warning
        case neutral
        case failure

        var color: Color {
            switch self {
            case .success:
                return .green
            case .warning:
                return .orange
            case .neutral:
                return .secondary
            case .failure:
                return .red
            }
        }
    }

    struct StatusPresentation: Equatable {
        let label: String
        let tone: StatusTone
        let message: String
    }

    struct ButtonState: Equatable {
        let startDisabled: Bool
        let stopDisabled: Bool
        let forceStopDisabled: Bool
    }

    struct AuthButtonState: Equatable {
        let connectDisabled: Bool
        let refreshDisabled: Bool
        let logoutDisabled: Bool
    }

    struct LocalAuthPresentation: Equatable {
        let label: String
        let tone: StatusTone
        let message: String
        let missingKeyMessage: String?
    }
}
