import Foundation
import Testing
@testable import VaultCore

/// Exercises the widget→app "mark returned" queue against a temp directory,
/// so it runs without an App Group entitlement.
private func tempStore() -> (PendingReturnStore, URL) {
    let dir = FileManager.default.temporaryDirectory
        .appending(path: "pending-return-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return (PendingReturnStore(directory: dir), dir)
}

@Test("An empty queue reads as empty, not nil-crash")
func emptyQueue() {
    let (store, dir) = tempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(store.pending().isEmpty)
}

@Test("Enqueue persists ids in insertion order")
func enqueueOrder() {
    let (store, dir) = tempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    store.enqueue("a")
    store.enqueue("b")
    #expect(store.pending() == ["a", "b"])
}

@Test("Enqueue de-duplicates so a double tap applies once")
func enqueueDedup() {
    let (store, dir) = tempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    store.enqueue("a")
    store.enqueue("a")
    #expect(store.pending() == ["a"])
}

@Test("Remove clears applied ids and keeps the rest")
func removeApplied() {
    let (store, dir) = tempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    store.enqueue("a")
    store.enqueue("b")
    store.enqueue("c")
    store.remove(["a", "c"])
    #expect(store.pending() == ["b"])
}

@Test("A fresh store at the same directory sees the persisted queue")
func persistsAcrossInstances() {
    let (store, dir) = tempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    store.enqueue("a")
    #expect(PendingReturnStore(directory: dir).pending() == ["a"])
}
