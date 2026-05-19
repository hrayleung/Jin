import SwiftUI
import SwiftData
import AppKit
import Kingfisher

@MainActor
private final class JinAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppIconManager.applyDefaultIcon()
        // Bridge appAppearanceMode → NSApp.appearance so AppKit chrome
        // (title bar, window.backgroundColor, every NSVisualEffectView,
        // menus, sheets, popovers, alerts) follows the user's chosen mode.
        // SwiftUI's .preferredColorScheme(...) only tints the SwiftUI
        // environment; without this assignment the title bar resolves
        // against the system appearance, producing the black bar over
        // light content when system≠app mode. Apple bug FB8383053.
        let storedMode = UserDefaults.standard.string(forKey: AppPreferenceKeys.appAppearanceMode)
            .flatMap(AppAppearanceMode.init(rawValue:)) ?? .system
        NSApp.appearance = storedMode.resolvedNSAppearance()
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = AppPreferencesSnapshotStore.persistCurrentDomain()
        if !AppRuntimeProtection.automaticSnapshotsSuspended {
            _ = try? AppSnapshotManager.captureAutomaticSnapshot(reason: .termination)
        }
    }
}

@main
struct JinApp: App {
    @NSApplicationDelegateAdaptor(JinAppDelegate.self) private var appDelegate
    @StateObject private var launchCoordinator: AppLaunchCoordinator
    @StateObject private var streamingStore = ConversationStreamingStore()
    @StateObject private var responseCompletionNotifier = ResponseCompletionNotifier()
    @StateObject private var shortcutsStore = AppShortcutsStore.shared
    @StateObject private var updateManager: SparkleUpdateManager

    @AppStorage(AppPreferenceKeys.appAppearanceMode) private var appAppearanceMode: AppAppearanceMode = .system
    @AppStorage(AppPreferenceKeys.appFontFamily) private var appFontFamily = JinTypography.systemFontPreferenceValue

    @State private var postLaunchMaintenanceStarted = false

    private let preferencesSyncController: AppPreferencesSyncController
    private let postLaunchMaintenance = AppPostLaunchMaintenance()

    init() {
        UserDefaults.standard.register(defaults: [
            AppPreferenceKeys.notifyOnBackgroundResponseCompletion: true,
            AppPreferenceKeys.updateAutoCheckOnLaunch: true,
            AppPreferenceKeys.updateAllowPreRelease: false,
            AppPreferenceKeys.useOverlayScrollbars: true
        ])
        ImageCache.default.memoryStorage.config.expiration = .seconds(3600)
        ImageCache.default.diskStorage.config.expiration = .days(30)
        OverlayScrollerStyleController.shared.installIfNeeded()

        preferencesSyncController = AppPreferencesSyncController()
        SpeechPluginPreferenceSupport.migrateLegacyOnDeviceProviderSelections()
        _updateManager = StateObject(wrappedValue: SparkleUpdateManager())
        _launchCoordinator = StateObject(wrappedValue: AppLaunchCoordinator())
    }

    var body: some Scene {
        WindowGroup {
            AppRootContentView(launchCoordinator: launchCoordinator) { container in
                ContentView()
                    .modelContainer(container)
                    .environmentObject(streamingStore)
                    .environmentObject(responseCompletionNotifier)
                    .environmentObject(shortcutsStore)
                    .environmentObject(updateManager)
                    .font(JinTypography.appFont(familyPreference: appFontFamily))
                    .preferredColorScheme(preferredColorScheme)
                    .onChange(of: appAppearanceMode) { _, newValue in
                        NSApp.appearance = newValue.resolvedNSAppearance()
                    }
                    .onAppear {
                        performPostLaunchMaintenanceIfNeeded(with: container)
                    }
                    .task {
                        await updateManager.checkForUpdatesOnLaunchIfNeeded()
                    }
            }
            .onAppear {
                launchCoordinator.startIfNeeded()
            }
            // No window customization. Reference Tahoe-native apps (Chops,
            // Apple's own) use plain WindowGroup + NavigationSplitView and
            // let the system handle title bar, sidebar Liquid Glass, traffic
            // lights, fullscreen transitions. Every customization we tried
            // (.windowStyle hiddenTitleBar, containerBackground thinMaterial,
            // WindowChromeCompat NSWindow hacks) fought Tahoe and produced
            // either double-bordered glass or jumping layouts.
        }
        .commands {
            ChatCommands(shortcutsStore: shortcutsStore)
        }

        Settings {
            AppRootContentView(launchCoordinator: launchCoordinator) { container in
                SettingsView()
                    .modelContainer(container)
                    .environmentObject(responseCompletionNotifier)
                    .environmentObject(shortcutsStore)
                    .environmentObject(updateManager)
                    .font(JinTypography.appFont(familyPreference: appFontFamily))
                    .preferredColorScheme(preferredColorScheme)
                    .onChange(of: appAppearanceMode) { _, newValue in
                        NSApp.appearance = newValue.resolvedNSAppearance()
                    }
            }
            .onAppear {
                launchCoordinator.startIfNeeded()
            }
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appAppearanceMode {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private func performPostLaunchMaintenanceIfNeeded(with container: ModelContainer) {
        guard !postLaunchMaintenanceStarted else { return }
        postLaunchMaintenanceStarted = true

        postLaunchMaintenance.perform(with: container)
    }

    static func mergeRefreshedModels(latestModels: [ModelInfo], existingModels: [ModelInfo]) -> [ModelInfo] {
        AppPostLaunchMaintenance.mergeRefreshedModels(latestModels: latestModels, existingModels: existingModels)
    }
}

