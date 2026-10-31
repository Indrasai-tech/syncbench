import XCTest
@testable import SyncBench

final class ModelTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testJSONValueKeepsNumbersAndBooleansApart() throws {
        let data = Data(#"{"count": 1, "zero": 0, "flag": true, "name": "x", "none": null}"#.utf8)
        let value = try decoder.decode([String: JSONValue].self, from: data)
        XCTAssertEqual(value["count"]?.description, "1")
        XCTAssertEqual(value["zero"]?.description, "0")
        XCTAssertEqual(value["flag"]?.description, "true")
        XCTAssertEqual(value["name"]?.description, "x")
        XCTAssertEqual(value["none"], .null)
    }

    func testRunDecodes() throws {
        let json = """
        {"id":"r1","scenario_id":"duplicate-request","synchronizer":"naive","seed":42,"status":"failed",
         "created_at":"2026-10-31T10:00:00+00:00","finished_at":null,"duration_ms":1.2,
         "summary":{"events":9,"retries":0,"lost_updates":0,"duplicate_effects":1,"fingerprint":"abc"},"error":null}
        """
        let run = try decoder.decode(TestRun.self, from: Data(json.utf8))
        XCTAssertEqual(run.scenarioId, "duplicate-request")
        XCTAssertEqual(run.summary?.duplicateEffects, 1)
        XCTAssertTrue(run.isFinished)
    }

    func testQueuedRunIsNotFinished() throws {
        let json = #"{"id":"r","scenario_id":"s","synchronizer":"reference","seed":1,"status":"queued"}"#
        XCTAssertFalse(try decoder.decode(TestRun.self, from: Data(json.utf8)).isFinished)
    }

    func testReportDecodesAndFlagsEvents() throws {
        let json = """
        {"scenario_id":"s","scenario_name":"S","synchronizer":"naive","policy":"server_wins","seed":1,"status":"failed",
         "assertions":[{"name":"a","passed":false,"expected":1,"actual":2,"message":"bad","event_seqs":[3,4]},
                       {"name":"b","passed":true,"expected":"x","actual":"x","message":"OK","event_seqs":[]}],
         "expected_final_state":{"count":1},"final_server_state":{"count":2},
         "metrics":{"events":2,"retries":0,"lost_updates":0,"duplicate_effects":1,"assertions_total":2,
                    "assertions_failed":1,"simulated_duration_ms":0,"wall_ms":0.5},
         "fingerprint":"f","events":[{"seq":1,"t_ms":0,"actor":"runner","type":"run_started","detail":{"op_id":"A-1"}}]}
        """
        let report = try decoder.decode(TestReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.flaggedEventSeqs, [3, 4])
        XCTAssertEqual(report.finalServerState["count"]?.description, "2")
        XCTAssertEqual(report.events.first?.detail["op_id"]?.description, "A-1")
    }

    func testSynchronizerChoiceApiValue() {
        XCTAssertNil(SynchronizerChoice.scenarioDefault.apiValue)
        XCTAssertEqual(SynchronizerChoice.naive.apiValue, "naive")
    }
}
