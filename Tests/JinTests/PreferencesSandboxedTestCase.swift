import Foundation
import XCTest

class PreferencesSandboxedTestCase: XCTestCase {
    private var previousHome: String?
    private var temporaryHome: URL?

    override func setUpWithError() throws {
        try super.setUpWithError()

        previousHome = ProcessInfo.processInfo.environment["HOME"]
        let temporaryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("jin-preferences-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryHome.appendingPathComponent("Library/Preferences", isDirectory: true),
            withIntermediateDirectories: true
        )

        self.temporaryHome = temporaryHome
        setenv("HOME", temporaryHome.path, 1)
        UserDefaults.resetStandardUserDefaults()
    }

    override func tearDownWithError() throws {
        UserDefaults.resetStandardUserDefaults()

        if let previousHome {
            setenv("HOME", previousHome, 1)
        } else {
            unsetenv("HOME")
        }

        if let temporaryHome {
            try? FileManager.default.removeItem(at: temporaryHome)
        }

        temporaryHome = nil
        previousHome = nil

        UserDefaults.resetStandardUserDefaults()
        try super.tearDownWithError()
    }
}
