import XCTest
@testable import SyncBench

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else { return }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class APIClientTests: XCTestCase {
    private var store: LocalStore!
    private var client: APIClient!

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: "syncbench.tests.\(UUID().uuidString)")!
        store = LocalStore(defaults: defaults)
        store.baseURL = "http://example.test:8000/"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        client = APIClient(session: URLSession(configuration: config), store: store)
    }

    private func response(_ url: URL, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    func testBuildsURLWithoutDoubleSlash() throws {
        let url = try client.makeURL(path: "/api/v1/runs", query: [URLQueryItem(name: "limit", value: "5")])
        XCTAssertEqual(url.absoluteString, "http://example.test:8000/api/v1/runs?limit=5")
    }

    func testInvalidBaseURLThrows() {
        store.baseURL = "not a url"
        XCTAssertThrowsError(try client.makeURL(path: "/x", query: []))
    }

    func testSendsAPIKeyHeaderAndDecodes() async throws {
        store.apiKey = "secret"
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-API-Key"), "secret")
            return (self.response(request.url!, 200), Data(#"{"status":"ok","scenarios":5}"#.utf8))
        }
        let health = try await RunService(api: client).health()
        XCTAssertEqual(health.status, "ok")
        XCTAssertEqual(health.scenarios, 5)
    }

    func testHTTPErrorSurfacesServerDetail() async {
        MockURLProtocol.handler = { request in
            (self.response(request.url!, 404), Data(#"{"detail":"Run 'x' not found"}"#.utf8))
        }
        do {
            _ = try await RunService(api: client).run(id: "x")
            XCTFail("expected an error")
        } catch let APIError.http(status, message) {
            XCTAssertEqual(status, 404)
            XCTAssertTrue(message.contains("not found"))
        } catch {
            XCTFail("wrong error \(error)")
        }
    }

    func testMalformedJSONBecomesDecodingError() async {
        MockURLProtocol.handler = { request in (self.response(request.url!, 200), Data("nope".utf8)) }
        do {
            _ = try await RunService(api: client).stats()
            XCTFail("expected an error")
        } catch APIError.decoding {
        } catch {
            XCTFail("wrong error \(error)")
        }
    }
}
