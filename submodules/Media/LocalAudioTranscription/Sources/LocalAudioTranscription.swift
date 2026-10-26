import Foundation
import SwiftSignalKit
import Speech

private var sharedRecognizers: [String: NSObject] = [:]

private struct TranscriptionResult {
    var text: String
    var confidence: Float
    var isFinal: Bool
}

// ZalupaGram: the recognizer starts the text over after a pause, so a long
// message ended up with its last part only. The parts are glued back here.
private final class ZalupaGramTranscriptionParts {
    var committed: [String] = []
    var current: String = ""

    private static func firstWord(_ text: String) -> Substring {
        return text.split(separator: " ", maxSplits: 1).first ?? ""
    }

    func update(_ text: String) {
        if !self.current.isEmpty && text.count < self.current.count && ZalupaGramTranscriptionParts.firstWord(text).lowercased() != ZalupaGramTranscriptionParts.firstWord(self.current).lowercased() {
            self.committed.append(self.current)
        }
        self.current = text
    }

    var text: String {
        return (self.committed + [self.current]).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

private func transcribeAudio(path: String, locale: String) -> Signal<TranscriptionResult?, NoError> {
    return Signal { subscriber in
        let disposable = MetaDisposable()
        
        if #available(iOS 13.0, *) {
            SFSpeechRecognizer.requestAuthorization { status in
                Queue.mainQueue().async {
                    switch status {
                    case .notDetermined:
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                    case .restricted:
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                    case .denied:
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                    case .authorized:
                        let speechRecognizer: SFSpeechRecognizer
                        if let sharedRecognizer = sharedRecognizers[locale] as? SFSpeechRecognizer {
                            speechRecognizer = sharedRecognizer
                        } else {
                            guard let speechRecognizerValue = SFSpeechRecognizer(locale: Locale(identifier: locale)), speechRecognizerValue.isAvailable else {
                                subscriber.putNext(nil)
                                subscriber.putCompletion()
                                
                                return
                            }
                            speechRecognizerValue.defaultTaskHint = .dictation
                            sharedRecognizers[locale] = speechRecognizerValue
                            speechRecognizer = speechRecognizerValue
                            
                            // ZalupaGram: keep what the recognizer supports, so languages
                            // without an on-device model are recognized on Apple's servers.
                        }
                        
                        let tempFilePath = NSTemporaryDirectory() + "/\(UInt64.random(in: 0 ... UInt64.max)).m4a"
                        let _ = try? FileManager.default.copyItem(atPath: path, toPath: tempFilePath)
                        
                        let request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: tempFilePath))
                        if #available(iOS 16.0, *) {
                            request.addsPunctuation = true
                        }
                        request.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
                        // ZalupaGram: partial results to notice where the text starts over.
                        request.shouldReportPartialResults = true
                        let parts = ZalupaGramTranscriptionParts()

                        let task = speechRecognizer.recognitionTask(with: request, resultHandler: { result, error in
                            if let result = result {
                                parts.update(result.bestTranscription.formattedString)
                                if result.isFinal {
                                    var confidence: Float = 0.0
                                    for segment in result.bestTranscription.segments {
                                        confidence += segment.confidence
                                    }
                                    confidence /= Float(max(1, result.bestTranscription.segments.count))
                                    subscriber.putNext(TranscriptionResult(text: parts.text, confidence: confidence, isFinal: true))
                                    subscriber.putCompletion()
                                }
                            } else {
                                print("transcribeAudio: locale: \(locale), error: \(String(describing: error))")

                                // ZalupaGram: keep what was recognized before the error.
                                let text = parts.text
                                subscriber.putNext(text.isEmpty ? nil : TranscriptionResult(text: text, confidence: 0.5, isFinal: true))
                                subscriber.putCompletion()
                            }
                        })
                        
                        disposable.set(ActionDisposable {
                            task.cancel()
                        })
                    @unknown default:
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                    }
                }
            }
        } else {
            subscriber.putNext(nil)
            subscriber.putCompletion()
        }
        
        return disposable
    }
    |> runOn(.mainQueue())
}

public struct LocallyTranscribedAudio {
    public var text: String
    public var isFinal: Bool
}

public func transcribeAudio(path: String, appLocale: String) -> Signal<LocallyTranscribedAudio?, NoError> {
    var signals: [Signal<TranscriptionResult?, NoError>] = []
    var locales: [String] = []
    if !locales.contains(Locale.current.identifier) {
        locales.append(Locale.current.identifier)
    }
    if locales.isEmpty {
        locales.append("en-US")
    }
    for locale in locales {
        signals.append(transcribeAudio(path: path, locale: locale))
    }
    var resultSignal: Signal<[TranscriptionResult?], NoError> = .single([])
    for signal in signals {
        resultSignal = resultSignal |> mapToSignal { result -> Signal<[TranscriptionResult?], NoError> in
            return signal |> map { next in
                return result + [next]
            }
        }
    }
    
    return resultSignal
    |> map { results -> LocallyTranscribedAudio? in
        let sortedResults = results.compactMap({ $0 }).sorted(by: { lhs, rhs in
            return lhs.confidence > rhs.confidence
        })
        return sortedResults.first.flatMap { result -> LocallyTranscribedAudio in
            return LocallyTranscribedAudio(text: result.text, isFinal: result.isFinal)
        }
    }
}
