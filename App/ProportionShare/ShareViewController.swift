import UIKit
import UniformTypeIdentifiers

/// The Share Extension. Receives a URL, text, or images from Safari, a social
/// app, or Photos, drops a `PendingImport` into the App Group container, and
/// tells the user to open Proportion.
///
/// It deliberately does no parsing: extensions have tight memory limits and
/// no network entitlement of their own, and the parse-review screen must run
/// in the app anyway. For social video links there is nothing to download —
/// the caption text the host app shares is what we use (see the spec).
final class ShareViewController: UIViewController {
    private let store = PendingImportStore()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        layout()
        Task { await handleShare() }
    }

    private func layout() {
        statusLabel.text = "Saving to Proportion…"
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.adjustsFontForContentSizeCategory = true
        spinner.startAnimating()

        let stack = UIStackView(arrangedSubviews: [spinner, statusLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func handleShare() async {
        guard store.isAvailable else {
            finish(message: "Proportion isn't set up to receive shares yet.", success: false)
            return
        }
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []

        var url: URL?
        var text: String?
        var images: [Data] = []

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), url == nil {
                url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier), text == nil {
                text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                if let data = await loadImageData(from: provider) { images.append(data) }
            }
        }

        // Social apps often share a caption as text alongside the link;
        // keep both so the app can use the caption when the page has no recipe.
        let item: PendingImport
        if let url {
            item = PendingImport(kind: .url, url: url, text: text)
        } else if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item = PendingImport(kind: .text, text: text)
        } else if !images.isEmpty {
            item = PendingImport(kind: .images)
        } else {
            finish(message: "Nothing here Proportion can read.", success: false)
            return
        }

        do {
            try store.save(item, images: images)
            finish(message: "Saved. Open Proportion to review the recipe.", success: true)
        } catch {
            finish(message: "Couldn't hand this to Proportion.", success: false)
        }
    }

    private func loadImageData(from provider: NSItemProvider) async -> Data? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) else { return nil }
        if let url = item as? URL, let image = UIImage(contentsOfFile: url.path) {
            return image.downsizedJPEGData()
        }
        if let image = item as? UIImage {
            return image.downsizedJPEGData()
        }
        if let data = item as? Data, let image = UIImage(data: data) {
            return image.downsizedJPEGData()
        }
        return nil
    }

    private func finish(message: String, success: Bool) {
        spinner.stopAnimating()
        statusLabel.text = message
        DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 0.9 : 1.6)) { [weak self] in
            if success {
                self?.extensionContext?.completeRequest(returningItems: nil)
            } else {
                self?.extensionContext?.cancelRequest(withError: NSError(domain: "Proportion.Share", code: 1))
            }
        }
    }
}

private extension UIImage {
    func downsizedJPEGData(maxEdge: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let longest = max(size.width, size.height)
        guard longest > maxEdge else { return jpegData(compressionQuality: quality) }
        let scale = maxEdge / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target)
            .image { _ in draw(in: CGRect(origin: .zero, size: target)) }
            .jpegData(compressionQuality: quality)
    }
}
