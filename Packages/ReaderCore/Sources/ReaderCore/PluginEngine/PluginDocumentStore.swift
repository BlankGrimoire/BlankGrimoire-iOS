// SPDX-License-Identifier: MPL-2.0

import Foundation
import SwiftSoup

/// Stores SwiftSoup documents and elements that are exposed to `runtime.js`.
///
/// The SDK runtime expects a synchronous `DocumentLike` implementation. The
/// store keeps the Swift objects alive while JavaScript holds opaque node ids,
/// and performs every SwiftSoup operation under a lock.
final class PluginDocumentStore: @unchecked Sendable {
    private struct ElementEntry {
        let element: Element
        let documentID: String
    }

    private let lock = NSLock()
    private var documents: [String: Document] = [:]
    private var elements: [String: ElementEntry] = [:]
    private var sequence: UInt64 = 0

    func parse(_ html: String) throws -> String {
        let document = try SwiftSoup.parse(html)
        return lock.withLock {
            sequence += 1
            let id = "d:\(sequence)"
            documents[id] = document
            return id
        }
    }

    func release(_ documentID: String) {
        lock.withLock {
            documents.removeValue(forKey: documentID)
            elements = elements.filter { $0.value.documentID != documentID }
        }
    }

    func clear() {
        lock.withLock {
            documents.removeAll()
            elements.removeAll()
        }
    }

    func querySelector(_ nodeID: String, _ selector: String) -> String? {
        lock.withLock {
            guard let (root, documentID) = rootLocked(nodeID),
                let element = try? root.select(selector).first()
            else {
                return nil
            }
            return registerLocked(element, documentID: documentID)
        }
    }

    func querySelectorAll(_ nodeID: String, _ selector: String) -> [String] {
        lock.withLock {
            guard let (root, documentID) = rootLocked(nodeID),
                let selected = try? root.select(selector)
            else {
                return []
            }
            return selected.map { registerLocked($0, documentID: documentID) }
        }
    }

    func documentElement(_ documentID: String) -> String? {
        lock.withLock {
            guard let document = documents[documentID],
                let element = document.children().first()
            else {
                return nil
            }
            return registerLocked(element, documentID: documentID)
        }
    }

    func getAttribute(_ nodeID: String, _ name: String) -> String? {
        lock.withLock {
            guard let element = elements[nodeID]?.element, element.hasAttr(name) else {
                return nil
            }
            return try? element.attr(name)
        }
    }

    func textContent(_ nodeID: String) -> String? {
        lock.withLock {
            if let document = documents[nodeID] {
                return try? document.text()
            }
            guard let element = elements[nodeID]?.element else {
                return nil
            }
            // Inline scripts and styles store their payload as data nodes, so
            // `text()` would return an empty string for them.
            let tag = element.tagName().lowercased()
            if tag == "script" || tag == "style" {
                return element.data()
            }
            return try? element.text()
        }
    }

    func innerHTML(_ nodeID: String) -> String? {
        lock.withLock {
            if let document = documents[nodeID] {
                return try? document.html()
            }
            guard let element = elements[nodeID]?.element else {
                return nil
            }
            return try? element.html()
        }
    }

    private func rootLocked(_ nodeID: String) -> (Element, String)? {
        if let document = documents[nodeID] {
            return (document, nodeID)
        }
        if let entry = elements[nodeID] {
            return (entry.element, entry.documentID)
        }
        return nil
    }

    private func registerLocked(_ element: Element, documentID: String) -> String {
        sequence += 1
        let id = "e:\(sequence)"
        elements[id] = ElementEntry(element: element, documentID: documentID)
        return id
    }
}
