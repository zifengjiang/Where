import Testing
@testable import Where

struct WhereSmokeTests {
    @Test
    func testingDependenciesCreateAnInMemoryDatabase() throws {
        let dependencies = try AppDependencies.testing()

        #expect(dependencies.database != nil)
    }
}
