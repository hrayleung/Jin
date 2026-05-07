import Foundation
import XCTest
@testable import Jin

final class AgentModeControlsResolverTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AgentModeControlsResolverTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testControlsReturnNilWhenInactiveOrPluginDisabled() {
        defaults.set(true, forKey: AppPreferenceKeys.agentModeEnabled)

        XCTAssertNil(AgentModeControlsResolver.controls(active: false, defaults: defaults))

        defaults.set(false, forKey: AppPreferenceKeys.agentModeEnabled)
        XCTAssertNil(AgentModeControlsResolver.controls(active: true, defaults: defaults))
    }

    func testControlsResolveDefaultsAndSeedSafePrefixes() {
        defaults.set(true, forKey: AppPreferenceKeys.agentModeEnabled)

        let controls = AgentModeControlsResolver.controls(active: true, defaults: defaults)

        XCTAssertEqual(controls?.enabled, true)
        XCTAssertNil(controls?.workingDirectory)
        XCTAssertEqual(controls?.commandTimeoutSeconds, 120)
        XCTAssertEqual(controls?.maxOutputBytes, 102_400)
        XCTAssertEqual(controls?.autoApproveFileReads, true)
        XCTAssertEqual(controls?.bypassPermissions, false)
        XCTAssertTrue(controls?.enabledTools.shellExecute == true)
        XCTAssertTrue(controls?.allowedCommandPrefixes.contains("swift test") == true)
        XCTAssertNotNil(defaults.string(forKey: AppPreferenceKeys.agentModeDefaultSafePrefixesJSON))
    }

    func testControlsMergeCustomPrefixesAndUserSettings() {
        defaults.set(true, forKey: AppPreferenceKeys.agentModeEnabled)
        defaults.set("/tmp/project", forKey: AppPreferenceKeys.agentModeWorkingDirectory)
        defaults.set("[\"npm test\",\"make lint\"]", forKey: AppPreferenceKeys.agentModeAllowedCommandPrefixesJSON)
        defaults.set("[\"git status\"]", forKey: AppPreferenceKeys.agentModeDefaultSafePrefixesJSON)
        defaults.set(30, forKey: AppPreferenceKeys.agentModeCommandTimeoutSeconds)
        defaults.set(false, forKey: AppPreferenceKeys.agentModeAutoApproveFileReads)
        defaults.set(true, forKey: AppPreferenceKeys.agentModeBypassPermissions)
        defaults.set(false, forKey: AppPreferenceKeys.agentModeToolShell)
        defaults.set(false, forKey: AppPreferenceKeys.agentModeToolFileWrite)
        defaults.set(false, forKey: AppPreferenceKeys.agentModeToolGrep)

        let controls = AgentModeControlsResolver.controls(active: true, defaults: defaults)

        XCTAssertEqual(controls?.workingDirectory, "/tmp/project")
        XCTAssertEqual(controls?.allowedCommandPrefixes, ["git status", "npm test", "make lint"])
        XCTAssertEqual(controls?.commandTimeoutSeconds, 30)
        XCTAssertEqual(controls?.autoApproveFileReads, false)
        XCTAssertEqual(controls?.bypassPermissions, true)
        XCTAssertEqual(controls?.enabledTools.shellExecute, false)
        XCTAssertEqual(controls?.enabledTools.fileRead, true)
        XCTAssertEqual(controls?.enabledTools.fileWrite, false)
        XCTAssertEqual(controls?.enabledTools.fileEdit, true)
        XCTAssertEqual(controls?.enabledTools.globSearch, true)
        XCTAssertEqual(controls?.enabledTools.grepSearch, false)
    }

    func testControlsAllowPluginGateInjection() {
        let controls = AgentModeControlsResolver.controls(
            active: true,
            defaults: defaults,
            pluginEnabled: { pluginID, _ in
                XCTAssertEqual(pluginID, "agent_mode")
                return true
            }
        )

        XCTAssertEqual(controls?.enabled, true)
    }
}
