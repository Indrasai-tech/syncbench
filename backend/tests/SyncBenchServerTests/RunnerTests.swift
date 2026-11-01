import XCTest
@testable import SyncBenchServer

final class RunnerTests: XCTestCase {
    func testBuiltInScenariosValidateAndReferencePasses() throws {
        let scenarios = try ScenarioCatalog.load()
        XCTAssertGreaterThanOrEqual(scenarios.count, 5)
        for scenario in scenarios.values {
            XCTAssertNoThrow(try scenario.validate(), scenario.id)
            var runner = ScenarioRunner(scenario: scenario, synchronizer: "reference")
            XCTAssertEqual(runner.run().status, "passed", scenario.id)
        }
    }

    func testSeededScenarioHasStableFingerprint() throws {
        let scenario = try XCTUnwrap(ScenarioCatalog.load()["retry-after-timeout"])
        var firstRunner = ScenarioRunner(scenario: scenario, seed: 991)
        var secondRunner = ScenarioRunner(scenario: scenario, seed: 991)
        let first = firstRunner.run()
        let second = secondRunner.run()
        XCTAssertEqual(first.fingerprint, second.fingerprint)
        XCTAssertEqual(first.metrics.simulatedDurationMs, second.metrics.simulatedDurationMs)
    }

    func testDuplicateDeliveryIsDetectedByNaiveSynchronizer() throws {
        let scenario = try XCTUnwrap(ScenarioCatalog.load()["duplicate-request"])
        var runner = ScenarioRunner(scenario: scenario, synchronizer: "naive")
        let report = runner.run()
        XCTAssertEqual(report.status, "failed")
        XCTAssertGreaterThan(report.metrics.duplicateEffects, 0)
    }
}
