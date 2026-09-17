import AppKit

/// Saves and restores the complete contents of a pasteboard: every item and every data type it carries (plain
/// and rich text, images, file URLs, app-specific types). Snapshots live in memory only, for well under a second.
struct ClipboardManager {
    /// One pasteboard item as (type, data) pairs, in the original type order.
    struct Snapshot: Equatable {
        var items: [[(type: NSPasteboard.PasteboardType, data: Data)]]
        var isEmpty: Bool { items.isEmpty }

        static func == (a: Snapshot, b: Snapshot) -> Bool {
            a.items.count == b.items.count && zip(a.items, b.items).allSatisfy { x, y in
                x.count == y.count && zip(x, y).allSatisfy { $0.type == $1.type && $0.data == $1.data }
            }
        }
    }

    /// Markers from nspasteboard.org: clipboard managers skip transient/concealed content, so dictated text
    /// doesn't pile up in the user's clipboard history.
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func snapshot() -> Snapshot {
        Snapshot(items: (pasteboard.pasteboardItems ?? []).map { item in
            // Types whose data can't be produced right now (e.g. unresolvable promises) are skipped.
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }.filter { !$0.isEmpty })
    }

    /// Replaces the pasteboard with `text` (plus transient markers). Returns the change count after writing.
    @discardableResult
    func write(transcript text: String) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: Self.transientType)
        item.setData(Data(), forType: Self.concealedType)
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }

    /// Restores a snapshot exactly (all items, all types). An empty snapshot clears the pasteboard.
    func restore(_ snapshot: Snapshot) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.items.map { pairs -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in pairs { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
