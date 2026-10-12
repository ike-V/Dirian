import Foundation
import AppKit
import Security

private let phoneAppComponent = "com.ikev.diroid/.MainActivity"
private let shareRootKey = "shareRoot"

/// Shares a Mac folder to the phone: starts the file server, reverse-forwards its port over
/// ADB, and opens the phone app with the access token.
@MainActor
final class MacShareModel: ObservableObject {
    @Published private(set) var isSharing = false
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
    @Published private(set) var rootURL: URL

    private var server: MacFileServer?
    private var client: AdbClient?

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

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = rootURL
        panel.prompt = "Share"
        panel.message = "Choose the folder your phone can browse"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rootURL = url
        UserDefaults.standard.set(url.path, forKey: shareRootKey)
    }

    func start() {
        guard !isSharing, !isBusy else { return }
        isBusy = true
        message = nil
        let root = rootURL
        let token = Self.makeToken()

        Task {
            do {
                let (server, client) = try await Task.detached { () throws -> (MacFileServer, AdbClient) in
                    guard let serial = try AdbClient.listDeviceSerials().first else {
                        throw AdbError.serverError("No device found. Plug in your phone with USB debugging enabled.")
                    }
                    let client = AdbClient(serial: serial)
                    let server = MacFileServer(root: root, token: token)
                    try server.start()
                    do {
                        try client.reverse(port: MacFileServer.port)
                        try client.startActivity(
                            phoneAppComponent,
                            stringExtras: ["token": token],
                            intExtras: ["port": Int(MacFileServer.port)])
                    } catch {
                        server.stop()
                        throw error
                    }
                    return (server, client)
                }.value
                self.server = server
                self.client = client
                isSharing = true
            } catch AdbError.connectionFailed(_) {
                message = "The adb server isn't running. Run `adb start-server` in Terminal."
            } catch {
                message = "\(error)"
            }
            isBusy = false
        }
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
