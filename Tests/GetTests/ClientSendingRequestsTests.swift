// The MIT License (MIT)
//
// Copyright (c) 2021-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Get

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ClientSendingRequestsTests: XCTestCase {
    var client: APIClient!

    override func setUp() {
        super.setUp()

        self.client = .mock()
    }

    // MARK: - Basic Requests

    // You don't need to provide a predefined list of resources in your app.
    // You can define the requests inline instead.
    func testDefiningRequestInline() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock.get(url: url, json: "user").register()

        // WHEN
        let user: User = try await client.send(Request(path: "/user")).value

        // THEN
        XCTAssertEqual(user.login, "kean")
    }

    func testResponseMetadata() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock.get(url: url, json: "user").register()

        // WHEN
        let response = try await client.send(Paths.user.get)

        // THEN the client returns not just the value, but data, original
        // request, and more
        XCTAssertEqual(response.value.login, "kean")
        XCTAssertEqual(response.data.count, 1321)
        XCTAssertEqual(response.originalRequest?.url, url)
        XCTAssertEqual(response.statusCode, 200)
#if !os(Linux) && !os(Android)
        let metrics = try XCTUnwrap(response.metrics)
        let transaction = try XCTUnwrap(metrics.transactionMetrics.first)
        XCTAssertEqual(transaction.request.url, URL(string: "https://api.github.com/user"))
#endif
    }

    func testFailingRequest() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock(url: url, dataType: .json, statusCode: 500, data: [
            .get: "nope".data(using: .utf8)!
        ]).register()

        // WHEN
        do {
            try await client.send(Request(path: "/user"))
        } catch {
            // THEN
            let error = try XCTUnwrap(error as? APIError)
            switch error {
            case .unacceptableStatusCode(let code):
                XCTAssertEqual(code, 500)
            }
        }
    }

    func testSendingRequestWithInvalidURL() async throws {
        // GIVEN
        let request = Request(path: "https://api.github.com  ---invalid")

        // WHEN
        do {
            try await client.send(request)
        } catch {
            // THEN
            let error = try XCTUnwrap(error as? URLError)
            XCTAssertEqual(error.code, .badURL)
        }
    }

    func testCancellingRequests() async throws {
        // Given
        let url = URL(string: "https://api.github.com/users/kean")!
        var mock = Mock.get(url: url, json: "user")
        mock.delay = DispatchTimeInterval.seconds(60)
        mock.register()

        // When
        let task = Task {
            try await client.send(Request(path: "/users/kean"))
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(100)) {
            task.cancel()
        }

        // Then
        do {
            _ = try await task.value
        } catch {
            XCTAssertTrue(error is URLError)
            XCTAssertEqual((error as? URLError)?.code, .cancelled)
        }
    }

    // MARK: - Response Types

    // func value(for:) -> Decodable
    func testResponseDecodable() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock.get(url: url, json: "user").register()

        // WHEN
        let user: User = try await client.send(Request(path: "/user")).value

        // THEN returns decoded JSON
        XCTAssertEqual(user.login, "kean")
    }

    func testResponseDecodableOptionalNotNil() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock.get(url: url, json: "user").register()

        // WHEN
        let user: User? = try await client.send(Request(path: "/user")).value

        // THEN returns decoded JSON
        XCTAssertEqual(user?.login, "kean")
    }
    
    // func value(for:) -> Decodable
    func testResponseEmpty() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock(url: url, dataType: .html, statusCode: 200, data: [
            .get: Data()
        ]).register()

        // WHEN
        try await client.send(Request(path: "/user")).value
    }
    
    func testResponseEmptyWithDecodableOptional() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock(url: url, dataType: .json, statusCode: 204, data: [
            .get: Data()
        ]).register()
        
        // WHEN
        let user: User? = try await client.send(Request(path: "/user")).value
        
        // THEN returns nil response
        XCTAssertNil(user)
    }

    // func value(for:) -> Data
    func testResponseData() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock(url: url, dataType: .html, statusCode: 200, data: [
            .get: "<h>Hello</h>".data(using: .utf8)!
        ]).register()

        // WHEN
        let data: Data = try await client.send(Request(path: "/user")).value

        // THEN return unprocessed data (NOT what Data: Decodable does by default)
        XCTAssertEqual(String(data: data, encoding: .utf8), "<h>Hello</h>")
    }

    // func value(for:) -> String
    func testResponseString() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock(url: url, dataType: .json, statusCode: 200, data: [
            .get: "hello".data(using: .utf8)!
        ]).register()

        // WHEN
        let text: String = try await client.send(Request(path: "/user")).value

        // THEN
        XCTAssertEqual(text, "hello")
    }

    func testDecodingWithVoidResponse() async throws {
#if os(watchOS)
        throw XCTSkip("Mocker URLProtocol isn't being called for POST requests on watchOS")
#endif

        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock(url: url, dataType: .json, statusCode: 200, data: [
            .post: json(named: "user")
        ]).register()

        // WHEN
        let request = Request(path: "/user", method: .post, body: ["login": "kean"])
        try await client.send(request)
    }

    func testChangingResponseType() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock.get(url: url, json: "user").register()

        let request = Request(path: "/user")

        // WHEN
        let string = try await client.send(request.withResponse(String.self)).value

        // THEN
        XCTAssertTrue(string.contains(#""login": "kean"#))
    }

    // MARK: - Retries

    func testRetries() async throws {
        // GIVEN
        final class RetryingDelegate: APIClientDelegate {
            func client(_ client: APIClient, shouldRetry task: URLSessionTask, error: Error, attempts: Int) async throws -> Bool {
                attempts < 3
            }
        }

        let client = APIClient.mock {
            $0.delegate = RetryingDelegate()
        }

        let url = URL(string: "https://api.github.com/user")!
        var mock = Mock(url: url, dataType: .json, statusCode: 401, data: [
            .get: "Unauthorized".data(using: .utf8)!
        ])
        var attemptsCount = 0
        mock.onRequest = { _, _ in
            attemptsCount += 1
        }
        mock.register()

        // WHEN
        do {
            try await client.send(Request(path: "/user"))
            XCTFail("Expected request to fail")
        } catch {
            XCTAssertEqual(attemptsCount, 3)
            let error = try XCTUnwrap(error as? APIError)
            switch error {
            case let .unacceptableStatusCode(statusCode):
                XCTAssertEqual(statusCode, 401)
            }
        }
    }

    func testDecodingFailureDoesntStartRetry() async throws {
        // GIVEN
        final class RetryingDelegate: APIClientDelegate {
            func client(_ client: APIClient, shouldRetry task: URLSessionTask, error: Error, attempts: Int) async throws -> Bool {
                XCTFail("Retries are not expected to be called")
                return false
            }
        }

        let url = URL(string: "https://api.github.com/user")!
        Mock(url: url, dataType: .json, statusCode: 200, data: [
            .get: "invalid-response".data(using: .utf8)!
        ]).register()

        // WHEN
        do {
            let _: User = try await client.send(Request(path: "/user")).value
            XCTFail()
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }

    // MARK: - Fetching Data

    func testFetchData() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock.get(url: url, json: "user").register()

        // WHEN
        let response = try await client.data(for: Request(path: "/user"))

        // THEN
        let user = try JSONDecoder().decode(User.self, from: response.data)
        XCTAssertEqual(user.login, "kean")
    }

    // MARK: - Downloads

#if !os(Linux) && !os(Android)
    func testDownloads() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock.get(url: url, json: "user").register()

        // WHEN
        let response = try await client.download(for: Request(path: "/user"))

        // THEN
        let data = try Data(contentsOf: response.location)
        let user = try JSONDecoder().decode(User.self, from: data)
        XCTAssertEqual(user.login, "kean")
    }
#endif

    // MARK: - Uploads

    func testUpload() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock(url: url, dataType: .json, statusCode: 200, data: [
            .post: json(named: "user")
        ]).register()

        // WHEN

        let fileURL = try XCTUnwrap(Bundle.module.url(forResource: "user", withExtension: "json"))
        let user: User = try await client.upload(for: Request(path: "/user", method: .post), fromFile: fileURL).value

        // THEN
        XCTAssertEqual(user.login, "kean")
    }

    // MARK: - Request Body

    func testPassEncodableRequestBody() async throws {
#if os(watchOS)
        throw XCTSkip("Mocker URLProtocol isn't being called for POST requests on watchOS")
#endif

        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        var mock = Mock(url: url, dataType: .json, statusCode: 200, data: [
            .post: json(named: "user")
        ])
        mock.onRequest = { request, _ in
            guard let body = request.httpBody ?? request.httpBodyStream?.data,
                  let json = try? JSONSerialization.jsonObject(with: body, options: []),
                  let user = json as? [String: Any] else {
                return XCTFail()
            }
            XCTAssertEqual(user["id"] as? Int, 1)
            XCTAssertEqual(user["login"] as? String, "kean")
        }
        mock.register()

        // WHEN
        var request = Request(path: "/user", method: .post)
        request.body = User(id: 1, login: "kean")
        try await client.send(request)
    }

    func testPassingNilBody() async throws {
#if os(watchOS)
        throw XCTSkip("Mocker URLProtocol isn't being called for POST requests on watchOS")
#endif

        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        var mock = Mock(url: url, dataType: .json, statusCode: 200, data: [
            .post: json(named: "user")
        ])
        mock.onRequest = { request, _ in
            XCTAssertNil(request.httpBody)
            XCTAssertNil(request.httpBodyStream)
        }
        mock.register()

        // WHEN
        let body: User? = nil
        let request = Request(path: "/user", method: .post, body: body)
        try await client.send(request)
    }

    func testPassingCustomBody() async throws {
#if os(watchOS)
        throw XCTSkip("Mocker URLProtocol isn't being called for POST requests on watchOS")
#endif

        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        var mock = Mock(url: url, dataType: .json, statusCode: 200, data: [
            .post: json(named: "user")
        ])
        mock.onRequest = { request, _ in
            guard let body = request.httpBody ?? request.httpBodyStream?.data,
                  let json = try? JSONSerialization.jsonObject(with: body, options: []),
                  let user = json as? [String: Any] else {
                return XCTFail()
            }
            // THEN
            XCTAssertEqual(user["id"] as? Int, 1)
            XCTAssertEqual(user["login"] as? String, "kean")
        }
        mock.register()

        // WHEN/THEN
        try await client.send(Request(path: "/user", method: .post)) {
            let user = User(id: 1, login: "kean")
            $0.httpBody = try JSONEncoder().encode(user)
        }
    }

    func testPassingDataAsEncodableBody() async throws {
#if os(watchOS)
        throw XCTSkip("Mocker URLProtocol isn't being called for POST requests on watchOS")
#endif

        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        var mock = Mock(url: url, dataType: .json, statusCode: 200, data: [
            .post: json(named: "user")
        ])
        mock.onRequest = { request, _ in
            guard let body = request.httpBody ?? request.httpBodyStream?.data,
                  let string = String(data: body, encoding: .utf8) else {
                return XCTFail()
            }
            // THEN
            XCTAssertEqual(string, "hello")
        }
        mock.register()

        // WHEN/THEN
        let body = "hello".data(using: .utf8)!
        try await client.send(Request(path: "/user", body: body))
    }

    func testPassingStringAsEncodableBody() async throws {
#if os(watchOS)
        throw XCTSkip("Mocker URLProtocol isn't being called for POST requests on watchOS")
#endif

        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        var mock = Mock(url: url, dataType: .json, statusCode: 200, data: [
            .post: json(named: "user")
        ])
        mock.onRequest = { request, _ in
            guard let body = request.httpBody ?? request.httpBodyStream?.data,
                  let string = String(data: body, encoding: .utf8) else {
                return XCTFail()
            }
            // THEN
            XCTAssertEqual(string, "hello")
        }
        mock.register()

        // WHEN/THEN
        let request = Request(path: "/user", method: .post, body: "hello")
        try await client.send(request)
    }

    // MARK: - Configuring Request

    func testConfigureRequest() async throws {
        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        var mock = Mock.get(url: url, json: "user")
        var request: URLRequest?
        mock.onRequest = { a, _ in
            request = a
        }
        mock.register()

        // WHEN
        let response: Response<User> = try await client.send(Request(path: "/user")) {
            $0.cachePolicy = .reloadIgnoringLocalCacheData
        }

        // THEN
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(response.value.login, "kean")
    }

#if !os(Linux) && !os(Android) // This doesn't work on Linux
    func testSetHTTPAdditionalHeaders() async throws {
        // GIVEN
        client = .mock {
            $0.sessionConfiguration.httpAdditionalHeaders = [
                "x-custom-field": "1"
            ]
        }

        let url = URL(string: "https://api.github.com/user")!
        Mock.get(url: url, json: "user").register()

        // WHEN
        let response = try await client.send(Request(path: "/user"))

        // THEN
        XCTAssertNil(response.originalRequest?.value(forHTTPHeaderField: "x-custom-field"))
        XCTAssertEqual(response.currentRequest?.value(forHTTPHeaderField: "x-custom-field"), "1")
    }
#endif
}
