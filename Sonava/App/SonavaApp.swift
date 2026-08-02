//
//  AudioPlayerApp.swift
//  Sonava
//
//  SwiftUI entry point.
//

import SwiftUI

@main
struct AudioPlayerApp: App {
    /// The only reason this app has a delegate: iOS relaunches an app in the
    /// background when its download session finishes work, and hands over a
    /// completion handler that must be called once the results are processed.
    /// Nothing in SwiftUI's scene lifecycle receives that callback.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Called when the system has finished transferring files we asked for
    /// while the app was suspended or dead. Handing the handler to the store
    /// lets it do its bookkeeping and then tell iOS it is safe to suspend us
    /// again — skipping this is how a download appears to finish and then
    /// isn't there on the next launch.
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == DownloadStore.sessionIdentifier else {
            completionHandler()
            return
        }
        Task { @MainActor in
            AudioManager.shared.downloads.backgroundCompletionHandler = completionHandler
        }
    }
}
