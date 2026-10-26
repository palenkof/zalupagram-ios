import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import PresentationDataUtils
import OverlayStatusController

// ZalupaGram fork: updates from the private releases repo. iOS can't install
// an app by itself, so the new IPA is downloaded and handed to the share
// sheet: Save to Files and install with iloader on the PC, or open it in
// SideStore/AltStore on the phone.

private let latestReleaseUrl = URL(string: "https://api.github.com/repos/palenkof/zalupagram-ios-releases/releases/latest")!
private let lastCheckKey = "zg_update_last_check"
private let dismissedVersionKey = "zg_update_dismissed_version"
private let autoCheckInterval: Double = 6.0 * 60.0 * 60.0

private struct ReleaseInfo {
    let version: String
    let notes: String
    let assetUrl: URL
    let assetName: String
    let size: Int
}

private func updateToken() -> String? {
    if zalupaGramUpdateTokenMasked.isEmpty {
        return nil
    }
    let bytes = zip(zalupaGramUpdateTokenMasked, zalupaGramUpdateTokenKey).map { $0 ^ $1 }
    return String(bytes: bytes, encoding: .utf8)
}

private func versionParts(_ version: String) -> [Int] {
    var value = version
    if value.hasPrefix("v") {
        value.removeFirst()
    }
    return value.split(separator: ".").map { Int($0) ?? 0 }
}

private func isNewer(_ version: String, than current: String) -> Bool {
    let lhs = versionParts(version)
    let rhs = versionParts(current)
    for i in 0 ..< max(lhs.count, rhs.count) {
        let a = i < lhs.count ? lhs[i] : 0
        let b = i < rhs.count ? rhs[i] : 0
        if a != b {
            return a > b
        }
    }
    return false
}

// The asset link redirects to a signed storage URL, which must not get
// the GitHub token.
private final class ZalupaGramDownloadDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var request = request
        if request.url?.host != "api.github.com" {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(request)
    }
}

private func apiRequest(url: URL, token: String, accept: String) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue(accept, forHTTPHeaderField: "Accept")
    request.setValue("ZalupaGram-iOS", forHTTPHeaderField: "User-Agent")
    request.timeoutInterval = 30.0
    return request
}

private func fetchLatestRelease(token: String, completion: @escaping (ReleaseInfo?) -> Void) {
    let request = apiRequest(url: latestReleaseUrl, token: token, accept: "application/vnd.github+json")
    URLSession.shared.dataTask(with: request, completionHandler: { data, _, _ in
        var result: ReleaseInfo?
        if let data, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let tag = json["tag_name"] as? String, let assets = json["assets"] as? [[String: Any]] {
            for asset in assets {
                guard let name = asset["name"] as? String, name.hasSuffix(".ipa"), let urlString = asset["url"] as? String, let url = URL(string: urlString) else {
                    continue
                }
                result = ReleaseInfo(version: tag, notes: json["body"] as? String ?? "", assetUrl: url, assetName: name, size: asset["size"] as? Int ?? 0)
                break
            }
        }
        Queue.mainQueue().async {
            completion(result)
        }
    }).resume()
}

private func downloadRelease(_ release: ReleaseInfo, token: String, completion: @escaping (URL?) -> Void) {
    let request = apiRequest(url: release.assetUrl, token: token, accept: "application/octet-stream")
    let session = URLSession(configuration: .default, delegate: ZalupaGramDownloadDelegate(), delegateQueue: nil)
    session.downloadTask(with: request, completionHandler: { location, response, _ in
        var result: URL?
        if let location, let response = response as? HTTPURLResponse, response.statusCode == 200 {
            let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("zalupagram-update")
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(release.assetName)
            if (try? FileManager.default.moveItem(at: location, to: destination)) != nil {
                result = destination
            }
        }
        session.finishTasksAndInvalidate()
        Queue.mainQueue().async {
            completion(result)
        }
    }).resume()
}

private func present(_ controller: ViewController, context: AccountContext) {
    context.sharedContext.mainWindow?.present(controller, on: .root)
}

private func presentShareSheet(fileUrl: URL, context: AccountContext) {
    guard let window = context.sharedContext.mainWindow else {
        return
    }
    let activityController = UIActivityViewController(activityItems: [fileUrl], applicationActivities: nil)
    if let popover = activityController.popoverPresentationController {
        let view = window.hostView.containerView
        popover.sourceView = view
        popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
        popover.permittedArrowDirections = []
    }
    window.presentNative(activityController)
}

private func startDownload(_ release: ReleaseInfo, token: String, context: AccountContext) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let ru = zalupaGramIsRussian(presentationData.strings)
    let progress = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
    present(progress, context: context)
    downloadRelease(release, token: token, completion: { fileUrl in
        progress.dismiss()
        guard let fileUrl else {
            present(textAlertController(context: context, title: nil, text: ru ? "Не удалось скачать обновление. Попробуйте позже." : "Could not download the update. Try again later.", actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), context: context)
            return
        }
        presentShareSheet(fileUrl: fileUrl, context: context)
    })
}

private func presentUpdateAlert(_ release: ReleaseInfo, token: String, context: AccountContext) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let ru = zalupaGramIsRussian(presentationData.strings)
    let version = String(versionParts(release.version).map { String($0) }.joined(separator: "."))
    let sizeText = release.size > 0 ? String(format: ru ? " (%.0f МБ)" : " (%.0f MB)", Double(release.size) / 1024.0 / 1024.0) : ""
    var text = (ru ? "Доступна версия \(version)" : "Version \(version) is available") + sizeText + "."
    let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    if !notes.isEmpty {
        text += "\n\n" + notes
    }
    text += ru
        ? "\n\nIPA скачается и откроется меню «Поделиться»: сохраните в «Файлы» и поставьте через iloader на ПК или откройте в SideStore."
        : "\n\nThe IPA is downloaded and the share sheet opens: save it to Files and install with iloader on the PC, or open it in SideStore."
    present(textAlertController(context: context, title: "ZalupaGram", text: text, actions: [
        TextAlertAction(type: .genericAction, title: ru ? "Позже" : "Later", action: {
            UserDefaults.standard.set(release.version, forKey: dismissedVersionKey)
        }),
        TextAlertAction(type: .defaultAction, title: ru ? "Скачать" : "Download", action: {
            startDownload(release, token: token, context: context)
        })
    ], actionLayout: .vertical), context: context)
}

// Called when the app is ready (manual: false, at most every 6 hours, a
// version put off with «Later» is not offered again) and from the ZalupaGram
// settings (manual: true, always answers).
public func zalupaGramCheckForUpdates(context: AccountContext, manual: Bool) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let ru = zalupaGramIsRussian(presentationData.strings)
    guard let token = updateToken() else {
        if manual {
            present(textAlertController(context: context, title: nil, text: ru ? "В этой сборке нет токена обновлений." : "This build has no update token.", actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), context: context)
        }
        return
    }
    if !manual {
        let now = Date().timeIntervalSince1970
        if now - UserDefaults.standard.double(forKey: lastCheckKey) < autoCheckInterval {
            return
        }
        UserDefaults.standard.set(now, forKey: lastCheckKey)
    }
    fetchLatestRelease(token: token, completion: { release in
        guard let release else {
            if manual {
                present(textAlertController(context: context, title: nil, text: ru ? "Не удалось проверить обновления." : "Could not check for updates.", actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), context: context)
            }
            return
        }
        if isNewer(release.version, than: ZalupaGram.version) {
            if !manual && UserDefaults.standard.string(forKey: dismissedVersionKey) == release.version {
                return
            }
            presentUpdateAlert(release, token: token, context: context)
        } else if manual {
            present(textAlertController(context: context, title: nil, text: ru ? "У вас последняя версия: \(ZalupaGram.version)." : "You have the latest version: \(ZalupaGram.version).", actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), context: context)
        }
    })
}
