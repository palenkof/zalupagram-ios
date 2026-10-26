import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import ZipArchive

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

private func makeLogsArchive(logs: [(String, String)]) -> String? {
    let lineFeed = "\n".data(using: .utf8)!
    var data = logsHeader().data(using: .utf8)!
    if logs.isEmpty {
        data.append("No log files.\n".data(using: .utf8)!)
    }
    for (name, path) in logs {
        data.append(lineFeed)
        data.append("------ File: \(name) ------\n".data(using: .utf8)!)
        if let fileData = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            data.append(fileData)
        }
    }

    let directory = NSTemporaryDirectory() + "zalupagram-logs"
    try? FileManager.default.removeItem(atPath: directory)
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let baseName = "ZalupaGram-logs-\(formatter.string(from: Date()))"
    let textPath = directory + "/\(baseName).txt"
    let zipPath = directory + "/\(baseName).zip"
    guard (try? data.write(to: URL(fileURLWithPath: textPath))) != nil else {
        return nil
    }
    guard SSZipArchive.createZipFile(atPath: zipPath, withFilesAtPaths: [textPath]) else {
        return nil
    }
    try? FileManager.default.removeItem(atPath: textPath)
    return zipPath
}

public func zalupaGramShareLogs(context: AccountContext) {
    let _ = (Logger.shared.collectLogs()
    |> deliverOn(Queue.concurrentDefaultQueue())
    |> map { logs -> String? in
        return makeLogsArchive(logs: logs)
    }
    |> deliverOnMainQueue).start(next: { path in
        guard let path = path, let window = context.sharedContext.mainWindow else {
            return
        }
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
