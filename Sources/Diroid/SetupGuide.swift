import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    /// Posted when a device becomes ready, so the browser connects to it.
    static let deviceBecameReady = Notification.Name("deviceBecameReady")
}

/// The setup window: opens by itself the first time Dirian runs without a ready device, and from the Dirian menu after that.
@MainActor
enum SetupGuideWindow {
    private static let seenKey = "setupGuideSeen"
    private static var window: NSWindow?

    static func showIfFirstRun() {
        guard !UserDefaults.standard.bool(forKey: seenKey) else { return }
        Task {
            if await AdbStatus.current() == .ready {
                UserDefaults.standard.set(true, forKey: seenKey)
            } else {
                show()
            }
        }
    }

    static func show() {
        if window == nil {
            let root = SetupGuideView(close: { window?.close() }, resize: resize)
                .environment(\.accent, AppPrefs.savedAccent)
            let hosting = NSHostingView(rootView: root)
            hosting.sizingOptions = []   // the window is sized by `resize`, not by the view, so they can't fight
            let guide = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            guide.contentView = hosting
            guide.title = "Set up Dirian"
            guide.isReleasedWhenClosed = false
            guide.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: guide, queue: .main) { _ in
                UserDefaults.standard.set(true, forKey: "setupGuideSeen")
            }
            window = guide
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Fits the window to the steps' height, keeping its top edge where it is.
    private static func resize(to height: CGFloat) {
        guard let window, height > 0 else { return }
        let target = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 440, height: height)).size
        guard abs(target.height - window.frame.height) > 1 else { return }
        var frame = window.frame
        frame.origin.y += frame.height - target.height
        frame.size = target
        window.setFrame(frame, display: true)
    }
}

/// Applies the chosen Dock icon at launch and opens the guide on the first run.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppPrefs.savedAppIcon.apply() }
        // After the browser window has had its first look for a device.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            MainActor.assumeIsolated { SetupGuideWindow.showIfFirstRun() }
        }
    }
}

/// How far the adb connection has got.
enum AdbStatus: Equatable {
    case unknown, noServer, noDevice, needsAllow, ready

    static func current() async -> AdbStatus {
        guard let found = try? await Task.detached(operation: { try AdbClient.listDevices() }).value else { return .noServer }
        if found.isEmpty { return .noDevice }
        return found.contains(where: \.isReady) ? .ready : .needsAllow
    }
}

/// Steps that tick themselves as adb, the device and its USB debugging approval come true.
struct SetupGuideView: View {
    let close: () -> Void
    let resize: (CGFloat) -> Void
    @Environment(\.accent) private var accent
    @State private var status = AdbStatus.unknown
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private struct Step {
        let title: String
        let detail: String
        let done: Bool
        var commands: [String] = []
    }

    private var steps: [Step] {
        let adb = AdbSetup.current
        return [
            Step(
                title: "Install and start adb",
                detail: adb.detail + " Then wait a moment and this step ticks itself.",
                done: status != .unknown && status != .noServer,
                commands: [adb.command]
            ),
            Step(
                title: "Turn on USB debugging & connect device",
                detail: "On Android open Settings > About phone > Locate Build number & tap 7 times.\nOpen Developer options > turn on USB debugging > connect device to USB.",
                done: status == .needsAllow || status == .ready
            ),
            Step(
                title: "Allow USB debugging",
                detail: "Unlock Android and tap Allow on USB debugging prompt (\"Always allow\" to save connection).\nOn Samsung devices turn off \"Auto Blocker\" in Security & Privacy",
                done: status == .ready
            ),
        ]
    }

    var body: some View {
        let steps = steps
        let allDone = steps.allSatisfy(\.done)
        let current = steps.firstIndex { !$0.done }
        VStack(alignment: .leading, spacing: 14) {
            Text(allDone ? "You're all set" : "Set up Dirian").font(.title2.weight(.semibold))
            Text(allDone ? "Dirian can see your Android device and is ready to browse it."
                         : "Dirian browses your Android device's files over USB.")
                .foregroundStyle(.secondary)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(step.done ? accent.color : Color.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(step.title).foregroundStyle(step.done ? .secondary : .primary)
                        if !step.done {
                            Text(step.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            if index == current {
                                ForEach(step.commands, id: \.self) { CommandBox(command: $0) }
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button(allDone ? "Done" : "Skip for now", action: close)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(GeometryReader { Color.clear.preference(key: GuideHeightKey.self, value: $0.size.height) })
        .onPreferenceChange(GuideHeightKey.self) { height in DispatchQueue.main.async { resize(height) } }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear(perform: refresh)
        .onReceive(tick) { _ in refresh() }
    }

    private func refresh() {
        Task {
            let latest = await AdbStatus.current()
            if latest == .ready, status != .ready { NotificationCenter.default.post(name: .deviceBecameReady, object: nil) }
            status = latest
        }
    }
}

private struct GuideHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
