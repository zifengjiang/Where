import Foundation
import Testing
@testable import Where

@MainActor
struct ItemsViewModelTests {
    @Test func blankQueryLoadsAllWithoutDefaultSelection() async {
        let item = itemFixture(name: "钥匙")
        let repository = ItemsRepositoryFake(events: ["": [.success([item])]])
        let model = ItemsViewModel(repository: repository, debounce: .zero)
        model.start()
        await eventually { model.items == [item] }
        #expect(model.selectedItem == nil)
        #expect(repository.queries == [""])
    }

    @Test func selectingItemOnlyChangesSelection() async {
        let first = itemFixture(name: "钥匙")
        let second = itemFixture(name: "耳机")
        let model = ItemsViewModel(repository: ItemsRepositoryFake(events: ["": [.success([first, second])]]), debounce: .zero)
        model.start(); await eventually { model.items.count == 2 }
        model.select(first)
        #expect(model.selectedItem == first)
        #expect(model.items == [first, second])
    }

    @Test func selectionSurvivesRefreshWhenItemRemainsAndUsesFreshValue() async {
        let initial = itemFixture(name: "钥匙")
        let updated = ItemSummary(id: initial.id, sceneID: initial.sceneID, sceneName: initial.sceneName,
            sceneImagePath: initial.sceneImagePath, name: "备用钥匙", locationNote: initial.locationNote,
            note: initial.note, normalizedX: initial.normalizedX, normalizedY: initial.normalizedY,
            aliases: initial.aliases, tags: initial.tags, appearanceOriginalImagePath: initial.appearanceOriginalImagePath,
            appearanceCutoutImagePath: initial.appearanceCutoutImagePath, createdAt: initial.createdAt, updatedAt: Date())
        let stream = ItemsRepositoryFake.liveStream()
        let repository = ItemsRepositoryFake(streams: ["": stream.stream])
        let model = ItemsViewModel(repository: repository, debounce: .zero)
        model.start(); stream.continuation.yield([initial]); await eventually { model.items == [initial] }
        model.select(initial); stream.continuation.yield([updated]); await eventually { model.selectedItem?.name == "备用钥匙" }
        #expect(model.selectedItem?.id == initial.id)
    }

    @Test func queryClearsSelectionWhenSelectedItemLeavesResults() async {
        let first = itemFixture(name: "钥匙")
        let second = itemFixture(name: "耳机")
        let repository = ItemsRepositoryFake(events: ["": [.success([first, second])], "耳机": [.success([second])]])
        let model = ItemsViewModel(repository: repository, debounce: .zero)
        model.start(); await eventually { model.items.count == 2 }; model.select(first)
        model.query = "耳机"
        await eventually { model.items == [second] }
        #expect(model.selectedItem == nil)
    }

    @Test func rapidQueriesCancelStaleObservation() async {
        let stale = ItemsRepositoryFake.liveStream()
        let latestItem = itemFixture(name: "旅行插头")
        let repository = ItemsRepositoryFake(streams: ["旧": stale.stream, "旅行": stream([latestItem])])
        let model = ItemsViewModel(repository: repository, debounce: .milliseconds(15))
        model.start(); model.query = "旧"; model.query = "旅行"
        await eventually { model.items == [latestItem] }
        stale.continuation.yield([itemFixture(name: "过期")])
        try? await Task.sleep(for: .milliseconds(30))
        #expect(model.items == [latestItem])
    }

    @Test func repositoryFailureExposesRetry() async {
        let item = itemFixture(name: "电池")
        let repository = ItemsRepositoryFake(events: ["": [.failure(ItemsTestError.failed), .success([item])]])
        let model = ItemsViewModel(repository: repository, debounce: .zero)
        model.start(); await eventually { model.state == .failed }
        model.retry(); await eventually { model.items == [item] }
        #expect(model.state == .loaded)
        #expect(repository.queries == ["", ""])
    }

    @Test func missingImagePathsDoNotRemoveTextOrSelection() async {
        let item = itemFixture(name: "说明书", scenePath: "missing.jpg", cutoutPath: nil)
        let model = ItemsViewModel(repository: ItemsRepositoryFake(events: ["": [.success([item])]]), debounce: .zero)
        model.start(); await eventually { model.items == [item] }; model.select(item)
        #expect(model.selectedItem?.name == "说明书")
        #expect(model.selectedItem?.sceneImagePath == "missing.jpg")
    }
}

private enum ItemsTestError: Error { case failed }

private final class ItemsRepositoryFake: ItemRepositoryProtocol, @unchecked Sendable {
    struct Live { let stream: AsyncThrowingStream<[ItemSummary], Error>; let continuation: AsyncThrowingStream<[ItemSummary], Error>.Continuation }
    private let lock = NSLock()
    private var events: [String: [Result<[ItemSummary], Error>]]
    private let streams: [String: AsyncThrowingStream<[ItemSummary], Error>]
    private(set) var queries: [String] = []
    init(events: [String: [Result<[ItemSummary], Error>]]) { self.events = events; streams = [:] }
    init(streams: [String: AsyncThrowingStream<[ItemSummary], Error>]) { events = [:]; self.streams = streams }
    static func liveStream() -> Live { var continuation: AsyncThrowingStream<[ItemSummary], Error>.Continuation!; let stream = AsyncThrowingStream<[ItemSummary], Error> { continuation = $0 }; return Live(stream: stream, continuation: continuation) }
    func observeItems(query: String) -> AsyncThrowingStream<[ItemSummary], Error> {
        lock.lock(); queries.append(query); let event = events[query]?.isEmpty == false ? events[query]!.removeFirst() : nil; lock.unlock()
        if let fixed = streams[query] { return fixed }
        return AsyncThrowingStream { continuation in
            switch event { case .success(let items): continuation.yield(items); continuation.finish(); case .failure(let error): continuation.finish(throwing: error); case nil: continuation.yield([]); continuation.finish() }
        }
    }
    func saveSceneDraft(_ draft: SceneDraft) async throws {}
    func rollbackSceneDraft(id: UUID) async throws {}
    func searchItems(query: String) async throws -> [ItemSummary] { [] }
    func deleteItem(id: UUID) async throws -> DeletedImagePaths { .init(original: nil, cutout: nil) }
}

private func stream(_ items: [ItemSummary]) -> AsyncThrowingStream<[ItemSummary], Error> { AsyncThrowingStream { $0.yield(items); $0.finish() } }
private func itemFixture(name: String, scenePath: String = "scene.jpg", cutoutPath: String? = "cutout.png") -> ItemSummary {
    ItemSummary(id: UUID(), sceneID: UUID(), sceneName: "玄关", sceneImagePath: scenePath, name: name,
        locationNote: "左侧抽屉", note: "备用", normalizedX: 0.3, normalizedY: 0.6,
        aliases: ["备用"], tags: ["常用"], appearanceOriginalImagePath: nil,
        appearanceCutoutImagePath: cutoutPath, createdAt: .now, updatedAt: .now)
}

@MainActor private func eventually(_ predicate: @escaping () -> Bool) async {
    for _ in 0..<100 { if predicate() { return }; try? await Task.sleep(for: .milliseconds(5)) }
}
