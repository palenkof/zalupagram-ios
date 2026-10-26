import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import AccountContext

// ZalupaGram fork: backup of the ZalupaGram options (everything kept in
// UserDefaults under zg_*, except the updater state) to a JSON file and back.

private let backupFormat = "zalupagram-ios-settings"
private let skippedKeys: Set<String> = ["zg_update_last_check", "zg_update_dismissed_version"]

private func optionKeys() -> [String] {
    return UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix("zg_") && !skippedKeys.contains($0) }.sorted()
}

private func presentNative(_ controller: UIViewController, context: AccountContext) {
    guard let window = context.sharedContext.mainWindow else {
        return
    }
    if let popover = controller.popoverPresentationController {
        let view = window.hostView.containerView
        popover.sourceView = view
        popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
        popover.permittedArrowDirections = []
    }
    window.presentNative(controller)
}

public func zalupaGramExportSettings(context: AccountContext) {
    var options: [String: Any] = [:]
    for key in optionKeys() {
        if let value = UserDefaults.standard.object(forKey: key), JSONSerialization.isValidJSONObject([value]) {
            options[key] = value
        }
    }
    let root: [String: Any] = [
        "format": backupFormat,
        "version": ZalupaGram.version,
        "options": options,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
        return
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ZalupaGram-settings-\(formatter.string(from: Date())).json")
    guard (try? data.write(to: url)) != nil else {
        return
    }
    presentNative(UIActivityViewController(activityItems: [url], applicationActivities: nil), context: context)
}

private final class ZalupaGramDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    let completion: (URL?) -> Void

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.completion(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.completion(nil)
    }
}

private var currentPickerDelegate: ZalupaGramDocumentPickerDelegate?

// Calls completion with the number of restored options, nil if the file
// is not a ZalupaGram settings backup, nothing if cancelled.
public func zalupaGramImportSettings(context: AccountContext, completion: @escaping (Int?) -> Void) {
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.json], asCopy: true)
    let delegate = ZalupaGramDocumentPickerDelegate(completion: { url in
        currentPickerDelegate = nil
        guard let url else {
            return
        }
        guard let data = try? Data(contentsOf: url), let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], root["format"] as? String == backupFormat, let options = root["options"] as? [String: Any] else {
            completion(nil)
            return
        }
        var count = 0
        for (key, value) in options where key.hasPrefix("zg_") && !skippedKeys.contains(key) {
            UserDefaults.standard.set(value, forKey: key)
            count += 1
        }
        completion(count)
    })
    currentPickerDelegate = delegate
    picker.delegate = delegate
    presentNative(picker, context: context)
}
