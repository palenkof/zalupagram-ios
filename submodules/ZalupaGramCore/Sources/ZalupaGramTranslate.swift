import Foundation

// ZalupaGram fork: free translation through Google instead of the Telegram
// server, the same as in ZalupaGram Desktop (zg_translate.cpp). Used by
// TelegramCore when the freeTranslation option is on. Formatting of the
// translated text is not kept.
public enum ZalupaGramTranslate {
    private static let chunkLimit = 4000

    // Splits long texts by paragraphs, then lines, then hard.
    private static func split(_ text: String) -> [String] {
        var result: [String] = []
        var rest = Substring(text)
        while rest.count > chunkLimit {
            let window = rest.prefix(chunkLimit)
            let half = window.index(window.startIndex, offsetBy: chunkLimit / 2)
            var cut = window.endIndex
            for separator in ["\n\n", "\n", " "] {
                if let range = window.range(of: separator, options: .backwards), range.lowerBound >= half {
                    cut = range.upperBound
                    break
                }
            }
            result.append(String(rest[..<cut]))
            rest = rest[cut...]
        }
        if !rest.isEmpty {
            result.append(String(rest))
        }
        return result
    }

    // Response: [[["translated","original",...], ...], null, "en", ...].
    private static func parse(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data), let root = json as? [Any], let segments = root.first as? [Any] else {
            return nil
        }
        var result = ""
        for segment in segments {
            // Skip transliteration and other entries without a translation.
            if let segment = segment as? [Any], let text = segment.first as? String {
                result += text
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func requestChunk(_ text: String, to language: String, completion: @escaping (String?) -> Void) {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: language),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20.0
        request.setValue("application/x-www-form-urlencoded;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        request.httpBody = ("q=" + encoded).data(using: .utf8)
        URLSession.shared.dataTask(with: request, completionHandler: { data, response, _ in
            if let data, let response = response as? HTTPURLResponse, response.statusCode == 200 {
                completion(parse(data))
            } else {
                completion(nil)
            }
        }).resume()
    }

    // Two letters (or zh-CN style) language code of the target language.
    private static func googleLanguage(_ language: String) -> String {
        var value = language
        if value.hasSuffix("-raw") {
            value.removeLast(4)
        }
        if value.lowercased().hasPrefix("zh") {
            return value.lowercased().contains("hant") || value.lowercased().contains("tw") ? "zh-TW" : "zh-CN"
        }
        return String(value.prefix(while: { $0 != "-" && $0 != "_" }))
    }

    public static func translate(_ text: String, to language: String, completion: @escaping (String?) -> Void) {
        let chunks = split(text)
        if chunks.isEmpty {
            completion(nil)
            return
        }
        let target = googleLanguage(language)
        var results: [String] = []
        func next() {
            if results.count == chunks.count {
                completion(results.joined())
                return
            }
            requestChunk(chunks[results.count], to: target, completion: { result in
                guard let result else {
                    completion(nil)
                    return
                }
                results.append(result)
                next()
            })
        }
        next()
    }

    // One by one, nil for the texts that failed.
    public static func translate(_ texts: [String], to language: String, completion: @escaping ([String?]) -> Void) {
        var results: [String?] = []
        func next() {
            if results.count == texts.count {
                completion(results)
                return
            }
            let text = texts[results.count]
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                results.append(text)
                next()
                return
            }
            translate(text, to: language, completion: { result in
                results.append(result)
                next()
            })
        }
        next()
    }
}
