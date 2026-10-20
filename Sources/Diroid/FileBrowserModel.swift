import Foundation
import AppKit

/// Why nothing can be listed, shown centered in place of the file list. A `command`, if
/// any, is shown with a copy button for pasting into Terminal.
struct ConnectionProblem {
    let title: String
    let detail: String
    var command: String?
}

private let selectedDeviceKey = "selectedDeviceSerial"

@MainActor
final class FileBrowserModel: ObservableObject {
    /// Where `/sdcard` resolves to.
    static let rootPath = "/storage/emulated/0"

    @Published private(set) var currentPath: String = rootPath
    @Published private(set) var entries: [AdbDirEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var connectionProblem: ConnectionProblem?
    /// The sidebar category being shown (a search across the whole storage), or nil when browsing a folder.
    @Published private(set) var category: FileCategory?
    /// Every device adb lists, kept current while the app runs.
    @Published private(set) var devices: [AdbDevice] = []
    /// Display names of ready devices, by serial.
    @Published private(set) var deviceNames: [String: String] = [:]
    /// The device being browsed, and the one Share Mac to Android targets.
    @Published private(set) var selectedSerial: String?
    /// The selected device's name, for the sidebar's root entry.
    var deviceName: String { selectedSerial.flatMap { deviceNames[$0] } ?? "Internal Storage" }
    /// Names of the visible folders directly under `rootPath`, for the sidebar.
    @Published private(set) var sidebarFolders: [String] = []

    private var client: AdbClient?
    private var watchTask: Task<Void, Never>?

    /// Dismisses the error without touching `currentPath` or `entries`.
    func clearError() {
        errorMessage = nil
    }

    /// Joins `base` (default `currentPath`) and `name`, avoiding "//" when `base` is "/".
    private func childPath(_ name: String, in base: String? = nil) -> String {
        let base = base ?? currentPath
        return base == "/" ? "/\(name)" : "\(base)/\(name)"
    }

    /// Where `entry` lives: its own path for category results, else the current folder.
    private func path(for entry: AdbDirEntry) -> String {
        entry.fullPath ?? childPath(entry.name)
    }

    /// Runs `operation`, reporting any error via `errorMessage`.
    private func catching(_ operation: () async throws -> Void) async {
        do {
            try await operation()
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Runs a device-mutating `operation` off the main actor, then reloads.
    private func mutate(_ operation: @escaping @Sendable () throws -> Void) async {
        await catching {
            try await Task.detached(operation: operation).value
            await reload()
        }
    }

    /// Reloads the folder or category currently shown.
    private func reload() async {
        if let category { await loadCategory(category) } else { await load(path: currentPath) }
    }

    /// Lists the devices, picks one (the user's last choice if it's connected, else the first ready one),
    /// and opens its root folder.
    func connectAndLoadRoot() {
        Task {
            connectionProblem = nil
            do {
                let found = try await Task.detached { try AdbClient.listDevices() }.value
                devices = found
                guard let serial = Self.chooseSerial(from: found) else {
                    selectedSerial = nil
                    connectionProblem = found.contains { $0.state == "unauthorized" }
                        ? Self.unauthorizedProblem
                        : ConnectionProblem(
                            title: "No device found",
                            detail: "Plug in your Android device with USB debugging enabled, then press refresh.")
                    return
                }
                selectedSerial = serial
                client = AdbClient(serial: serial)
                await fetchNames(for: found.filter { $0.serial == serial })
                Task { await fetchNames(for: found) }
                await load(path: Self.rootPath)
            } catch AdbError.connectionFailed(_) {
                connectionProblem = ConnectionProblem(
                    title: "The adb server isn't running",
                    detail: "Dirian needs adb, the Android Debug Bridge. It's included with Android Studio (in the SDK's platform-tools), or install it with: brew install --cask android-platform-tools. Then run this in Terminal and press refresh.",
                    command: "adb start-server")
            } catch {
                errorMessage = "\(error)"
            }
        }
    }

    private static let unauthorizedProblem = ConnectionProblem(
        title: "Allow USB debugging on your Android device",
        detail: "Unlock your Android device and tap Allow on the USB debugging prompt, then press refresh. No prompt? Run this in Terminal to ask again. Still nothing? On the device, open Developer options and tap “Revoke USB debugging authorizations”, then replug it. On Samsung, also turn off “Block commands and software updates by USB cable” in Auto Blocker.",
        command: "adb reconnect")

    /// The device to use: the last one the user picked if it's ready, else the first ready one.
    private static func chooseSerial(from devices: [AdbDevice]) -> String? {
        let ready = devices.filter(\.isReady)
        if let preferred = UserDefaults.standard.string(forKey: selectedDeviceKey),
           ready.contains(where: { $0.serial == preferred }) {
            return preferred
        }
        return ready.first?.serial
    }

    /// Reads the names of ready `list` devices that don't have one yet.
    private func fetchNames(for list: [AdbDevice]) async {
        for device in list where device.isReady && deviceNames[device.serial] == nil {
            let serial = device.serial
            if let name = try? await Task.detached(operation: { try AdbClient(serial: serial).deviceName() }).value {
                deviceNames[serial] = name
            }
        }
    }

    /// How `device` appears in the picker: its name, with the serial added when two devices share a
    /// name or the name is unknown, and its state when it isn't ready.
    func label(for device: AdbDevice) -> String {
        let name = deviceNames[device.serial]
        let shared = name != nil && devices.contains { $0.serial != device.serial && deviceNames[$0.serial] == name }
        var text = name.map { shared ? "\($0) (\(device.serial))" : $0 } ?? device.serial
        if !device.isReady { text += " (\(device.state))" }
        return text
    }

    /// Switches to `serial` and reloads from its root. Remembered across launches.
    func selectDevice(_ serial: String) {
        guard serial != selectedSerial, devices.first(where: { $0.serial == serial })?.isReady == true else { return }
        UserDefaults.standard.set(serial, forKey: selectedDeviceKey)
        connectAndLoadRoot()
    }

    /// Keeps `devices` current while the app runs, so a device plugged in or out shows in the picker.
    func startWatchingDevices() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }
                await self.refreshDevices()
            }
        }
    }

    private func refreshDevices() async {
        guard let found = try? await Task.detached(operation: { try AdbClient.listDevices() }).value,
              found != devices else { return }
        devices = found
        await fetchNames(for: found)
    }

    func load(path: String) async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await Task.detached { try client.listDirectory(path) }.value
            if fetched.isEmpty {
                // Empty may mean a swallowed permission error; check.
                try await Task.detached { try client.checkDirectoryAccess(path) }.value
            }
            currentPath = path
            category = nil
            entries = fetched.sorted(by: nameAscending)
            if path == Self.rootPath {
                sidebarFolders = entries.filter { $0.isDirectory && !$0.name.hasPrefix(".") }.map(\.name)
            }
        } catch AdbError.serverError(let message) where message.contains("unauthorized") {
            connectionProblem = Self.unauthorizedProblem
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
    }

    /// Lists the files of `category` from the whole storage, newest first.
    func loadCategory(_ category: FileCategory) async {
        guard let client else { return }
        isLoading = true
        errorMessage = nil
        let root = Self.rootPath
        do {
            let found = try await Task.detached { try client.categoryFiles(category, under: root, limit: 300) }.value
            self.category = category
            entries = found
        } catch {
            errorMessage = "\(error)"
        }
        isLoading = false
    }

    func open(entry: AdbDirEntry) {
        let fullPath = path(for: entry)
        if entry.isDirectory {
            Task { await load(path: fullPath) }
            return
        }
        guard let client else { return }
        Task {
            await catching {
                try await downloadAndOpen(client: client, remotePath: fullPath, fileName: entry.name)
            }
        }
    }

    /// Pulls a file to a temp directory and opens it with its default app.
    private func downloadAndOpen(client: AdbClient, remotePath: String, fileName: String) async throws {
        let data = try await Task.detached { try client.readFile(remotePath) }.value

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(fileName)
        try data.write(to: fileURL)

        NSWorkspace.shared.open(fileURL)
    }

    /// Pulls a file into a user-chosen folder, suffixing the name on collision.
    func saveToFolder(entry: AdbDirEntry) {
        guard !entry.isDirectory, let client else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Save"
        panel.message = "Choose a folder to save \"\(entry.name)\" to"

        guard panel.runModal() == .OK, let destinationFolder = panel.url else { return }

        let remotePath = path(for: entry)
        Task {
            await catching {
                let data = try await Task.detached { try client.readFile(remotePath) }.value

                let fileManager = FileManager.default
                let fileName = Self.uniqueName(for: entry.name) { candidate in
                    fileManager.fileExists(atPath: destinationFolder.appendingPathComponent(candidate).path)
                }

                try data.write(to: destinationFolder.appendingPathComponent(fileName))
            }
        }
    }

    /// Deletes after confirmation; folders are deleted recursively.
    func delete(entry: AdbDirEntry) {
        guard let client else { return }

        let alert = NSAlert()
        if entry.isDirectory {
            alert.messageText = "Delete \"\(entry.name)\" and everything inside it?"
            alert.informativeText = "This permanently deletes the folder and all its contents from your Android device. This can't be undone."
        } else {
            alert.messageText = "Delete \"\(entry.name)\"?"
            alert.informativeText = "This permanently deletes the file from your Android device. This can't be undone."
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let remotePath = path(for: entry)
        let isDirectory = entry.isDirectory
        Task {
            await mutate {
                try client.delete(remotePath, recursive: isDirectory)
            }
        }
    }

    /// Prompts for a new name and renames the entry.
    func rename(entry: AdbDirEntry) {
        guard let client else { return }
        guard let newName = Self.promptForText(title: "Rename \"\(entry.name)\"", actionTitle: "Rename", defaultValue: entry.name),
              newName != entry.name else { return }

        let oldPath = path(for: entry)
        let newPath = childPath(newName, in: (oldPath as NSString).deletingLastPathComponent)
        Task {
            await mutate {
                try client.rename(oldPath, to: newPath)
            }
        }
    }

    /// Prompts for a name and creates a new folder in the current directory.
    func makeDirectory() {
        guard let client, category == nil else { return }

        let existingNames = Set(entries.map(\.name))
        let defaultName = Self.uniqueName(for: "New Folder") { existingNames.contains($0) }
        guard let name = Self.promptForText(title: "New Folder", actionTitle: "Create", defaultValue: defaultName) else { return }

        let path = childPath(name)
        Task {
            await mutate {
                try client.makeDirectory(path)
            }
        }
    }

    /// Pushes user-picked local files into the current directory, suffixing names on collision.
    func uploadFiles() {
        guard let client, category == nil else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload"
        panel.message = "Choose files to upload to \(currentPath)"

        guard panel.runModal() == .OK else { return }
        let localURLs = panel.urls
        let destinationPath = currentPath
        var existingNames = Set(entries.map(\.name))

        Task {
            for localURL in localURLs {
                await catching {
                    let data = try Data(contentsOf: localURL)
                    let originalName = localURL.lastPathComponent
                    let fileName = Self.uniqueName(for: originalName) { existingNames.contains($0) }
                    existingNames.insert(fileName)

                    let remotePath = childPath(fileName, in: destinationPath)
                    try await Task.detached { try client.writeFile(remotePath, data: data) }.value
                }
            }
            await load(path: currentPath)
        }
    }

    /// Modal single-line text prompt. Returns the trimmed text, or nil if cancelled or empty.
    private static func promptForText(title: String, actionTitle: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.alertStyle = .informational
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(string: defaultValue)
        textField.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Appends " (1)", " (2)", ... before the extension until `exists` reports the name is free.
    private static func uniqueName(for originalName: String, exists: (String) -> Bool) -> String {
        guard exists(originalName) else { return originalName }
        let baseName = (originalName as NSString).deletingPathExtension
        let ext = (originalName as NSString).pathExtension
        var candidate: String
        var counter = 1
        repeat {
            candidate = ext.isEmpty ? "\(baseName) (\(counter))" : "\(baseName) (\(counter)).\(ext)"
            counter += 1
        } while exists(candidate)
        return candidate
    }
}
