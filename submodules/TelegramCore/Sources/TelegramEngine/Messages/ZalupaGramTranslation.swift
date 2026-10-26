import Foundation
import SwiftSignalKit
import ZalupaGramCore

// ZalupaGram fork: Google translation as a signal, nil for the texts that failed.
func zalupaGramGoogleTranslate(_ texts: [String], toLang: String) -> Signal<[String?], NoError> {
    return Signal { subscriber in
        ZalupaGramTranslate.translate(texts, to: toLang, completion: { results in
            subscriber.putNext(results)
            subscriber.putCompletion()
        })
        return EmptyDisposable
    }
}
