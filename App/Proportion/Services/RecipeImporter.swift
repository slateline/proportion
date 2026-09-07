import Foundation
import UIKit
import ProportionCore

/// Orchestrates every capture path into a `RecipeDraft` for the review screen.
///
/// Order of preference on each path is always: exact structured data (JSON-LD),
/// then deterministic parsing, then the model — and the model only when the
/// user has allowed it. Nothing here saves anything; the draft goes to
/// parse-review first.
struct RecipeImporter: Sendable {
    var session: URLSession = .shared
    var jsonLD = JSONLDRecipeExtractor()
    var htmlText = HTMLTextExtractor()
    var textParser = PlainTextRecipeParser()
    var ocr = OCRService()
    var claude: ClaudeRecipeParser?
    /// Read at call time so a Settings change applies immediately.
    var allowsModel: @Sendable () -> Bool = { false }

    /// Below this the deterministic parse is shown only if the model can't do better.
    static let confidentThreshold = 0.6

    enum ImportError: LocalizedError {
        case emptyInput
        case nothingFound(fallbackText: String?)
        case pageUnreachable(URL)
        case imageUnreadable

        var errorDescription: String? {
            switch self {
            case .emptyInput: return "There's nothing to import."
            case .nothingFound: return "No recipe could be found there."
            case .pageUnreachable(let url): return "Couldn't load \(url.host ?? "that page")."
            case .imageUnreadable: return "Couldn't read any text in that image."
            }
        }
    }

    // MARK: URL

    func importURL(_ url: URL, captionText: String? = nil) async throws -> RecipeDraft {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Proportion/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

        let html: String
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
                throw ImportError.pageUnreachable(url)
            }
            html = String(decoding: data, as: UTF8.self)
        } catch let error as ImportError {
            throw error
        } catch {
            // Social links often can't be fetched at all. Fall through to the
            // shared caption if there is one rather than dead-ending.
            if let captionText, !captionText.isEmpty {
                return try await importText(captionText, sourceURL: url, source: .shareExtension)
            }
            throw ImportError.pageUnreachable(url)
        }

        if let draft = jsonLD.extract(fromHTML: html, pageURL: url) {
            return draft
        }

        let extracted = htmlText.extract(from: html)
        var text = extracted.text
        if let captionText, !captionText.isEmpty {
            text = captionText + "\n\n" + text
        }
        var draft = try await importText(text, sourceURL: url, source: .shareExtension)
        if draft.title == "Untitled recipe", let title = extracted.title {
            draft.title = Self.cleanPageTitle(title)
        }
        return draft
    }

    // MARK: Text

    func importText(_ text: String, sourceURL: URL? = nil, source: RecipeDraft.Source = .pastedText) async throws -> RecipeDraft {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyInput }

        let heuristic = textParser.parse(trimmed, sourceURL: sourceURL, source: source)
        if let heuristic, (heuristic.parseConfidence ?? 0) >= Self.confidentThreshold {
            return heuristic
        }

        if allowsModel(), let claude {
            do {
                var draft = try await claude.parse(text: trimmed, sourceURL: sourceURL)
                if source == .ocr { draft.source = .ocr }
                return draft
            } catch {
                if let heuristic {
                    return heuristic.flagged("Claude couldn't read this (\(error.localizedDescription)). Showing the built-in parse instead — check every line.")
                }
                throw ImportError.nothingFound(fallbackText: trimmed)
            }
        }

        if let heuristic { return heuristic }
        throw ImportError.nothingFound(fallbackText: trimmed)
    }

    // MARK: Images

    func importImages(_ images: [UIImage]) async throws -> RecipeDraft {
        guard !images.isEmpty else { throw ImportError.emptyInput }

        let recognised = try? await ocr.recognizeText(in: images)
        if let recognised, recognised.isUsable {
            do {
                return try await importText(recognised.text, source: .ocr)
            } catch {
                // Text was readable but not a recipe by our heuristics; the
                // vision path below may still make sense of the layout.
            }
        }

        if allowsModel(), let claude {
            let jpegs = images.compactMap { $0.downsizedJPEGData() }
            let hint = recognised.map { "On-device OCR read: \($0.text.prefix(2000))" }
            return try await claude.parse(images: jpegs, hint: hint)
        }

        if let recognised, !recognised.text.isEmpty {
            throw ImportError.nothingFound(fallbackText: recognised.text)
        }
        throw ImportError.imageUnreadable
    }

    /// Convenience for callers holding encoded images (the photo picker, the
    /// App Group hand-off); `Data` crosses task boundaries without ceremony.
    func importImageData(_ data: [Data]) async throws -> RecipeDraft {
        try await importImages(data.compactMap(UIImage.init(data:)))
    }

    // MARK: Share Extension hand-off

    func importPending(_ item: PendingImport, store: PendingImportStore) async throws -> RecipeDraft {
        switch item.kind {
        case .url:
            guard let url = item.url else { throw ImportError.emptyInput }
            return try await importURL(url, captionText: item.text)
        case .text:
            return try await importText(item.text ?? "", source: .shareExtension)
        case .images:
            return try await importImageData(store.imageData(for: item))
        }
    }

    static func cleanPageTitle(_ title: String) -> String {
        // "Best Pancakes | Some Site" → "Best Pancakes"
        let separators = [" | ", " - ", " – ", " — ", " : "]
        for separator in separators {
            if let range = title.range(of: separator) {
                return String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return title
    }
}

private extension RecipeDraft {
    func flagged(_ warning: String) -> RecipeDraft {
        var copy = self
        copy.warnings.append(warning)
        return copy
    }
}
