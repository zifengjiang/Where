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
    @State private var completionCoordinator = SubjectPickerCompletionCoordinator()

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

            if analysis != nil {
                Text("Tap an object to choose its cutout.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(selection.accessibilityCandidates, id: \.candidateID) { descriptor in
                            Button {
                                selectCandidate(id: descriptor.candidateID, announcement: descriptor.label)
                            } label: {
                                Text(descriptor.label)
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(descriptor.isSelected ? .accentColor : .secondary)
                            .accessibilityValue(descriptor.value)
                            .accessibilityAddTraits(descriptor.isSelected ? .isSelected : [])
                            .disabled(completionCoordinator.isCompleted)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            HStack {
                Button("Use original photo") { useOriginal() }
                    .buttonStyle(.bordered)
                    .disabled(completionCoordinator.isCompleted)

                Button("Confirm cutout") { confirmCutout() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.selectedID == nil || isConfirming || completionCoordinator.isCompleted)
            }
        }
        .padding()
        .task(id: imageIdentity) { await loadAnalysis() }
        .onChange(of: error) { _, newError in
            guard let newError else { return }
            UIAccessibility.post(notification: .announcement, argument: newError.localizedDescription)
        }
        .onDisappear {
            requestID = UUID()
            confirmationTask?.cancel()
            confirmationTask = nil
            completionCoordinator.cancelPendingConfirmation()
        }
    }

    private var imageIdentity: ObjectIdentifier { ObjectIdentifier(sourceImage) }

    private func selectSubject(_ subject: ImageAnalysisInteraction.Subject) {
        guard let id = analysis?.candidateID(for: subject) else { return }
        selectCandidate(id: id)
    }

    private func selectCandidate(id: SubjectCandidate.ID, announcement: String? = nil) {
        guard !completionCoordinator.isCompleted else { return }
        selection.select(id: id)
        if let announcement {
            UIAccessibility.post(
                notification: .announcement,
                argument: String(localized: "\(announcement), selected")
            )
        }
    }

    private func useOriginal() {
        confirmationTask?.cancel()
        confirmationTask = nil
        requestID = UUID()
        isConfirming = false
        guard completionCoordinator.claimOriginal() else { return }
        onUseOriginal(sourceImage)
    }

    private func loadAnalysis() async {
        let currentRequest = UUID()
        requestID = currentRequest
        completionCoordinator.reset()
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
        guard let completionToken = completionCoordinator.beginConfirmation() else { return }
        isConfirming = true
        error = nil
        let currentRequest = requestID
        confirmationTask?.cancel()
        confirmationTask = Task {
            do {
                let cutout = try await analysis.cutout(for: selectedID)
                try Task.checkCancellation()
                guard requestID == currentRequest,
                      completionCoordinator.claimCutout(token: completionToken) else { return }
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

@MainActor
final class SubjectPickerCompletionCoordinator {
    private(set) var isCompleted = false
    private var confirmationToken = UUID()

    func reset() {
        isCompleted = false
        confirmationToken = UUID()
    }

    func beginConfirmation() -> UUID? {
        guard !isCompleted else { return nil }
        let token = UUID()
        confirmationToken = token
        return token
    }

    func cancelPendingConfirmation() {
        confirmationToken = UUID()
    }

    func claimOriginal() -> Bool {
        claimCompletion()
    }

    func claimCutout(token: UUID) -> Bool {
        guard token == confirmationToken else { return false }
        return claimCompletion()
    }

    private func claimCompletion() -> Bool {
        guard !isCompleted else { return false }
        isCompleted = true
        confirmationToken = UUID()
        return true
    }
}

@MainActor
final class SubjectInteractionLifecycle {
    private(set) weak var interaction: ImageAnalysisInteraction?
    private var tapTask: Task<Void, Never>?

    var hasTrackedTap: Bool { tapTask != nil }

    func replaceInteraction(on view: UIView, with newInteraction: ImageAnalysisInteraction) {
        guard interaction !== newInteraction else { return }
        cancelTap()
        if let interaction, interaction.view === view {
            view.removeInteraction(interaction)
        }
        if newInteraction.view !== view {
            view.addInteraction(newInteraction)
        }
        interaction = newInteraction
    }

    func trackTap(_ task: Task<Void, Never>) {
        cancelTap()
        tapTask = task
    }

    func cancelTap() {
        tapTask?.cancel()
        tapTask = nil
    }

    func dismantle(from view: UIView) {
        cancelTap()
        if let interaction, interaction.view === view {
            view.removeInteraction(interaction)
        }
        interaction = nil
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
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Subject picker"
        imageView.accessibilityHint = "Tap an object in the photo to select its cutout."
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTap(_:))))
        return imageView
    }

    func updateUIView(_ imageView: UIImageView, context: Context) {
        context.coordinator.parent = self
        imageView.image = image
        context.coordinator.lifecycle.replaceInteraction(on: imageView, with: analysis.interaction)
        analysis.interaction.highlightedSubjects = analysis.subjects(for: selectedID.map { [$0] } ?? [])
    }

    static func dismantleUIView(_ imageView: UIImageView, coordinator: Coordinator) {
        coordinator.lifecycle.dismantle(from: imageView)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SubjectInteractionView
        let lifecycle = SubjectInteractionLifecycle()
        init(parent: SubjectInteractionView) { self.parent = parent }

        @objc func didTap(_ recognizer: UITapGestureRecognizer) {
            guard let imageView = recognizer.view as? UIImageView else { return }
            let point = recognizer.location(in: imageView)
            let snapshot = parent
            let analysisIdentity = ObjectIdentifier(snapshot.analysis)
            let task = Task { @MainActor [weak self, weak imageView] in
                if let subject = await snapshot.analysis.interaction.subject(at: point) {
                    guard !Task.isCancelled,
                          let self,
                          ObjectIdentifier(self.parent.analysis) == analysisIdentity,
                          self.lifecycle.interaction === snapshot.analysis.interaction else { return }
                    snapshot.onSubjectTap(subject)
                    return
                }
                guard !Task.isCancelled,
                      let self,
                      let imageView,
                      ObjectIdentifier(self.parent.analysis) == analysisIdentity,
                      self.lifecycle.interaction === snapshot.analysis.interaction else { return }
                let geometry = AspectFitGeometry(imageSize: snapshot.image.size, containerSize: imageView.bounds.size)
                if let normalized = geometry.normalizedPoint(for: point) {
                    snapshot.onNormalizedTap(normalized)
                }
            }
            lifecycle.trackTap(task)
        }
    }
}
