import Foundation
import Sparkle

class UpdaterService {
    static let shared = UpdaterService()

    let updaterController: SPUStandardUpdaterController

    private init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
