import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import ZipArchive
import OverlayStatusController
import PresentationDataUtils

// ZalupaGram fork: logs button in Settings. Packs the app log files into
// one zip with a header about the build and the device, then opens the
// system share sheet, so the logs can be saved to Files or sent anywhere.

private func deviceModel() -> String {
    var info = utsname()
    uname(&info)
    let mirror = Mirror(reflecting: info.machine)
    var result = ""
    for child in mirror.children {
        if let value = child.value as? Int8, value != 0 {
            result.append(Character(UnicodeScalar(UInt8(bitPattern: value))))
        }
    }
    return result
}

private func logsHeader() -> String {
    let info = Bundle.main.infoDictionary ?? [:]
    let telegramVersion = info["CFBundleShortVersionString"] as? String ?? "?"
    let buildNumber = info["CFBundleVersion"] as? String ?? "?"
    let bundleId = Bundle.main.bundleIdentifier ?? "?"
    let formatter = ISO8601DateFormatter()
    var lines: [String] = []
    lines.append("\(ZalupaGram.title) \(ZalupaGram.version) (build \(buildNumber), Telegram \(telegramVersion))")
    lines.append("Bundle: \(bundleId)")
    lines.append("Device: \(deviceModel()), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
    lines.append("Collected: \(formatter.string(from: Date()))")
    return lines.joined(separator: "\n") + "\n\n"
}

// Newest log files only, together up to this size: all of them can be
// hundreds of megabytes after a while and took minutes to pack.
private let maxLogsSize: Int64 = 30 * 1024 * 1024

private func makeLogsArchive(logs: [(String, String)]) -> String? {
    var selected: [(String, String)] = []
    var total: Int64 = 0
    for (name, path) in logs.reversed() {
        let size = ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.int64Value ?? 0
        if !selected.isEmpty && total + size > maxLogsSize {
            break
        }
        selected.append((name, path))
        total += size
    }

    let directory = NSTemporaryDirectory() + "zalupagram-logs"
    try? FileManager.default.removeItem(atPath: directory)
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let baseName = "ZalupaGram-logs-\(formatter.string(from: Date()))"
    let infoPath = directory + "/info.txt"
    var info = logsHeader()
    info += selected.isEmpty ? "No log files.\n" : "Files: \(selected.count) of \(logs.count), \(total / 1024) KB\n"
    guard (try? info.data(using: .utf8)!.write(to: URL(fileURLWithPath: infoPath))) != nil else {
        return nil
    }
    let zipPath = directory + "/\(baseName).zip"
    guard SSZipArchive.createZipFile(atPath: zipPath, withFilesAtPaths: [infoPath] + selected.reversed().map { $0.1 }) else {
        return nil
    }
    return zipPath
}

// Set by AppDelegate. The files are read directly: Logger.collectLogs()
// waits in the logger queue behind all pending writes and never came back.
public var zalupaGramLogsDirectory: String?

private func listLogs() -> [(String, String)] {
    guard let directory = zalupaGramLogsDirectory, let urls = try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: directory), includingPropertiesForKeys: [.creationDateKey], options: []) else {
        return []
    }
    var files: [(Date, String, String)] = []
    for url in urls where url.lastPathComponent.hasPrefix("log-") {
        let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
        files.append((date, url.lastPathComponent, url.path))
    }
    files.sort(by: { $0.0 < $1.0 })
    return files.map { ($0.1, $0.2) }
}

private final class LogsState {
    var finished = false
}

public func zalupaGramShareLogs(context: AccountContext) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let ru = zalupaGramIsRussian(presentationData.strings)
    let progress = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
    context.sharedContext.mainWindow?.present(progress, on: .root)
    let state = LogsState()
    let alert: (String) -> Void = { text in
        context.sharedContext.mainWindow?.present(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), on: .root)
    }

    Queue.mainQueue().after(60.0, {
        if state.finished {
            return
        }
        state.finished = true
        progress.dismiss()
        alert(ru ? "Логи собираются слишком долго, попробуйте ещё раз." : "Collecting the logs takes too long, try again.")
    })

    DispatchQueue.global(qos: .userInitiated).async {
        let logs = listLogs()
        let path = makeLogsArchive(logs: logs)
        Queue.mainQueue().async {
            if state.finished {
                return
            }
            state.finished = true
            progress.dismiss()
            guard let window = context.sharedContext.mainWindow else {
                return
            }
            guard let path = path else {
                alert(ru ? "Не удалось собрать логи." : "Couldn't collect the logs.")
                return
            }
            // After the progress has gone, a native sheet doesn't show over it.
            Queue.mainQueue().after(0.3, {
                let activityController = UIActivityViewController(activityItems: [URL(fileURLWithPath: path)], applicationActivities: nil)
                if let popover = activityController.popoverPresentationController {
                    let view = window.hostView.containerView
                    popover.sourceView = view
                    popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
                    popover.permittedArrowDirections = []
                }
                window.presentNative(activityController)
            })
        }
    }
}
