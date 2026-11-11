// SPDX-License-Identifier: MPL-2.0

import Foundation

/// HTTP request sent by an adapter through the native request handler.
public struct HttpRequest: Codable, Sendable {
    public let url: String
    public let method: String
    public let headers: [String: String]?
    public let body: String?

    public init(url: String, method: String = "GET", headers: [String: String]? = nil, body: String? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

/// HTTP response returned to an adapter.
public struct HttpResponse: Codable, Sendable {
    public let status: Int
    public let url: String
    public let headers: [String: String]
    public let body: String

    public init(status: Int, url: String, headers: [String: String], body: String) {
        self.status = status
        self.url = url
        self.headers = headers
        self.body = body
    }
}
