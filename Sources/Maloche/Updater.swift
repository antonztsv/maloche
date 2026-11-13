import AppKit
import MalocheCore
import Sparkle

/// Sparkle in a bundle with a feed and a key; the setting decides whether it checks on its own.
@MainActor
final class Updater {
    private let model: AppModel
    private let controller: SPUStandardUpdaterController

    init?(model: AppModel, info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        guard Updates.isConfigured(info: info) else { return nil }
        self.model = model
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        followSetting()
        controller.startUpdater()
    }

    func checkNow() {
        controller.checkForUpdates(nil)
    }

    private func followSetting() {
        controller.updater.automaticallyChecksForUpdates = withObservationTracking {
            model.settings.checkForUpdates
        } onChange: { [weak self] in
            Task { @MainActor in self?.followSetting() }
        }
    }
}
