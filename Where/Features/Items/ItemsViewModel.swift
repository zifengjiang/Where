import Foundation
import Observation

@MainActor
@Observable
final class ItemsViewModel {
    enum LoadState: Equatable { case loading, loaded, failed }

    var query = "" {
        didSet { if query != oldValue, hasStarted { scheduleObservation() } }
    }
    private(set) var items: [ItemSummary] = []
    private(set) var selectedItem: ItemSummary?
    private(set) var state: LoadState = .loading
    var effectiveQuery: String { SearchNormalizer.normalize(query) }
    var hasEffectiveQuery: Bool { !effectiveQuery.isEmpty }

    private let repository: any ItemRepositoryProtocol
    private let debounce: Duration
    private var observationTask: Task<Void, Never>?
    private var generation = 0
    private var hasStarted = false

    init(repository: any ItemRepositoryProtocol, debounce: Duration = .milliseconds(220)) {
        self.repository = repository
        self.debounce = debounce
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        observe(query: query, delay: false)
    }

    func stop() {
        hasStarted = false
        generation += 1
        observationTask?.cancel()
        observationTask = nil
    }

    func retry() {
        guard hasStarted else { start(); return }
        observe(query: query, delay: false)
    }

    func select(_ item: ItemSummary) {
        guard items.contains(where: { $0.id == item.id }) else { return }
        selectedItem = item
    }

    private func scheduleObservation() { observe(query: query, delay: true) }

    private func observe(query: String, delay: Bool) {
        observationTask?.cancel()
        generation += 1
        let currentGeneration = generation
        state = .loading
        observationTask = Task { [weak self, repository, debounce] in
            if delay && debounce > .zero {
                do { try await Task.sleep(for: debounce) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            do {
                for try await value in repository.observeItems(query: query) {
                    guard !Task.isCancelled,
                          let self,
                          self.generation == currentGeneration else { return }
                    self.apply(value)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      let self,
                      self.generation == currentGeneration else { return }
                self.state = .failed
            }
        }
    }

    private func apply(_ value: [ItemSummary]) {
        items = value
        if let selectedID = selectedItem?.id {
            selectedItem = value.first { $0.id == selectedID }
        }
        state = .loaded
    }
}
