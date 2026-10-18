import Foundation
import AppKit
import Security

private let androidAppPackage = "com.ikev.dirian"
private let androidAppComponent = "\(androidAppPackage)/.MainActivity"
private struct AndroidAppMissing: Error { let client: AdbClient }
private struct SelectedDeviceGone: Error, CustomStringConvertible {
    let description = "The device you're browsing isn't connected. Plug it back in, or pick another device in the sidebar."
}

/// Something the user needs to see after trying to start sharing.
enum ShareNotice {
    case appMissing
    case failed(String)
}
private let shareRootKey = "shareRoot"

/// Shares a Mac folder to an Android device: starts the file server, reverse-forwards its port over
/// ADB, and opens the Android app with the access token.
@MainActor
final class MacShareModel: ObservableObject {
    @Published private(set) var isSharing = false
    @Published private(set) var isBusy = false
    @Published private(set) var notice: ShareNotice?
    @Published private(set) var rootURL: URL

    private var server: MacFileServer?
    private var client: AdbClient?
    /// The device that was missing the app, so its install links can be opened there.
    private var deviceMissingApp: AdbClient?
    /// The device chosen in the sidebar; nil until one is, when the first ready device is used.
    var selectedSerial: @MainActor () -> String? = { nil }
    /// The accent color ("#RRGGBB") to hand to the Android app, so it matches the Mac.
    var accentHex: @MainActor () -> String? = { nil }

    init() {
        if let saved = UserDefaults.standard.string(forKey: shareRootKey) {
            rootURL = URL(fileURLWithPath: saved)
        } else {
            let iCloudDrive = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
            rootURL = FileManager.default.fileExists(atPath: iCloudDrive.path)
                ? iCloudDrive : FileManager.default.homeDirectoryForCurrentUser
        }
    }

    /// Not sharing: choose a folder, then share it. Sharing: stop.
    func toggle() {
        if isSharing {
            stop()
        } else if !isBusy, chooseFolder() {
            start()
        }
    }

    /// Asks for the folder to share; false if cancelled.
    private func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = rootURL
        panel.prompt = "Share"
        panel.message = "Choose the folder your Android device can browse"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        rootURL = url
        UserDefaults.standard.set(url.path, forKey: shareRootKey)
        return true
    }

    func start() {
        guard !isSharing, !isBusy else { return }
        isBusy = true
        notice = nil
        let root = rootURL
        let token = Self.makeToken()
        let wanted = selectedSerial()
        let accent = accentHex()

        Task {
            do {
                let (server, client) = try await Task.detached { () throws -> (MacFileServer, AdbClient) in
                    let ready = try AdbClient.listDevices().filter(\.isReady)
                    let serial: String
                    if let wanted {
                        guard ready.contains(where: { $0.serial == wanted }) else { throw SelectedDeviceGone() }
                        serial = wanted
                    } else if let first = ready.first {
                        serial = first.serial
                    } else {
                        throw AdbError.serverError("No device found. Plug in your Android device with USB debugging enabled.")
                    }
                    let client = AdbClient(serial: serial)
                    guard try client.isPackageInstalled(androidAppPackage) else { throw AndroidAppMissing(client: client) }
                    let server = MacFileServer(root: root, token: token)
                    try server.start()
                    do {
                        try client.reverse(port: MacFileServer.port)
                        try client.startActivity(
                            androidAppComponent,
                            stringExtras: accent.map { ["token": token, "accent": $0] } ?? ["token": token],
                            intExtras: ["port": Int(MacFileServer.port)])
                    } catch {
                        server.stop()
                        try? client.removeReverse(port: MacFileServer.port)
                        throw error
                    }
                    return (server, client)
                }.value
                self.server = server
                self.client = client
                isSharing = true
            } catch let missing as AndroidAppMissing {
                deviceMissingApp = missing.client
                notice = .appMissing
            } catch AdbError.connectionFailed(_) {
                notice = .failed("The adb server isn't running. Dirian needs adb, which is included with Android Studio's platform-tools. Run `adb start-server` in Terminal.")
            } catch {
                notice = .failed("\(error)")
            }
            isBusy = false
        }
    }

    /// Opens a link on the Android device that is missing the app.
    func openOnDevice(_ url: URL) {
        guard let device = deviceMissingApp else { return }
        Task {
            do {
                try await Task.detached { try device.openURL(url.absoluteString) }.value
            } catch {
                notice = .failed("\(error)")
            }
        }
    }

    func dismissNotice() {
        notice = nil
    }

    func stop() {
        let server = server
        let client = client
        self.server = nil
        self.client = nil
        isSharing = false
        Task.detached {
            server?.stop()
            try? client?.removeReverse(port: MacFileServer.port)
        }
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
