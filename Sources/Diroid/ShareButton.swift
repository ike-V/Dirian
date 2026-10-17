import SwiftUI

// Placeholders until the Android app is published.
private let googlePlayURL = URL(string: "https://play.google.com/store/apps/details?id=com.ikev.dirian")!
private let androidAppURL = URL(string: "https://github.com/ike-V/Dirian#dirian-for-android")!

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
                Button("Get the APK on Android") { share.openOnDevice(androidAppURL) }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(alertMessage)
        }
    }

    private var alertTitle: String {
        if case .appMissing = share.notice { return "Dirian for Android Isn't Installed on Your Device" }
        return "Couldn't Start Sharing"
    }

    private var alertMessage: String {
        switch share.notice {
        case .appMissing:
            return "Dirian for Android is only needed for sharing a Mac folder to your Android device. Install it, then click Share Mac to Android again. Everything else in Dirian works without it."
        case .failed(let message):
            return message
        case nil:
            return ""
        }
    }
}
