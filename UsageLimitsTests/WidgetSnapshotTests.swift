import SwiftUI
import UIKit
import XCTest

/// Renders the medium widget to PNGs so the layout can be checked at the real size.
@MainActor
final class WidgetSnapshotTests: XCTestCase {
    func testMediumUnifiedSnapshot() throws {
        try render(UsageEntry.sample(provider: .claude, unified: true), named: "medium-unified.png")
    }

    func testMediumClassicSnapshot() throws {
        try render(UsageEntry.sample(provider: .claude), named: "medium-classic.png")
    }

    private func render(_ entry: UsageEntry, named name: String) throws {
        let view = MediumWidgetView(entry: entry)
            .padding(16)
            .frame(width: 338, height: 158)
            .background(TerminalBackground())
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .environment(\.colorScheme, .dark)
            .environment(\.widgetRenderingMode, .fullColor)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: 338, height: 158)
        let data = try XCTUnwrap(renderer.uiImage?.pngData(), "ImageRenderer produced no PNG for \(name)")

        let directory = ProcessInfo.processInfo.environment["TMX_SHOT_DIR"] ?? NSTemporaryDirectory()
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name)
        try data.write(to: url)
        XCTAssertGreaterThan(data.count, 1_000, url.path)
    }
}
