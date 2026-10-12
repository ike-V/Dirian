import SwiftUI

// Placeholders until the Android app is published.
private let googlePlayURL = URL(string: "https://play.google.com/store/apps/details?id=com.ikev.diroid")!
private let releasesURL = URL(string: "https://github.com/ike-V/Diroid/releases/latest")!

/// Popover for sharing a Mac's folder to an Android device.
struct ShareView: View {
    @ObservedObject var share: MacShareModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Share a Mac's folder to your Android device")
                    .font(.headline)
                Text("The Diroid app on your Android device can browse, copy and upload files in this folder over the USB cable.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            folderRow

            if share.appMissing {
                missingAppNotice
            } else if let message = share.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if share.isSharing {
                    Label("Sharing", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
                Spacer()
                Button(share.isSharing ? "Stop Sharing" : "Start Sharing") {
                    if share.isSharing { share.stop() } else { share.start() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(share.isBusy)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var folderRow: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: share.rootURL.path))
                .resizable()
                .frame(width: 16, height: 16)
            Text(FileManager.default.displayName(atPath: share.rootURL.path))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(share.rootURL.path)
            Spacer()
            Button("Choose…") { share.chooseFolder() }
                .disabled(share.isSharing || share.isBusy)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    private var missingAppNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Diroid isn't installed on your Android device", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Install it, then choose Start Sharing again. You can still browse your Android device from this Mac without it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Link("Get It on Google Play", destination: googlePlayURL)
                Link("Download the APK", destination: releasesURL)
            }
            .font(.callout)
        }
    }
}
