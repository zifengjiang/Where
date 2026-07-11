import CoreGraphics
import UIKit
import VisionKit

struct SubjectCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let normalizedBounds: CGRect
    let displayBounds: CGRect

    var isValid: Bool {
        let values = [
            normalizedBounds.minX, normalizedBounds.minY,
            normalizedBounds.width, normalizedBounds.height,
            displayBounds.minX, displayBounds.minY,
            displayBounds.width, displayBounds.height,
        ]
        return values.allSatisfy(\.isFinite)
            && normalizedBounds.width > 0 && normalizedBounds.height > 0
            && normalizedBounds.minX >= 0 && normalizedBounds.minY >= 0
            && normalizedBounds.maxX <= 1 && normalizedBounds.maxY <= 1
            && displayBounds.width > 0 && displayBounds.height > 0
    }
}

struct SubjectSelectionState: Equatable, Sendable {
    private(set) var candidates: [SubjectCandidate]
    private(set) var selectedID: SubjectCandidate.ID?
    private var userSelectedID: SubjectCandidate.ID?

    init(candidates: [SubjectCandidate]) {
        self.candidates = candidates.filter(\.isValid)
        selectedID = Self.defaultID(in: self.candidates)
    }

    mutating func updateCandidates(_ newCandidates: [SubjectCandidate]) {
        candidates = newCandidates.filter(\.isValid)
        if let userSelectedID, candidates.contains(where: { $0.id == userSelectedID }) {
            selectedID = userSelectedID
        } else {
            userSelectedID = nil
            selectedID = Self.defaultID(in: candidates)
        }
    }

    mutating func select(id: SubjectCandidate.ID) {
        guard candidates.contains(where: { $0.id == id }) else { return }
        userSelectedID = id
        selectedID = id
    }

    mutating func select(at normalizedPoint: CGPoint) {
        guard normalizedPoint.x.isFinite, normalizedPoint.y.isFinite else { return }
        let match = candidates
            .filter { $0.normalizedBounds.contains(normalizedPoint) }
            .sorted(by: Self.hitOrder)
            .first
        if let match { select(id: match.id) }
    }

    private static func defaultID(in candidates: [SubjectCandidate]) -> SubjectCandidate.ID? {
        candidates.sorted {
            let lhsArea = $0.normalizedBounds.width * $0.normalizedBounds.height
            let rhsArea = $1.normalizedBounds.width * $1.normalizedBounds.height
            return lhsArea == rhsArea ? $0.id < $1.id : lhsArea > rhsArea
        }.first?.id
    }

    private static func hitOrder(_ lhs: SubjectCandidate, _ rhs: SubjectCandidate) -> Bool {
        let lhsArea = lhs.normalizedBounds.width * lhs.normalizedBounds.height
        let rhsArea = rhs.normalizedBounds.width * rhs.normalizedBounds.height
        return lhsArea == rhsArea ? lhs.id < rhs.id : lhsArea < rhsArea
    }
}

enum SubjectSegmentationError: Error, Equatable, LocalizedError, Sendable {
    case unsupported
    case noSubjects
    case subjectUnavailable
    case analysisFailed

    var errorDescription: String? {
        switch self {
        case .unsupported: "Subject extraction isn't supported on this device."
        case .noSubjects: "No separate subject was found in this photo."
        case .subjectUnavailable: "That subject is no longer available."
        case .analysisFailed: "The photo couldn't be analyzed."
        }
    }
}

@MainActor
final class SubjectSegmentationAnalysis {
    let sourceImage: UIImage
    let interaction: ImageAnalysisInteraction
    let candidates: [SubjectCandidate]
    private let subjectsByID: [SubjectCandidate.ID: ImageAnalysisInteraction.Subject]

    init(
        sourceImage: UIImage,
        interaction: ImageAnalysisInteraction,
        candidates: [SubjectCandidate],
        subjectsByID: [SubjectCandidate.ID: ImageAnalysisInteraction.Subject]
    ) {
        self.sourceImage = sourceImage
        self.interaction = interaction
        self.candidates = candidates
        self.subjectsByID = subjectsByID
    }

    func candidateID(for subject: ImageAnalysisInteraction.Subject) -> SubjectCandidate.ID? {
        subjectsByID.first(where: { $0.value == subject })?.key
    }

    func subjects(for candidateIDs: some Sequence<SubjectCandidate.ID>) -> Set<ImageAnalysisInteraction.Subject> {
        Set(candidateIDs.compactMap { subjectsByID[$0] })
    }

    func cutout(for candidateID: SubjectCandidate.ID) async throws -> UIImage {
        guard let subject = subjectsByID[candidateID] else {
            throw SubjectSegmentationError.subjectUnavailable
        }
        do {
            return try await interaction.image(for: [subject])
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SubjectSegmentationService.map(error)
        }
    }
}

@MainActor
struct SubjectSegmentationService {
    func analyze(_ image: UIImage) async throws -> SubjectSegmentationAnalysis {
        guard ImageAnalyzer.isSupported else { throw SubjectSegmentationError.unsupported }

        let analyzer = ImageAnalyzer()
        let analysis: ImageAnalysis
        do {
            // Subject lifting is enabled by the interaction type. It doesn't require
            // Visual Look Up or any network-backed analysis option.
            analysis = try await analyzer.analyze(
                image,
                configuration: ImageAnalyzer.Configuration([])
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.map(error)
        }

        let interaction = ImageAnalysisInteraction()
        interaction.preferredInteractionTypes = .imageSubject
        interaction.analysis = analysis

        let imageView = UIImageView(image: image)
        imageView.frame = CGRect(origin: .zero, size: image.size)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.addInteraction(interaction)

        let subjects = await interaction.subjects
        try Task.checkCancellation()
        guard !subjects.isEmpty else { throw SubjectSegmentationError.noSubjects }

        let ordered = subjects.sorted(by: Self.subjectOrder)
        var candidates: [SubjectCandidate] = []
        var subjectsByID: [String: ImageAnalysisInteraction.Subject] = [:]
        for (index, subject) in ordered.enumerated() {
            let displayBounds = subject.bounds
            let normalized = Self.normalized(displayBounds, in: imageView.bounds)
            let id = Self.stableID(for: normalized, ordinal: index)
            let candidate = SubjectCandidate(id: id, normalizedBounds: normalized, displayBounds: displayBounds)
            guard candidate.isValid else { continue }
            candidates.append(candidate)
            subjectsByID[id] = subject
        }
        guard !candidates.isEmpty else { throw SubjectSegmentationError.noSubjects }
        return SubjectSegmentationAnalysis(
            sourceImage: image,
            interaction: interaction,
            candidates: candidates,
            subjectsByID: subjectsByID
        )
    }

    static func map(_ error: Error) -> SubjectSegmentationError {
        if let mapped = error as? SubjectSegmentationError { return mapped }
        if error is ImageAnalysisInteraction.SubjectUnavailable { return .subjectUnavailable }
        return .analysisFailed
    }

    private static func normalized(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let normalized = CGRect(
            x: rect.minX / bounds.width,
            y: rect.minY / bounds.height,
            width: rect.width / bounds.width,
            height: rect.height / bounds.height
        )
        return normalized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func subjectOrder(
        _ lhs: ImageAnalysisInteraction.Subject,
        _ rhs: ImageAnalysisInteraction.Subject
    ) -> Bool {
        let a = lhs.bounds
        let b = rhs.bounds
        return [a.minX, a.minY, a.width, a.height].lexicographicallyPrecedes([b.minX, b.minY, b.width, b.height])
    }

    private static func stableID(for rect: CGRect, ordinal: Int) -> String {
        [rect.minX, rect.minY, rect.width, rect.height]
            .map { String(format: "%.8f", Double($0)) }
            .joined(separator: ":") + ":\(ordinal)"
    }
}
