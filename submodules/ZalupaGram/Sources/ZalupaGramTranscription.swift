import Foundation
import AVFoundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import TelegramPresentationData
import PresentationDataUtils
import ConvertOpusToAAC
import LocalAudioTranscription
import ZalupaGramCore

// ZalupaGram fork: voice and round video messages to text right on the phone
// with Apple speech recognition, without Premium (Whisper does it in Desktop).
// The text is stored in the message like the server transcription.

public var zalupaGramLocalTranscription: Bool {
    return ZalupaGramCore.option(.localTranscribe)
}

// Apple's recognizer is unreliable on long audio: it is cut into pieces of
// this length and the texts are joined.
private let chunkSeconds: Double = 50.0

private func tempPath(_ ext: String) -> String {
    return NSTemporaryDirectory() + "zg-transcribe-\(UInt64.random(in: 0 ... UInt64.max)).\(ext)"
}

// Exports the pieces one after another, the export calls back on its own queue.
private final class AudioChunkExporter {
    private let asset: AVURLAsset
    private let duration: Double
    private let completion: ([String]?) -> Void
    private var paths: [String] = []

    init(asset: AVURLAsset, duration: Double, completion: @escaping ([String]?) -> Void) {
        self.asset = asset
        self.duration = duration
        self.completion = completion
    }

    func start() {
        self.exportNext()
    }

    private func exportNext() {
        let start = Double(self.paths.count) * chunkSeconds
        if start >= self.duration - 0.2 {
            self.completion(self.paths.isEmpty ? nil : self.paths)
            return
        }
        guard let session = AVAssetExportSession(asset: self.asset, presetName: AVAssetExportPresetAppleM4A) else {
            self.completion(nil)
            return
        }
        let path = tempPath("m4a")
        session.outputURL = URL(fileURLWithPath: path)
        session.outputFileType = .m4a
        session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 1000), duration: CMTime(seconds: min(chunkSeconds, self.duration - start), preferredTimescale: 1000))
        session.exportAsynchronously { [self] in
            if session.status == .completed {
                self.paths.append(path)
                self.exportNext()
            } else {
                Logger.shared.log("ZalupaGram", "transcription: export failed \(String(describing: session.error))")
                self.completion(nil)
            }
        }
    }
}

// The sound of the media as m4a pieces, nil if there is no sound at all
// (a silent round video crashed the recognizer).
private func audioChunks(path: String, isVideo: Bool) -> Signal<[String]?, NoError> {
    return Signal { subscriber in
        // The cache file has no extension, AVFoundation needs one.
        let source = tempPath(isVideo ? "mp4" : "m4a")
        guard (try? FileManager.default.copyItem(atPath: path, toPath: source)) != nil else {
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        let asset = AVURLAsset(url: URL(fileURLWithPath: source))
        let duration = CMTimeGetSeconds(asset.duration)
        if asset.tracks(withMediaType: .audio).isEmpty || !duration.isFinite || duration <= 0.0 {
            Logger.shared.log("ZalupaGram", "transcription: no sound")
            subscriber.putNext(nil)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        if !isVideo && duration <= chunkSeconds {
            subscriber.putNext([source])
            subscriber.putCompletion()
            return EmptyDisposable
        }
        let exporter = AudioChunkExporter(asset: asset, duration: duration, completion: { paths in
            subscriber.putNext(paths)
            subscriber.putCompletion()
        })
        exporter.start()
        return EmptyDisposable
    }
    |> runOn(Queue.concurrentDefaultQueue())
}

// The pieces one after another, the texts joined. Nil if nothing was recognized.
private func transcribeChunks(_ paths: [String], appLocale: String) -> Signal<LocallyTranscribedAudio?, NoError> {
    var signal: Signal<[String], NoError> = .single([])
    for path in paths {
        signal = signal |> mapToSignal { texts -> Signal<[String], NoError> in
            return transcribeAudio(path: path, appLocale: appLocale)
            |> filter { $0?.isFinal ?? true }
            |> take(1)
            |> map { result -> [String] in
                if let text = result?.text, !text.isEmpty {
                    return texts + [text]
                }
                return texts
            }
        }
    }
    return signal
    |> map { texts -> LocallyTranscribedAudio? in
        if texts.isEmpty {
            return nil
        }
        return LocallyTranscribedAudio(text: texts.joined(separator: " "), isFinal: true)
    }
}

private enum TranscriptionFailure {
    case notLoaded
    case noSound
    case notRecognized
}

private final class TranscriptionFailureBox {
    var value: TranscriptionFailure = .notRecognized
}

private func presentTranscriptionFailure(_ failure: TranscriptionFailure, context: AccountContext) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let ru = zalupaGramIsRussian(presentationData.strings)
    let text: String
    switch failure {
    case .notLoaded:
        text = ru ? "Не удалось загрузить сообщение для расшифровки." : "Couldn't load the message to transcribe it."
    case .noSound:
        text = ru ? "В этом кружке нет звука." : "This video message has no sound."
    case .notRecognized:
        text = ru ? "iOS не распознал речь. Проверьте, что в Настройках iPhone разрешено распознавание речи для ZalupaGram и включена диктовка." : "iOS didn't recognize speech. Check that speech recognition is allowed for ZalupaGram and dictation is on in iPhone Settings."
    }
    context.sharedContext.mainWindow?.present(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), on: .root)
}

// Emits false if the media couldn't be loaded or recognition failed, the
// reason is shown to the user.
public func zalupaGramTranscribeLocally(context: AccountContext, messageId: EngineMessage.Id, appLocale: String) -> Signal<Bool, NoError> {
    let failure = TranscriptionFailureBox()
    return context.engine.data.get(TelegramEngine.EngineData.Item.Messages.Message(id: messageId))
    |> mapToSignal { message -> Signal<(String, Bool)?, NoError> in
        guard let message, let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile else {
            return .single(nil)
        }
        // A round video that only played may be loaded partly: load all of it.
        let fetchDisposable = context.engine.resources.fetch(reference: .media(media: .message(message: MessageReference(message._asMessage()), media: file), resource: file.resource), userLocation: .peer(message.id.peerId), userContentType: MediaResourceUserContentType(file: file)).startStandalone()
        return context.engine.resources.data(resource: EngineMediaResource(file.resource))
        |> filter { $0.isComplete }
        |> take(1)
        |> map { data -> (String, Bool)? in
            return (data.path, file.isInstantVideo)
        }
        |> timeout(60.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))
        |> afterDisposed {
            fetchDisposable.dispose()
        }
    }
    |> mapToSignal { value -> Signal<[String]?, NoError> in
        guard let (path, isVideo) = value else {
            Logger.shared.log("ZalupaGram", "transcription: \(messageId) media is not loaded")
            failure.value = .notLoaded
            return .single(nil)
        }
        if isVideo {
            return audioChunks(path: path, isVideo: true)
            |> map { paths -> [String]? in
                if paths == nil {
                    failure.value = .noSound
                }
                return paths
            }
        }
        return convertOpusToAAC(sourcePath: path, allocateTempFile: {
            return EngineTempBox.shared.tempFile(fileName: "audio.m4a").path
        })
        |> mapToSignal { path -> Signal<[String]?, NoError> in
            guard let path else {
                return .single(nil)
            }
            return audioChunks(path: path, isVideo: false)
        }
    }
    |> mapToSignal { paths -> Signal<LocallyTranscribedAudio?, NoError> in
        guard let paths, !paths.isEmpty else {
            return .single(nil)
        }
        return transcribeChunks(paths, appLocale: appLocale)
    }
    |> mapToSignal { result -> Signal<Bool, NoError> in
        guard let result else {
            Logger.shared.log("ZalupaGram", "transcription: \(messageId) failed: \(failure.value)")
            let reason = failure.value
            Queue.mainQueue().async {
                presentTranscriptionFailure(reason, context: context)
            }
            return .single(false)
        }
        return context.engine.messages.storeLocallyTranscribedAudio(messageId: messageId, text: result.text, isFinal: result.isFinal, error: nil)
        |> map { _ -> Bool in }
        |> then(.single(true))
    }
}
