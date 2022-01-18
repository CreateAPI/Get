// The MIT License (MIT)
//
// Copyright (c) 2021-2022 Alexander Grebenyuk (github.com/kean).

import Foundation
import Get

// An example of an API definition. Feel free to use any other method for
// organizing the resources.
public enum Paths {}

// MARK: - /user

extension Paths {
    public static var user: UserResource { UserResource() }
    
    public struct UserResource {
        public let path: String = "/user"
        
        public var get: Request<User> { .get(path) }
    }
}

// MARK: - /user/emails

extension Paths.UserResource {
    public var emails: EmailsResource { EmailsResource() }
    
    public struct EmailsResource {
        public let path: String = "/user/emails"
        
        public var get: Request<[UserEmail]> { .get(path) }
        
        public func post(_ emails: [String]) -> Request<Void> {
            .post(path, body: emails)
        }
                
        public func delete() -> Request<Void> {
            .delete(path)
        }
    }
}

// MARK: - /users/{username}

extension Paths {
    public static func users(_ name: String) -> UsersResource {
        UsersResource(path: "/users/\(name)")
    }
    
    public struct UsersResource {
        public let path: String
                
        public var get: Request<User> { .get(path) }
    }
}

// MARK: - /users/{username}/followers

extension Paths.UsersResource {
    public var followers: FollowersResource { FollowersResource(path: path + "/followers") }
    
    public struct FollowersResource {
        public let path: String
                
        public var get: Request<[User]> { .get(path) }
    }
}

// MARK: - Entities

public struct UserEmail: Decodable {
    public var email: String
    public var verified: Bool
    public var primary: Bool
    public var visibility: String?
}

public struct User: Codable {
    public var id: Int
    public var login: String
    public var name: String?
    public var hireable: Bool?
    public var location: String?
    public var bio: String?
}

// MARK: - APIClientDelegate

enum GitHubError: Error {
    case unacceptableStatusCode(Int)
}

private final class GitHubAPIClientDelegate: APIClientDelegate {
    func client(_ client: APIClient, willSendRequest request: inout URLRequest) async throws {
        request.setValue("Bearer: \("your-access-token")", forHTTPHeaderField: "Authorization")
    }
        
    func shouldClientRetry(_ client: APIClient, withError error: Error) async throws -> Bool {
        if case .unacceptableStatusCode(let status) = (error as? GitHubError), status == 401 {
            return await refreshAccessToken()
        }
        return false
    }
    
    private func refreshAccessToken() async -> Bool {
        // TODO: Refresh (make sure you only refresh once if multiple requests fail)
        return false
    }
    
    func client(_ client: APIClient, didReceiveInvalidResponse response: HTTPURLResponse, data: Data) -> Error {
        GitHubError.unacceptableStatusCode(response.statusCode)
    }
}


// MARK: - Usage

func usage() async throws {
    let client = APIClient(host: "api.github.com") {
        $0.delegate = GitHubAPIClientDelegate()
    }
    
    let _ = try await client.send(Paths.user.get)
    let _ = try await client.send(Paths.user.emails.get)
    
//    try await client.send(Resources.user.emails.delete(["octocat@gmail.com"]))
        
    let _ = try await client.send(Paths.users("kean").followers.get)
    
    let _: User = try await client.send(.get("/user")).value
}
