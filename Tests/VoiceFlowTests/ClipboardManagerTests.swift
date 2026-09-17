import AppKit
import Testing
@testable import VoiceFlow

/// Uses private, uniquely named pasteboards: the user's clipboard is never touched.
@MainActor @Suite(.serialized) struct ClipboardManagerTests {
    func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("VoiceFlowTests-\(UUID().uuidString)"))
    }

    @Test func roundTripsMultipleItemsAndTypes() throws {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        let custom = NSPasteboard.PasteboardType("com.example.custom")
        let png = try #require(NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.systemRed.setFill(); rect.fill(); return true
        }.tiffRepresentation)

        let first = NSPasteboardItem()
        first.setString("hello", forType: .string)
        first.setData(Data(#"{\rtf1 hello}"#.utf8), forType: .rtf)
        first.setData(Data([0, 1, 2, 255]), forType: custom)
        let second = NSPasteboardItem()
        second.setData(png, forType: .tiff)
        pb.clearContents()
        pb.writeObjects([first, second])

        let manager = ClipboardManager(pasteboard: pb)
        let saved = manager.snapshot()
        #expect(saved.items.count == 2)

        manager.write(transcript: "dictated text")
        #expect(pb.string(forType: .string) == "dictated text")
        #expect(pb.types?.contains(ClipboardManager.transientType) == true)
        #expect(pb.types?.contains(ClipboardManager.concealedType) == true)

        manager.restore(saved)
        #expect(manager.snapshot() == saved)
        #expect(pb.string(forType: .string) == "hello")
        #expect(pb.data(forType: custom) == Data([0, 1, 2, 255]))
        #expect(pb.pasteboardItems?.count == 2)
        #expect(pb.pasteboardItems?[1].data(forType: .tiff) == png)
    }

    @Test func emptyClipboardRestoresToEmpty() {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        pb.clearContents()
        let manager = ClipboardManager(pasteboard: pb)
        let saved = manager.snapshot()
        #expect(saved.isEmpty)
        manager.write(transcript: "x")
        manager.restore(saved)
        #expect(pb.pasteboardItems?.isEmpty ?? true)
    }

    @Test func writeIncrementsChangeCountSoUserCopiesAreDetectable() {
        let pb = makePasteboard()
        defer { pb.releaseGlobally() }
        let manager = ClipboardManager(pasteboard: pb)
        let afterWrite = manager.write(transcript: "dictated")
        #expect(manager.changeCount == afterWrite)
        pb.clearContents()
        pb.setString("user copied something", forType: .string)
        #expect(manager.changeCount != afterWrite)
    }
}
