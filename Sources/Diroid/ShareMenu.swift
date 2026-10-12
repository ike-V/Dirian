import SwiftUI

// Placeholders until the Android app is published.
private let googlePlayURL = URL(string: "https://play.google.com/store/apps/details?id=com.ikev.diroid")!
private let releasesURL = URL(string: "https://github.com/ike-V/Diroid/releases/latest")!

/// Bottom-bar menu for sharing a Mac's folder to an Android device.
struct ShareMenu: View {
    @ObservedObject var share: MacShareModel

    private var folderName: String {
        FileManager.default.displayName(atPath: share.rootURL.path)
    }

    var body: some View {
        Menu {
            if share.isSharing {
                Button("Stop Sharing") { share.stop() }
            } else {
                Button("Start Sharing “\(folderName)”") { share.start() }
                    .disabled(share.isBusy)
            }
            Divider()
            Button("Choose Folder…") { share.chooseFolder() }
                .disabled(share.isSharing || share.isBusy)
        } label: {
            Text(share.isSharing ? "Sharing to Android" : "Share Mac to Android")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .alert(alertTitle, isPresented: Binding(
            get: { share.notice != nil },
            set: { isPresented in if !isPresented { share.dismissNotice() } }
        )) {
            if case .appMissing = share.notice {
                Button("Get It on Google Play") { NSWorkspace.shared.open(googlePlayURL) }
                Button("Download the APK") { NSWorkspace.shared.open(releasesURL) }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(alertMessage)
        }
    }

    private var alertTitle: String {
        if case .appMissing = share.notice { return "Diroid Isn't Installed on Your Android Device" }
        return "Couldn't Start Sharing"
    }

    private var alertMessage: String {
        switch share.notice {
        case .appMissing:
            return "Install it, then choose Start Sharing again. You can still browse your Android device from this Mac without it."
        case .failed(let message):
            return message
        case nil:
            return ""
        }
    }
}
