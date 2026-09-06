import SwiftUI
import PhotosUI
import ProportionCore

/// The four capture paths behind one screen. Each hands an import job to
/// `ImportFlowView`, which ends on the review screen; nothing is saved
/// unseen.
struct CaptureView: View {
    @Environment(AppServices.self) private var services

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var link = ""
    @State private var pasted = ""
    @State private var showManual = false
    @State private var flow: Flow?

    struct Flow: Identifiable {
        let id = UUID()
        let title: String
        let job: @Sendable () async throws -> RecipeDraft
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 4, matching: .images) {
                        Label("Choose photos or screenshots", systemImage: "photo.on.rectangle")
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: {
                            Label("Photograph a page", systemImage: "camera")
                        }
                    }
                } header: {
                    Text("From a picture")
                } footer: {
                    Text("Text is read on your phone. A cookbook page, a handwritten card, or a screenshot of a caption all work.")
                }

                Section {
                    TextField("https://…", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(importLink)
                    Button("Import from link", action: importLink)
                        .disabled(URL(string: link.trimmingCharacters(in: .whitespaces))?.host == nil)
                } header: {
                    Text("From a link")
                } footer: {
                    Text("Recipe sites usually work directly. For Instagram, TikTok or YouTube, use the Share button in that app and choose Proportion — the caption is what gets read; videos are never downloaded.")
                }

                Section {
                    TextEditor(text: $pasted)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Pasted recipe text")
                    Button("Import pasted text", action: importPasted)
                        .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("From text")
                }

                Section {
                    Button { showManual = true } label: {
                        Label("Write it in", systemImage: "square.and.pencil")
                    }
                } footer: {
                    if !services.modelEnabled {
                        Text(services.hasModelKey
                             ? "Claude parsing is off in Settings; the built-in parser is used."
                             : "No Claude key configured; the built-in parser is used.")
                    }
                }
            }
            .navigationTitle("Capture")
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                photoItems = []
                // Load on the main actor first so the job only captures plain Data.
                Task {
                    var datas: [Data] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) }
                    }
                    guard !datas.isEmpty else { return }
                    let importer = services.importer
                    flow = Flow(title: "From photo") { try await importer.importImageData(datas) }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    guard let data = image.jpegData(compressionQuality: 0.9) else { return }
                    let importer = services.importer
                    flow = Flow(title: "From camera") { try await importer.importImageData([data]) }
                }
                .ignoresSafeArea()
            }
            .sheet(item: $flow) { flow in
                ImportFlowView(title: flow.title, job: flow.job)
            }
            .sheet(isPresented: $showManual) {
                NavigationStack { RecipeEditorView(mode: .blank) }
            }
        }
    }

    private func importLink() {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespaces)), url.host != nil else { return }
        let importer = services.importer
        flow = Flow(title: url.host ?? "Link") { try await importer.importURL(url) }
        link = ""
    }

    private func importPasted() {
        let text = pasted
        let importer = services.importer
        flow = Flow(title: "Pasted text") { try await importer.importText(text) }
        pasted = ""
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
