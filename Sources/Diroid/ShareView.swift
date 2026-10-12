import SwiftUI

/// Popover for sharing a Mac folder to the phone.
struct ShareView: View {
    @ObservedObject var share: MacShareModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Share a Mac folder to your phone")
                .font(.headline)
            Text("The Diroid app on your phone can browse, copy and upload files in this folder over the USB cable.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.androidGreen)
                Text(share.rootURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose…") { share.chooseFolder() }
                    .disabled(share.isSharing || share.isBusy)
            }

            if let message = share.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                if share.isSharing {
                    Label("Sharing", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.androidGreen)
                }
                Spacer()
                if share.isSharing {
                    Button("Stop sharing") { share.stop() }
                } else {
                    Button("Start sharing") { share.start() }
                        .disabled(share.isBusy)
                }
            }
        }
        .padding()
        .frame(width: 340)
    }
}
