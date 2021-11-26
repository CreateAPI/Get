// The MIT License (MIT)
//
// Copyright (c) 2021 Alexander Grebenyuk (github.com/kean).

import Foundation

public protocol APIClientDelegate {
    func client(_ client: APIClient, willSendRequest request: inout URLRequest)
    func shouldClientRetry(_ client: APIClient, withError error: Error) async -> Bool
    func client(_ client: APIClient, didReceiveInvalidResponse response: HTTPURLResponse, data: Data) -> Error
}

public actor APIClient {
    private let session: URLSession
    private let host: String
    private let serializer = Serializer()
    private let delegate: APIClientDelegate
    
    public init(host: String, configuration: URLSessionConfiguration = .default, delegate: APIClientDelegate? = nil) {
        self.host = host
        self.session = URLSession(configuration: configuration)
        self.delegate = delegate ?? DefaultAPIClientDelegate()
    }

    public func send<T: Decodable>(_ request: Request<T>) async throws -> T {
        try await send(request, serializer.decode)
    }
    
    public func send(_ request: Request<Void>) async throws -> Void {
        try await send(request) { _ in () }
    }

    private func send<T>(_ request: Request<T>, _ decode: @escaping (Data) async throws -> T) async throws -> T {
        let request = try await makeRequest(for: request)
        let (data, response) = try await send(request)
        try validate(response: response, data: data)
        return try await decode(data)
    }
    
    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await actuallySend(request)
        } catch {
            guard await delegate.shouldClientRetry(self, withError: error) else { throw error }
            return try await actuallySend(request)
        }
    }
     
    private func actuallySend(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        delegate.client(self, willSendRequest: &request)
        if #available(macOS 12.0, iOS 15.0, macCatalyst 15.0, watchOS 8.0, tvOS 15.0, *) {
            return try await session.data(for: request, delegate: nil)
        } else {
            return try await session.asyncData(for: request)
        }
    }
    
    private func makeRequest<T>(for request: Request<T>) async throws -> URLRequest {
        let url = try makeURL(path: request.path, query: request.query)
        return try await makeRequest(url: url, method: request.method, body: request.body)
    }
    
    private func makeURL(path: String, query: [String: String]?) throws -> URL {
        guard let url = URL(string: path),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        if path.starts(with: "/") {
            components.scheme = "https"
            components.host = host
        }
        if let query = query {
            components.queryItems = query.map(URLQueryItem.init)
        }
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        return url
    }
    
    private func makeRequest(url: URL, method: String, body: AnyEncodable?) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body = body {
            request.httpBody = try await serializer.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
        
    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        if !(200..<300).contains(httpResponse.statusCode) {
            throw delegate.client(self, didReceiveInvalidResponse: httpResponse, data: data)
        }
    }
}

public extension APIClientDelegate {
    func client(_ client: APIClient, willSendRequest request: inout URLRequest) {}
    func shouldClientRetry(_ client: APIClient, withError error: Error) async -> Bool { false }
    func client(_ client: APIClient, didReceiveInvalidResponse response: HTTPURLResponse, data: Data) -> Error {
        URLError(.cannotParseResponse, userInfo: [NSLocalizedDescriptionKey: "Response status code was unacceptable: \(response.statusCode)."])
    }
}

private struct DefaultAPIClientDelegate: APIClientDelegate {}

private actor Serializer {
    func encode<T: Encodable>(_ entity: T) async throws -> Data {
        try JSONEncoder().encode(entity)
    }
    
    func decode<T: Decodable>(_ data: Data) async throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }
}
