import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import ConvertOpusToAAC
import LocalAudioTranscription
import ZalupaGramCore

// ZalupaGram fork: voice and round video messages to text right on the phone
// with Apple speech recognition, without Premium (Whisper does it in Desktop).
// The text is stored in the message like the server transcription.

public var zalupaGramLocalTranscription: Bool {
    return ZalupaGramCore.option(.localTranscribe)
}

// Emits false if the media is not loaded yet or recognition failed.
public func zalupaGramTranscribeLocally(context: AccountContext, messageId: EngineMessage.Id, appLocale: String) -> Signal<Bool, NoError> {
    return context.engine.data.get(TelegramEngine.EngineData.Item.Messages.Message(id: messageId))
    |> mapToSignal { message -> Signal<(String, Bool)?, NoError> in
        guard let message, let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile else {
            return .single(nil)
        }
        return context.engine.resources.data(id: EngineMediaResource.Id(file.resource.id))
        |> take(1)
        |> map { data -> (String, Bool)? in
            return data.isComplete ? (data.path, file.isInstantVideo) : nil
        }
    }
    |> mapToSignal { value -> Signal<String?, NoError> in
        guard let (path, isVideo) = value else {
            Logger.shared.log("ZalupaGram", "transcription: \(messageId) media is not loaded")
            return .single(nil)
        }
        if isVideo {
            // Speech recognition reads the MP4 of a round video as is.
            return .single(path)
        }
        return convertOpusToAAC(sourcePath: path, allocateTempFile: {
            return EngineTempBox.shared.tempFile(fileName: "audio.m4a").path
        })
    }
    |> mapToSignal { path -> Signal<LocallyTranscribedAudio?, NoError> in
        guard let path else {
            return .single(nil)
        }
        return transcribeAudio(path: path, appLocale: appLocale)
    }
    |> mapToSignal { result -> Signal<Bool, NoError> in
        guard let result else {
            Logger.shared.log("ZalupaGram", "transcription: \(messageId) recognition failed")
            return .single(false)
        }
        return context.engine.messages.storeLocallyTranscribedAudio(messageId: messageId, text: result.text, isFinal: result.isFinal, error: nil)
        |> map { _ -> Bool in }
        |> then(.single(true))
    }
}
