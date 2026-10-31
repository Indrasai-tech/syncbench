import Foundation

enum APIError: LocalizedError {
    case invalidURL(String)
    case http(status: Int, message: String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let s): return "Invalid server address: \(s)"
        case .http(let status, let message): return "Server returned \(status): \(message)"
        case .decoding(let s): return "Could not read the server response (\(s))"
        case .transport(let s): return "Could not reach the server: \(s)"
        }
    }
}

final class APIClient {
    private let session: URLSession
    private let store: LocalStore
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared, store: LocalStore = .shared) {
        self.session = session
        self.store = store
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        let data = try await send(method: "GET", path: path, query: query, body: nil)
        return try decode(data)
    }

    func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let data = try await send(method: "POST", path: path, query: [], body: try JSONEncoder().encode(body))
        return try decode(data)
    }

    func postEmpty<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send(method: "POST", path: path, query: [], body: nil)
        return try decode(data)
    }

    func text(_ path: String, query: [URLQueryItem] = []) async throws -> String {
        let data = try await send(method: "GET", path: path, query: query, body: nil)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Internals

    func makeURL(path: String, query: [URLQueryItem]) throws -> URL {
        var base = store.baseURL
        while base.hasSuffix("/") { base.removeLast() }
        guard var comps = URLComponents(string: base + path), comps.scheme != nil, comps.host != nil else {
            throw APIError.invalidURL(base)
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError.invalidURL(base) }
        return url
    }

    private func send(method: String, path: String, query: [URLQueryItem], body: Data?) async throws -> Data {
        var request = URLRequest(url: try makeURL(path: path, query: query))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let key = store.apiKey
        if !key.isEmpty { request.setValue(key, forHTTPHeaderField: "X-API-Key") }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.transport("no HTTP response") }
            guard (200..<300).contains(http.statusCode) else {
                throw APIError.http(status: http.statusCode, message: Self.errorMessage(from: data))
            }
            return data
        } catch let error as APIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(String(describing: error)) }
    }

    private static func errorMessage(from data: Data) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = obj["detail"] as? String { return detail }
        return String(decoding: data.prefix(200), as: UTF8.self)
    }
}
