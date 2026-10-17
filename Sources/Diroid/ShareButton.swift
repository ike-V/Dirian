import SwiftUI

// Placeholders until the Android app is published.
private let googlePlayURL = URL(string: "https://play.google.com/store/apps/details?id=com.ikev.dirian")!
private let releasesURL = URL(string: "https://github.com/ike-V/Dirian/releases/latest")!

/// Toolbar button that picks a Mac folder and shares it to an Android device, or stops sharing;
/// green while sharing.
struct ShareButton: View {
    @ObservedObject var share: MacShareModel

    private var folderName: String {
        FileManager.default.displayName(atPath: share.rootURL.path)
    }

    var body: some View {
        Button { share.toggle() } label: {
            Label(share.isSharing ? "Stop Sharing" : "Share Mac to Android", systemImage: "laptopcomputer")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(share.isSharing ? Color.androidGreen : Color.primary)
        }
        .disabled(share.isBusy)
        .help(share.isSharing
              ? "Stop sharing “\(folderName)” to Android"
              : "Choose a folder to share to Android")
    }
}

/// Alerts for share failures and the missing Android app. Applied outside the toolbar,
/// where alerts present reliably.
struct ShareAlerts: ViewModifier {
    @ObservedObject var share: MacShareModel

    func body(content: Content) -> some View {
        content.alert(alertTitle, isPresented: Binding(
            get: { share.notice != nil },
            set: { isPresented in if !isPresented { share.dismissNotice() } }
        )) {
            if case .appMissing = share.notice {
                Button("Open Google Play on Android") { share.openOnDevice(googlePlayURL) }
                Button("Download the APK on Android") { share.openOnDevice(releasesURL) }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(alertMessage)
        }
    }

    private var alertTitle: String {
        if case .appMissing = share.notice { return "Dirian Isn't Installed on Your Android Device" }
        return "Couldn't Start Sharing"
    }

    private var alertMessage: String {
        switch share.notice {
        case .appMissing:
            return "Install it on your Android device, then choose Start Sharing again. You can still browse your Android device from this Mac without it."
        case .failed(let message):
            return message
        case nil:
            return ""
        }
    }
}
