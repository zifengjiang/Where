# Where iOS App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an offline iOS 26 app that records household items as pins on scene photos, searches items by name/alias/tag, and presents segmented, flippable item cards with silhouette-shaped notes.

**Architecture:** A SwiftUI app uses feature-specific observable models over repositories. GRDB 7.10 stores normalized records in SQLite through a single `DatabaseQueue`; an `ImageStore` owns original, scene, and transparent cutout files. VisionKit performs subject lifting, Core Text lays read-only note text inside subject silhouettes, and views consume protocol-backed services for deterministic tests.

**Tech Stack:** Swift 6, SwiftUI, iOS 26 SDK, GRDB 7.10 via Swift Package Manager, VisionKit, Vision, Core Text, PhotosUI, XCTest, XCUITest, XcodeBuildMCP.

---

## File map

Create the Xcode project `Where.xcodeproj` with app target `Where`, unit-test target `WhereTests`, and UI-test target `WhereUITests`.

- `Where/App/WhereApp.swift`: composition root and database startup.
- `Where/App/AppDependencies.swift`: protocol-backed dependency container.
- `Where/App/RootTabView.swift`: iOS 26 TabView and independent add accessory.
- `Where/Database/AppDatabase.swift`: GRDB queue creation and migrations.
- `Where/Database/Records.swift`: GRDB record types only.
- `Where/Database/SceneRepository.swift`: scene writes and observations.
- `Where/Database/ItemRepository.swift`: item transactions, observations, and search.
- `Where/Domain/Models.swift`: UI-facing immutable models and drafts.
- `Where/Domain/SearchNormalizer.swift`: query and stored-text normalization.
- `Where/Images/ImageStore.swift`: draft/final file lifecycle and compression.
- `Where/Images/SubjectSegmentationService.swift`: VisionKit subject analysis and cutout generation.
- `Where/Images/SilhouetteTextLayout.swift`: alpha-mask path and Core Text layout.
- `Where/Images/AspectFitGeometry.swift`: normalized image/view coordinate conversion.
- `Where/Features/Scenes/ScenesView.swift`: scene grid.
- `Where/Features/Scenes/SceneDetailView.swift`: scene image and pin editing entry.
- `Where/Features/Items/ItemsView.swift`: selected scene preview, search, and item list.
- `Where/Features/Items/ItemCardView.swift`: front/back silhouette card.
- `Where/Features/Items/NoteEditorView.swift`: standard multiline note sheet.
- `Where/Features/Capture/SceneDraftView.swift`: scene name and source photo.
- `Where/Features/Capture/MarkerEditorView.swift`: multi-pin editor.
- `Where/Features/Capture/ItemDraftSheet.swift`: item metadata and appearance photo.
- `Where/Features/Capture/SubjectPickerView.swift`: largest-subject default and tap switching.
- `Where/Features/Shared/CameraPicker.swift`: system camera wrapper.
- `Where/Features/Shared/AsyncImageFileView.swift`: private-file image loading and fallback.
- `Where/Resources/AppIcon.icon`: Icon Composer layered icon.
- `WhereTests/`: one focused test file per production unit.
- `WhereUITests/WhereMainFlowUITests.swift`: end-to-end acceptance flow.

## Task 1: Scaffold the iOS project and dependency graph

**Files:**
- Create: `Where.xcodeproj`
- Create: `Where/App/WhereApp.swift`
- Create: `Where/App/AppDependencies.swift`
- Create: `WhereTests/WhereSmokeTests.swift`
- Create: `WhereUITests/WhereUITests.swift`

- [ ] **Step 1: Create the project**

Use the Build iOS Apps project-scaffolding capability with product name `Where`, bundle identifier `com.zifengjiang.Where`, SwiftUI lifecycle, Swift 6, iOS deployment target 26.0, and unit/UI test targets. Add `https://github.com/groue/GRDB.swift.git` pinned to `7.10.0`, linking product `GRDB` only to `Where` and `WhereTests`.

- [ ] **Step 2: Add a failing composition smoke test**

```swift
import Testing
@testable import Where

@Test func dependenciesCanUseTemporaryStorage() throws {
    let dependencies = try AppDependencies.testing()
    #expect(dependencies.database != nil)
}
```

- [ ] **Step 3: Run the test to verify the missing type fails**

Use XcodeBuildMCP `session_show_defaults`, set `Where.xcodeproj`, scheme `Where`, and an iOS 26 simulator, then run `test_sim` with `-only-testing:WhereTests/WhereSmokeTests`. Expected: compile failure for missing `AppDependencies`.

- [ ] **Step 4: Add the composition-root skeleton**

```swift
import Foundation

struct AppDependencies {
    let database: AppDatabase
    let imageStore: ImageStore

    static func testing() throws -> Self {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Self(
            database: try AppDatabase.inMemory(),
            imageStore: try ImageStore(rootDirectory: root)
        )
    }
}
```

Create the initial concrete types; later tasks add migrations and file operations without changing these initializers:

```swift
import GRDB

final class AppDatabase: @unchecked Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    static func inMemory() throws -> AppDatabase {
        AppDatabase(writer: try DatabaseQueue())
    }
}

actor ImageStore {
    let rootDirectory: URL

    init(rootDirectory: URL) throws {
        self.rootDirectory = rootDirectory
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
    }
}
```

- [ ] **Step 5: Verify and commit**

Run the smoke test and expect PASS. Commit:

```bash
git add Where.xcodeproj Where WhereTests WhereUITests
git commit -m "feat: scaffold Where iOS app"
```

## Task 2: Build the GRDB schema and migrations

**Files:**
- Create: `Where/Database/AppDatabase.swift`
- Create: `Where/Database/Records.swift`
- Create: `Where/Domain/Models.swift`
- Test: `WhereTests/AppDatabaseTests.swift`

- [ ] **Step 1: Write failing migration and cascade tests**

Test that migration `v1` creates `scene`, `item`, `itemAlias`, `tag`, and `itemTag`; insert one complete graph, delete its scene, and assert all item/alias/join rows are gone. Also assert `PRAGMA foreign_keys = 1`.

- [ ] **Step 2: Verify the tests fail**

Run `test_sim` with `-only-testing:WhereTests/AppDatabaseTests`. Expected: missing tables/migrator.

- [ ] **Step 3: Implement record types**

Define `SceneRecord`, `ItemRecord`, `ItemAliasRecord`, `TagRecord`, and `ItemTagRecord` as `Codable`, `FetchableRecord`, `PersistableRecord`, and `TableRecord`. Use `String` UUID primary keys and `Date` timestamps. `ItemRecord` must include:

```swift
var appearanceOriginalImagePath: String?
var appearanceCutoutImagePath: String?
var note: String?
var normalizedX: Double
var normalizedY: Double
```

- [ ] **Step 4: Implement `DatabaseMigrator`**

Create the five tables, indexes on `item.sceneID`, normalized alias values, normalized tag names, and item update time. Add `.references(..., onDelete: .cascade)` and unique constraints for `(itemID, normalizedValue)`, `tag.normalizedName`, and `(itemID, tagID)`.

- [ ] **Step 5: Verify and commit**

Run `AppDatabaseTests`; expect PASS. Commit:

```bash
git add Where/Database Where/Domain WhereTests/AppDatabaseTests.swift
git commit -m "feat: add GRDB schema and migrations"
```

## Task 3: Implement search normalization and repositories

**Files:**
- Create: `Where/Domain/SearchNormalizer.swift`
- Create: `Where/Database/SceneRepository.swift`
- Create: `Where/Database/ItemRepository.swift`
- Test: `WhereTests/SearchNormalizerTests.swift`
- Test: `WhereTests/ItemRepositoryTests.swift`

- [ ] **Step 1: Write failing normalization tests**

Cover trimming, case folding, compatibility normalization, full-width Latin input, Chinese text, and blank input. Required examples:

```swift
#expect(SearchNormalizer.normalize("  Ｃａｂｌｅ  ") == "cable")
#expect(SearchNormalizer.normalize(" 旅行 ") == "旅行")
```

- [ ] **Step 2: Implement normalization**

Use `precomposedStringWithCompatibilityMapping`, trim whitespace/newlines, and `lowercased(with: Locale(identifier: "en_US_POSIX"))`.

- [ ] **Step 3: Write failing repository tests**

Insert items where the query hits name, alias, and tag. Assert precedence name > alias > tag, then `updatedAt` descending. Assert blank query returns all items and `%`, `_`, and quotes remain data, not SQL syntax.

- [ ] **Step 4: Implement repository transactions and observations**

Expose:

```swift
protocol ItemRepositoryProtocol: Sendable {
    func saveSceneDraft(_ draft: SceneDraft) async throws
    func searchItems(query: String) async throws -> [ItemSummary]
    func observeItems(query: String) -> AsyncThrowingStream<[ItemSummary], Error>
    func deleteItem(id: UUID) async throws -> DeletedImagePaths
}
```

Use parameterized GRDB SQL and `ValueObservation.values(in:)`. Save scene, items, aliases, tags, and joins in one write transaction. Preserve `createdAt` on updates.

- [ ] **Step 5: Verify and commit**

Run both test classes; expect PASS. Commit:

```bash
git add Where/Domain/SearchNormalizer.swift Where/Database/SceneRepository.swift Where/Database/ItemRepository.swift WhereTests
git commit -m "feat: add repositories and item search"
```

## Task 4: Implement safe image storage

**Files:**
- Create: `Where/Images/ImageStore.swift`
- Test: `WhereTests/ImageStoreTests.swift`

- [ ] **Step 1: Write failing file-lifecycle tests**

Test draft creation, JPEG scene compression, transparent PNG cutout persistence, promote-on-commit, cancel cleanup, replace-then-delete-old, referenced-file preservation, and stale orphan cleanup.

- [ ] **Step 2: Implement the storage API**

```swift
actor ImageStore {
    struct DraftImage: Sendable { let url: URL; let relativeName: String }
    func stageSceneImage(_ data: Data) async throws -> DraftImage
    func stageAppearanceOriginal(_ data: Data) async throws -> DraftImage
    func stageCutout(_ image: CGImage) async throws -> DraftImage
    func promote(_ drafts: [DraftImage]) async throws -> [String]
    func discard(_ drafts: [DraftImage]) async
    func delete(relativePaths: Set<String>) async throws
    func cleanOrphans(referencedPaths: Set<String>, olderThan: Date) async throws
}
```

Normalize orientation before resizing; cap the longest scene edge at 3072 px and appearance edge at 1600 px. Preserve alpha for cutouts. Never accept an absolute database path.

- [ ] **Step 3: Verify and commit**

Run `ImageStoreTests`; expect PASS. Commit:

```bash
git add Where/Images/ImageStore.swift WhereTests/ImageStoreTests.swift
git commit -m "feat: add transactional image storage"
```

## Task 5: Implement photo geometry and scene pins

**Files:**
- Create: `Where/Images/AspectFitGeometry.swift`
- Create: `Where/Features/Scenes/ScenePhotoView.swift`
- Test: `WhereTests/AspectFitGeometryTests.swift`

- [ ] **Step 1: Write failing geometry tests**

Test portrait-in-landscape and landscape-in-portrait aspect-fit rectangles, rejection of taps in letterboxing, conversion to normalized coordinates, conversion back to view points, and clamping to `0...1`.

- [ ] **Step 2: Implement pure geometry**

```swift
struct AspectFitGeometry: Equatable {
    let imageSize: CGSize
    let containerSize: CGSize
    var imageRect: CGRect { get }
    func normalizedPoint(for viewPoint: CGPoint) -> CGPoint?
    func viewPoint(for normalizedPoint: CGPoint) -> CGPoint
}
```

- [ ] **Step 3: Build reusable pin overlay**

`ScenePhotoView` accepts an image, pins, selected item ID, and an optional edit callback. Render the selected marker larger with a contrasting outline and name label; hide labels for unselected markers. Add VoiceOver labels from item name and location note.

- [ ] **Step 4: Verify and commit**

Run geometry tests and one preview/snapshot at two device sizes. Commit:

```bash
git add Where/Images/AspectFitGeometry.swift Where/Features/Scenes/ScenePhotoView.swift WhereTests/AspectFitGeometryTests.swift
git commit -m "feat: add normalized scene markers"
```

## Task 6: Add VisionKit subject lifting

**Files:**
- Create: `Where/Images/SubjectSegmentationService.swift`
- Create: `Where/Features/Capture/SubjectPickerView.swift`
- Test: `WhereTests/SubjectSelectionTests.swift`

- [ ] **Step 1: Extract deterministic subject-selection logic and test it**

Represent candidates with stable IDs and bounds. Assert `defaultSubject` chooses the greatest `bounds.width * bounds.height`, returns nil for an empty set, and preserves the explicit user choice after reordering.

- [ ] **Step 2: Implement the VisionKit adapter**

Use `ImageAnalyzer` with image-subject analysis, populate `ImageAnalysisInteraction`, await `subjects`, and call `image(for:)` for the selected subject. Guard `ImageAnalyzer.isSupported`. Map no result and framework errors to recoverable `SubjectSegmentationError` values.

- [ ] **Step 3: Implement the picker UI**

Wrap the required UIKit image interaction in `UIViewRepresentable`. Highlight all candidates, select the largest by default, switch selection with `subject(at:)` when the user taps, and provide “Use original photo” as an explicit fallback.

- [ ] **Step 4: Verify and commit**

Run subject-selection unit tests; manually verify a bundled fixture with two objects and one fixture with no detectable subject. Commit:

```bash
git add Where/Images/SubjectSegmentationService.swift Where/Features/Capture/SubjectPickerView.swift WhereTests/SubjectSelectionTests.swift
git commit -m "feat: add item subject segmentation"
```

## Task 7: Lay note text inside the subject silhouette

**Files:**
- Create: `Where/Images/SilhouetteTextLayout.swift`
- Create: `Where/Features/Items/ItemCardView.swift`
- Create: `Where/Features/Items/NoteEditorView.swift`
- Test: `WhereTests/SilhouetteTextLayoutTests.swift`
- Test: `WhereTests/ItemCardStateTests.swift`

- [ ] **Step 1: Write failing silhouette-layout tests**

Use synthetic alpha masks for a rectangle, circle, narrow line, disconnected islands, and empty image. Assert safe inset, removal of tiny components, line fragments remain inside opaque pixels, overflow is reported, and narrow/empty shapes request rounded-card fallback.

- [ ] **Step 2: Implement mask-to-path and Core Text layout**

Downsample alpha to a bounded grid, keep the largest meaningful connected component, trace and simplify its contour, inset it for text safety, and create a Core Text frame with that path. Return:

```swift
struct SilhouetteTextLayoutResult: Sendable {
    let path: CGPath
    let lines: [SilhouetteLine]
    let overflowed: Bool
    let usesFallbackCard: Bool
}
```

Reject paths whose usable area or maximum line width falls below the Dynamic Type-dependent threshold.

- [ ] **Step 3: Implement the flippable card**

Front: transparent cutout. Back: warm paper fill clipped to silhouette, laid-out note, and `createdAt` when space permits. Respect `accessibilityReduceMotion`; use opacity transition instead of 3D rotation when enabled. Keep flip state local to the selected item ID.

- [ ] **Step 4: Implement note editing**

Use a standard sheet with `TextEditor`, character count, Cancel, and Save. The back is read-only and opens the full note sheet when truncated.

- [ ] **Step 5: Verify and commit**

Run both test classes and inspect the card at accessibility text sizes. Commit:

```bash
git add Where/Images/SilhouetteTextLayout.swift Where/Features/Items WhereTests/SilhouetteTextLayoutTests.swift WhereTests/ItemCardStateTests.swift
git commit -m "feat: add silhouette item cards"
```

## Task 8: Build the iOS 26 app shell

**Files:**
- Modify: `Where/App/WhereApp.swift`
- Modify: `Where/App/AppDependencies.swift`
- Create: `Where/App/RootTabView.swift`
- Test: `WhereTests/RootTabStateTests.swift`

- [ ] **Step 1: Write failing root-state tests**

Assert only `.scenes` and `.items` are tab selections; triggering add sets `isPresentingCapture` without changing the selected tab.

- [ ] **Step 2: Implement root navigation**

Create two `Tab` entries labeled “场景” and “所有物品”. Add the independent plus button with `.tabViewBottomAccessory` and adapt its content using `tabViewBottomAccessoryPlacement`. Present `SceneDraftView` as a full-screen cover. Apply `.tabBarMinimizeBehavior(.onScrollDown)` only after verifying it does not hide the add action.

- [ ] **Step 3: Verify and commit**

Build and run on an iOS 26 simulator; inspect expanded and minimized tab states. Commit:

```bash
git add Where/App WhereTests/RootTabStateTests.swift
git commit -m "feat: add iOS 26 tab shell"
```

## Task 9: Build scene browsing and editing

**Files:**
- Create: `Where/Features/Scenes/ScenesViewModel.swift`
- Create: `Where/Features/Scenes/ScenesView.swift`
- Create: `Where/Features/Scenes/SceneDetailViewModel.swift`
- Create: `Where/Features/Scenes/SceneDetailView.swift`
- Test: `WhereTests/ScenesViewModelTests.swift`

- [ ] **Step 1: Write failing view-model tests**

Test loading, empty state, repository error, delete confirmation, delete failure, and successful scene deletion followed by image cleanup.

- [ ] **Step 2: Implement scene grid and detail**

Scene cards show thumbnail, name, and item count. Detail uses `ScenePhotoView` with all pins and exposes Edit Scene, Add Item, and Delete. Replacing a scene image must show the warning that existing pins may need adjustment.

- [ ] **Step 3: Verify and commit**

Run tests and inspect empty, populated, and missing-image fixtures. Commit:

```bash
git add Where/Features/Scenes WhereTests/ScenesViewModelTests.swift
git commit -m "feat: add scene browsing and editing"
```

## Task 10: Build the multi-item capture flow

**Files:**
- Create: `Where/Features/Capture/SceneCaptureViewModel.swift`
- Create: `Where/Features/Capture/SceneDraftView.swift`
- Create: `Where/Features/Capture/MarkerEditorView.swift`
- Create: `Where/Features/Capture/ItemDraftSheet.swift`
- Create: `Where/Features/Shared/CameraPicker.swift`
- Test: `WhereTests/SceneCaptureViewModelTests.swift`

- [ ] **Step 1: Write failing state-machine tests**

Cover source selection, required scene name, ignored letterbox taps, adding/moving/removing multiple pins, required item name, aliases/tags deduplication, optional note/photo, save-in-progress protection, successful promotion, failed transaction preserving drafts, retry, and cancel cleanup.

- [ ] **Step 2: Implement the draft state machine**

Keep all unsaved state in `SceneDraft` and `ItemDraft`. Stage images immediately, but call the repository only from `finish()`. Do not promote/delete files until the transaction outcome is known.

- [ ] **Step 3: Implement system photo and camera inputs**

Use `PhotosPicker` for library selection. Wrap `UIImagePickerController` for camera capture, check availability and authorization, and present “Open Settings” plus “Choose from Photos” when denied.

- [ ] **Step 4: Implement marker and item editors**

Allow consecutive taps, drag-to-move, tap-to-edit, and delete. `ItemDraftSheet` contains name, tokenized aliases/tags, location note, multiline note, and optional appearance photo leading to `SubjectPickerView`.

- [ ] **Step 5: Verify and commit**

Run view-model tests; manually create one scene with three pins. Commit:

```bash
git add Where/Features/Capture Where/Features/Shared/CameraPicker.swift WhereTests/SceneCaptureViewModelTests.swift
git commit -m "feat: add multi-item scene capture"
```

## Task 11: Build the unified item search page

**Files:**
- Create: `Where/Features/Items/ItemsViewModel.swift`
- Create: `Where/Features/Items/ItemsView.swift`
- Create: `Where/Features/Shared/AsyncImageFileView.swift`
- Test: `WhereTests/ItemsViewModelTests.swift`

- [ ] **Step 1: Write failing view-model tests**

Assert no default selection, blank query shows all, selection changes only the top scene/card area, query changes clear a selection that is no longer present, missing images retain text data, and repository failures expose retry state.

- [ ] **Step 2: Implement the view model**

Debounce user text briefly, consume repository observation, retain selection only while its ID remains in results, and load the selected scene plus item card model.

- [ ] **Step 3: Implement the unified page**

Top area: selected scene photo and only the selected item pin highlighted, plus `ItemCardView`. Bottom area: search field and rows with cutout thumbnail, name, and tags. With no selection, show “选择一个物品查看它的位置”. With no results, show “未找到物品”.

- [ ] **Step 4: Verify and commit**

Run tests; manually search by name, alias, Chinese tag, and no-result query. Commit:

```bash
git add Where/Features/Items Where/Features/Shared/AsyncImageFileView.swift WhereTests/ItemsViewModelTests.swift
git commit -m "feat: add unified item search"
```

## Task 12: Add the Where app icon and product polish

**Files:**
- Create: `Where/Resources/AppIcon.icon`
- Modify: target app-icon build setting
- Create: `Where/Resources/Localizable.xcstrings`

- [ ] **Step 1: Create layered icon artwork**

Use a 1024×1024 canvas with separate vector layers: warm orange background, deep ink-green cabinet/corner outline, warm red location dot, and light marker ring. Do not include text, outer rounded-corner masks, static blur, or baked highlights.

- [ ] **Step 2: Assemble in Icon Composer**

Import the layers into `AppIcon.icon`; tune Default, Dark, Clear, and Mono/Tinted appearances. Set the target App Icon name to `AppIcon` and device display name to `Where`.

- [ ] **Step 3: Add localized and accessibility copy**

Move visible Chinese strings and permission explanations into the string catalog. Add camera usage text explaining that photos are used only to record household items. Audit every image, marker, button, empty state, and destructive alert.

- [ ] **Step 4: Verify and commit**

Run on simulator in default/dark/tinted icon modes, light/dark UI, Reduce Motion, and accessibility text sizes. Commit:

```bash
git add Where/Resources Where.xcodeproj
git commit -m "feat: add Where branding and accessibility polish"
```

## Task 13: Add end-to-end UI tests and final verification

**Files:**
- Create: `WhereUITests/WhereMainFlowUITests.swift`
- Modify: `Where/App/AppDependencies.swift`
- Create: `README.md`

- [ ] **Step 1: Add deterministic UI-test fixtures**

When launched with `-ui-testing`, use a temporary database and bundled scene/item fixtures. Add launch arguments for successful segmentation, multiple candidates, no subject, missing file, and forced database-save error.

- [ ] **Step 2: Write the main UI test**

Automate: open add, choose fixture photo, name scene, place two pins, add aliases/tags/note and item appearance, choose the non-default subject, finish, open All Items, search by tag, select the item, verify highlighted scene label, flip the card, and open the complete note sheet.

- [ ] **Step 3: Add recovery UI tests**

Cover no search results, segmentation fallback, missing image placeholder, database save retry, delete confirmation, and reduced-motion card transition.

- [ ] **Step 4: Run the complete verification suite**

Use XcodeBuildMCP in this order:

1. `session_show_defaults` and confirm project, scheme, and simulator.
2. `test_sim` for all unit/UI tests; expected zero failures.
3. `build_run_sim`; expected successful launch.
4. `snapshot_ui` and `screenshot` for Scenes, Items with selection, card back, and capture marker editor.
5. Inspect runtime logs for crashes, GRDB errors, missing-file loops, and main-thread image processing warnings.

- [ ] **Step 5: Document and commit**

Add README sections for product purpose, iOS/Xcode requirements, GRDB dependency, local-only privacy, build/test commands, and current MVP scope. Commit:

```bash
git add WhereUITests Where/App/AppDependencies.swift README.md
git commit -m "test: cover Where end-to-end flow"
```

## Task 14: Publish the completed implementation

**Files:**
- Modify only files required by final verification findings.

- [ ] **Step 1: Confirm clean verification evidence**

Re-run the full test suite after any final fix. Record simulator model, iOS version, test counts, and screenshot paths.

- [ ] **Step 2: Review repository hygiene**

Run:

```bash
git status --short
git diff --check
git log --oneline --decorate -15
```

Expected: clean worktree, no whitespace errors, and one focused commit per task.

- [ ] **Step 3: Push the implementation branch**

Push the tracked implementation branch to `https://github.com/zifengjiang/Where`. Do not force-push. Open a draft pull request into `main` with the scope, architecture, test evidence, screenshots, and known limitations.
