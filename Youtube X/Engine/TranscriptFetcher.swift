//
//  TranscriptFetcher.swift
//  Youtube X
//
//  Created by fizzyg on 8/7/26.
//

import Foundation
import WebKit

class TranscriptFetcher: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var completion: (([TranscriptLine]) -> Void)?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
    }

    func fetchTranscript(for videoId: String, completion: @escaping ([TranscriptLine]) -> Void) {
        self.completion = completion
        webView.load(URLRequest(url: URL(string: "https://www.youtube.com/watch?v=\(videoId)")!))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let js = """
        (function() {
            try {
                const playerResponse = JSON.parse(document.querySelector('script[type="application/json"]')?.textContent || '{}');
                const captions = playerResponse.playerResponse?.captions?.playerCaptionsTracklistRenderer?.captionTracks;
                if (captions && captions.length) {
                    // Return the first English track URL (or first available)
                    const track = captions.find(t => t.languageCode === 'en') || captions[0];
                    return JSON.stringify({url: track.baseUrl, language: track.languageCode});
                }
            } catch(e) {}
            return JSON.stringify({error: 'No captions found'});
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self = self, let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self?.completion?([])
                return
            }
            if let urlString = dict["url"] as? String {
                self.downloadAndParseTranscript(urlString)
            } else {
                self.completion?([])
            }
        }
    }

    private func downloadAndParseTranscript(_ urlString: String) {
        guard let url = URL(string: urlString) else { completion?([]); return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, let xml = String(data: data, encoding: .utf8) else {
                self?.completion?([])
                return
            }
            let lines = self?.parseSRT(xml) ?? []
            DispatchQueue.main.async { self?.completion?(lines) }
        }.resume()
    }

    private func parseSRT(_ xml: String) -> [TranscriptLine] {
        // YouTube sends XML with <text> tags
        var lines = [TranscriptLine]()
        let pattern = "<text start=\"([^\"]+)\" dur=\"[^\"]+\">([^<]+)</text>"
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(xml.startIndex..., in: xml)
        regex?.enumerateMatches(in: xml, range: range) { match, _, _ in
            guard let match = match,
                  let timeRange = Range(match.range(at: 1), in: xml),
                  let textRange = Range(match.range(at: 2), in: xml) else { return }
            if let start = Double(xml[timeRange]) {
                let text = String(xml[textRange]).decodingHTMLEntities()
                lines.append(TranscriptLine(time: start, text: text))
            }
        }
        return lines
    }
}

extension String {
    func decodingHTMLEntities() -> String {
        guard let data = data(using: .utf8) else { return self }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string
        }
        return self
    }
}
