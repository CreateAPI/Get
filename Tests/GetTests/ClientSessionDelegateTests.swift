// The MIT License (MIT)
//
// Copyright (c) 2021-2024 Alexander Grebenyuk (github.com/kean).

import XCTest
@testable import Get

#if !os(Linux) && !os(Android)
final class APIClientSessionDelegateTests: XCTestCase {
    private let delegate = SessionDelegate()
    private var client: APIClient!

    override func setUp() {
        super.setUp()

        self.client = .mock {
            $0.sessionDelegate = delegate
        }
    }

    // MARK: - Configuration

    func testThatDelegateQueueIsUsed() async throws {
        // GIVEN
        let sessionDelegateQueue = OperationQueue()
        let queue = DispatchQueue(label: "com.get.api-client-tests")
        let queueKey = DispatchSpecificKey<Void>()
        queue.setSpecific(key: queueKey, value: ())
        sessionDelegateQueue.underlyingQueue = queue

        self.client = .mock {
            $0.sessionDelegate = delegate
            $0.sessionDelegateQueue = sessionDelegateQueue
        }

        self.delegate.onMetrics = { [unowned self] _ in
            XCTAssertNotNil(DispatchQueue.getSpecific(key: queueKey))
            self.delegate.onMetrics = nil
        }

        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock.get(url: url, json: "user").register()

        // WHEN
        try await client.send(Request(path: "/user"))

        // THEN
        XCTAssertNil(self.delegate.onMetrics)
    }

    // MARK: - Global Delegate

    func testThatMetricsAreCollected() async throws {
        #if os(watchOS)
        throw XCTSkip("Mocker URLProtocol isn't being called for requests on watchOS")
        #endif

        // GIVEN
        let url = URL(string: "https://api.github.com/user")!
        Mock.get(url: url, json: "user").register()

        // WHEN
        try await client.send(Request(path: "/user"))

        // THEN
        XCTAssertEqual(delegate.metrics.count, 1)
        let metrics = try XCTUnwrap(delegate.metrics.first?.value)
        let transaction = try XCTUnwrap(metrics.transactionMetrics.first)
        XCTAssertEqual(transaction.request.url, URL(string: "https://api.github.com/user"))
    }

    func testInvalidateSession() async throws {
        let expectation = self.expectation(description: "didBecomeInvalid")
        delegate.onDidBecomeInvalid = { _ in
            expectation.fulfill()
        }

        client.session.invalidateAndCancel()

#if swift(>=5.9)
        await fulfillment(of: [expectation], timeout: 2)
#else
        wait(for: [expectation], timeout: 2)
#endif
    }

    // MARK: - Per-Task Delegate

    func testSettingDelegate() async throws {
        // GIVEN
        self.client = .mock()

        final class MockDelegate: NSObject, URLSessionDataDelegate {
            var response: URLResponse?

            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
                self.response = response
                return .cancel
            }
        }

        let url = URL(string: "https://api.github.com/user")!
        Mock.get(url: url, json: "user").register()

        // WHEN
        let delegate = MockDelegate()
        let request = Request(url: URL(string: "/user")!)
        do {
            try await client.send(request, delegate: delegate)
            XCTFail("Request was supposed to be cancelled")
        } catch {
            // Do nothing
        }

        // THEN
        XCTAssertEqual(delegate.response?.url, url)
    }

    func testSettingDelegateCallbackBased() async throws {
        // GIVEN
        self.client = .mock()

        final class MockDelegate: NSObject, URLSessionDataDelegate {
            var response: URLResponse?

            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
                self.response = response
                completionHandler(.cancel)
            }
        }
        let url = URL(string: "https://api.github.com/user")!
        Mock.get(url: url, json: "user").register()

        // WHEN
        let delegate = MockDelegate()
        let request = Request(url: URL(string: "/user")!)
        do {
            try await client.send(request, delegate: delegate)
            XCTFail("Request was supposed to be cancelled")
        } catch {
            // Do nothing
        }

        // THEN
        XCTAssertEqual(delegate.response?.url, url)
    }

    func testSetTaskDelegateTogetherWithSessionDelegate() async throws {
        // GIVEN
        final class MockDelegate: NSObject, URLSessionDataDelegate {
            var response: URLResponse?

            func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
                self.response = response
                completionHandler(.cancel)
            }
        }
        let url = URL(string: "https://api.github.com/user")!
        Mock.get(url: url, json: "user").register()

        // WHEN
        let delegate = MockDelegate()
        let request = Request(url: URL(string: "/user")!)
        do {
            try await client.send(request, delegate: delegate)
            XCTFail("Request was supposed to be cancelled")
        } catch {
            // Do nothing
        }

        // THEN
        XCTAssertEqual(delegate.response?.url, url)
    }
}

private final class SessionDelegate: NSObject, URLSessionTaskDelegate {
    var metrics: [URLSessionTask: URLSessionTaskMetrics] = [:]
    var onMetrics: ((URLSessionTaskMetrics) -> Void)?

    var onDidBecomeInvalid: ((Error?) -> Void)?

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        onDidBecomeInvalid?(error)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        self.onMetrics?(metrics)
        self.metrics[task] = metrics
    }
}
#endif
