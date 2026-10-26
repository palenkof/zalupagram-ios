import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import PresentationDataUtils
import OverlayStatusController
import AnimatedStickerNode
import WebPBinding

// ZalupaGram fork: stickers as PNG (static ones, or the first frame) and
// GIF (animated and video ones), handed to the share sheet, where «Save
// Image» puts them into Photos.

public enum ZalupaGramStickerFormat {
    case png
    case gif
}

private func stickerFile(_ message: EngineMessage) -> TelegramMediaFile? {
    for media in message.media {
        if let file = media as? TelegramMediaFile, file.isSticker || file.isAnimatedSticker || file.isVideoSticker {
            return file
        }
    }
    return nil
}

public func zalupaGramStickerExportFormats(message: EngineMessage) -> [ZalupaGramStickerFormat] {
    guard let file = stickerFile(message) else {
        return []
    }
    if file.isAnimatedSticker || file.isVideoSticker {
        return [.gif, .png]
    }
    return [.png]
}

public func zalupaGramStickerExportTitle(_ format: ZalupaGramStickerFormat, strings: PresentationStrings) -> String {
    switch format {
    case .png:
        return ZalupaGram.tr(strings, "Save as PNG", "Сохранить как PNG")
    case .gif:
        return ZalupaGram.tr(strings, "Save as GIF", "Сохранить как GIF")
    }
}

private let stickerSide = 512
private let gifSide = 320
private let maxGifFrames = 300

private func makeImage(data: Data, width: Int, height: Int, bytesPerRow: Int, premultiplied: Bool) -> CGImage? {
    guard let provider = CGDataProvider(data: data as CFData) else {
        return nil
    }
    let alpha: CGImageAlphaInfo = premultiplied ? .premultipliedFirst : .first
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue | CGBitmapInfo.byteOrder32Little.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
}

private final class StickerFrames {
    let frameRate: Int
    let premultiplied: Bool
    private let make: () -> AnimatedStickerFrameSource?
    private var source: AnimatedStickerFrameSource?

    init(frameRate: Int, premultiplied: Bool, make: @escaping () -> AnimatedStickerFrameSource?) {
        self.frameRate = frameRate
        self.premultiplied = premultiplied
        self.make = make
        self.source = make()
    }

    // All frames once, the source loops by itself.
    func forEachFrame(_ body: (AnimatedStickerFrame) -> Void) {
        guard let source = self.source else {
            return
        }
        let count = source.frameCount
        var index = 0
        while index < maxGifFrames * 2 {
            if count > 0 && index >= count {
                break
            }
            guard let frame = source.takeFrame(draw: true) else {
                break
            }
            if frame.type != .argb {
                break
            }
            body(frame)
            index += 1
        }
        self.source = self.make()
    }
}

private func animatedFrames(file: TelegramMediaFile, path: String, side: Int, queue: Queue, context: AccountContext) -> StickerFrames? {
    if file.isVideoSticker {
        guard let probe = VideoStickerDirectFrameSource(queue: queue, path: path, width: side, height: side, cachePathPrefix: nil) else {
            return nil
        }
        return StickerFrames(frameRate: max(1, probe.frameRate), premultiplied: false, make: {
            return VideoStickerDirectFrameSource(queue: queue, path: path, width: side, height: side, cachePathPrefix: nil)
        })
    } else {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        let lottieSettings = context.lottieRenderingSettings
        guard let probe = AnimatedStickerDirectFrameSource(queue: queue, data: data, width: side, height: side, cachePathPrefix: nil, fitzModifier: nil, lottieSettings: lottieSettings) else {
            return nil
        }
        return StickerFrames(frameRate: max(1, probe.frameRate), premultiplied: true, make: {
            return AnimatedStickerDirectFrameSource(queue: queue, data: data, width: side, height: side, cachePathPrefix: nil, fitzModifier: nil, lottieSettings: lottieSettings)
        })
    }
}

// Runs on `queue`: the frame sources have to live on it.
private func convertSticker(file: TelegramMediaFile, path: String, format: ZalupaGramStickerFormat, queue: Queue, context: AccountContext) -> URL? {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("zalupagram-stickers", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let name = "sticker-\(file.fileId.id)"
    let isAnimated = file.isAnimatedSticker || file.isVideoSticker

    switch format {
    case .png:
        var image: UIImage?
        if isAnimated {
            if let frames = animatedFrames(file: file, path: path, side: stickerSide, queue: queue, context: context) {
                var first: CGImage?
                frames.forEachFrame { frame in
                    if first == nil {
                        first = makeImage(data: frame.data, width: frame.width, height: frame.height, bytesPerRow: frame.bytesPerRow, premultiplied: frames.premultiplied)
                    }
                }
                image = first.flatMap { UIImage(cgImage: $0) }
            }
        } else if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            image = WebP.convert(fromWebP: data) ?? UIImage(data: data)
        }
        guard let data = image?.pngData() else {
            return nil
        }
        let url = directory.appendingPathComponent(name + ".png")
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    case .gif:
        guard let frames = animatedFrames(file: file, path: path, side: gifSide, queue: queue, context: context) else {
            return nil
        }
        // GIF players don't keep up with 60 fps, take every second frame then.
        let step = max(1, frames.frameRate / 30)
        var count = 0
        var index = 0
        frames.forEachFrame { _ in
            if index % step == 0 && count < maxGifFrames {
                count += 1
            }
            index += 1
        }
        if count == 0 {
            return nil
        }
        let url = directory.appendingPathComponent(name + ".gif")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            return nil
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
        let delay = Double(step) / Double(frames.frameRate)
        let frameProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: delay, kCGImagePropertyGIFUnclampedDelayTime as String: delay]] as CFDictionary
        var added = 0
        index = 0
        frames.forEachFrame { frame in
            if index % step == 0 && added < count, let image = makeImage(data: frame.data, width: frame.width, height: frame.height, bytesPerRow: frame.bytesPerRow, premultiplied: frames.premultiplied) {
                CGImageDestinationAddImage(destination, image, frameProperties)
                added += 1
            }
            index += 1
        }
        if added != count || !CGImageDestinationFinalize(destination) {
            return nil
        }
        return url
    }
}

private func presentShareSheet(_ url: URL, context: AccountContext) {
    guard let window = context.sharedContext.mainWindow else {
        return
    }
    let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    if let popover = controller.popoverPresentationController {
        let view = window.hostView.containerView
        popover.sourceView = view
        popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
        popover.permittedArrowDirections = []
    }
    window.presentNative(controller)
}

public func zalupaGramExportSticker(context: AccountContext, message: EngineMessage, format: ZalupaGramStickerFormat) {
    guard let file = stickerFile(message) else {
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let statusController = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
    context.sharedContext.mainWindow?.present(statusController, on: .root)

    let fetchDisposable = context.engine.resources.fetch(reference: .media(media: .message(message: MessageReference(message._asMessage()), media: file), resource: file.resource), userLocation: .peer(message.id.peerId), userContentType: .sticker).startStandalone()
    let queue = Queue()
    let _ = (context.engine.resources.data(resource: EngineMediaResource(file.resource))
    |> filter { $0.isComplete }
    |> map { Optional($0) }
    |> take(1)
    |> timeout(30.0, queue: Queue.mainQueue(), alternate: .single(nil))
    |> deliverOn(queue)
    |> map { data -> URL? in
        guard let data else {
            return nil
        }
        return convertSticker(file: file, path: data.path, format: format, queue: queue, context: context)
    }
    |> deliverOnMainQueue).startStandalone(next: { url in
        fetchDisposable.dispose()
        statusController.dismiss()
        if let url {
            presentShareSheet(url, context: context)
        } else {
            let ru = zalupaGramIsRussian(presentationData.strings)
            context.sharedContext.mainWindow?.present(textAlertController(context: context, title: nil, text: ru ? "Не удалось сохранить стикер." : "Couldn't save the sticker.", actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), on: .root)
        }
    })
}
