import SwiftUI
import UIKit
import VisionKit

struct SubjectPickerView: View {
    let sourceImage: UIImage
    var service = SubjectSegmentationService()
    let onUseOriginal: (UIImage) -> Void
    let onConfirmCutout: (UIImage, SubjectCandidate) -> Void

    @State private var analysis: SubjectSegmentationAnalysis?
    @State private var selection = SubjectSelectionState(candidates: [])
    @State private var error: SubjectSegmentationError?
    @State private var isLoading = true
    @State private var isConfirming = false
    @State private var requestID = UUID()
    @State private var confirmationTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if let analysis {
                    SubjectInteractionView(
                        image: sourceImage,
                        analysis: analysis,
                        selectedID: selection.selectedID,
                        onSubjectTap: selectSubject,
                        onNormalizedTap: { selection.select(at: $0) }
                    )
                } else {
                    Image(uiImage: sourceImage)
                        .resizable()
                        .scaledToFit()
                        .overlay { if isLoading { ProgressView("Finding subjects…") } }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if let error {
                Text(error.localizedDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Button("Use original photo") { onUseOriginal(sourceImage) }
                    .buttonStyle(.bordered)

                Button("Confirm cutout") { confirmCutout() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.selectedID == nil || isConfirming)
            }
        }
        .padding()
        .task(id: imageIdentity) { await loadAnalysis() }
        .onDisappear {
            requestID = UUID()
            confirmationTask?.cancel()
            confirmationTask = nil
        }
    }

    private var imageIdentity: ObjectIdentifier { ObjectIdentifier(sourceImage) }

    private func selectSubject(_ subject: ImageAnalysisInteraction.Subject) {
        guard let id = analysis?.candidateID(for: subject) else { return }
        selection.select(id: id)
    }

    private func loadAnalysis() async {
        let currentRequest = UUID()
        requestID = currentRequest
        confirmationTask?.cancel()
        confirmationTask = nil
        isConfirming = false
        analysis = nil
        selection = SubjectSelectionState(candidates: [])
        error = nil
        isLoading = true
        do {
            let result = try await service.analyze(sourceImage)
            try Task.checkCancellation()
            guard requestID == currentRequest else { return }
            analysis = result
            selection.updateCandidates(result.candidates)
        } catch is CancellationError {
            return
        } catch let segmentationError as SubjectSegmentationError {
            guard requestID == currentRequest else { return }
            error = segmentationError
        } catch {
            guard requestID == currentRequest else { return }
            self.error = .analysisFailed
        }
        if requestID == currentRequest { isLoading = false }
    }

    private func confirmCutout() {
        guard let analysis, let selectedID = selection.selectedID,
              let candidate = selection.candidates.first(where: { $0.id == selectedID }) else { return }
        isConfirming = true
        error = nil
        let currentRequest = requestID
        confirmationTask?.cancel()
        confirmationTask = Task {
            do {
                let cutout = try await analysis.cutout(for: selectedID)
                try Task.checkCancellation()
                guard requestID == currentRequest else { return }
                onConfirmCutout(cutout, candidate)
            } catch is CancellationError {
                return
            } catch let segmentationError as SubjectSegmentationError {
                guard requestID == currentRequest else { return }
                error = segmentationError
            } catch {
                guard requestID == currentRequest else { return }
                self.error = .analysisFailed
            }
            if requestID == currentRequest { isConfirming = false }
        }
    }
}

private struct SubjectInteractionView: UIViewRepresentable {
    let image: UIImage
    let analysis: SubjectSegmentationAnalysis
    let selectedID: SubjectCandidate.ID?
    let onSubjectTap: (ImageAnalysisInteraction.Subject) -> Void
    let onNormalizedTap: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTap(_:))))
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        context.coordinator.parent = self
        imageView.image = image
        if analysis.interaction.view !== imageView {
            imageView.addInteraction(analysis.interaction)
        }
        analysis.interaction.highlightedSubjects = analysis.subjects(for: selectedID.map { [$0] } ?? [])
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SubjectInteractionView
        init(parent: SubjectInteractionView) { self.parent = parent }

        @objc func didTap(_ recognizer: UITapGestureRecognizer) {
            guard let imageView = recognizer.view as? UIImageView else { return }
            let point = recognizer.location(in: imageView)
            let snapshot = parent
            Task { @MainActor in
                if let subject = await snapshot.analysis.interaction.subject(at: point) {
                    snapshot.onSubjectTap(subject)
                    return
                }
                let geometry = AspectFitGeometry(imageSize: snapshot.image.size, containerSize: imageView.bounds.size)
                if let normalized = geometry.normalizedPoint(for: point) {
                    snapshot.onNormalizedTap(normalized)
                }
            }
        }
    }
}
