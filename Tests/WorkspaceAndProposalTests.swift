// WorkspaceAndProposalTests.swift
// Workspace store (competitions/images/judges), audit chain and the
// heuristic proposal engine.

import XCTest
import CoreGraphics
import UIKit
@testable import PrivateJudgesWorkspace

final class WorkspaceStoreTests: XCTestCase {

    private func tempRoot(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pjw-tests-\(name)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A tiny deterministic image: 64x48 gray background with a dark disc.
    private func syntheticImageData() -> Data {
        let w = 64, h = 48
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        context.setFillColor(gray: 0.05, alpha: 1)
        context.fillEllipse(in: CGRect(x: 30 - 6, y: 24 - 6, width: 12, height: 12))
        let image = try! XCTUnwrap(context.makeImage())
        return jpegData(image)
    }

    private func jpegData(_ image: CGImage) -> Data {
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: image.width, height: image.height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: rect)
        let uiImage = UIImage(cgImage: ctx.makeImage()!)
        return uiImage.jpegData(compressionQuality: 0.95)!
    }

    func testCompetitionAndImageLifecycle() throws {
        let store = WorkspaceStore(root: tempRoot("workspace"), vault: Vault.ephemeralVault())
        try store.addCompetition(id: "PJV-2026-R1", title: "Round 1")
        XCTAssertThrowsError(try store.addCompetition(id: "PJV-2026-R1", title: "dup"))

        let data = syntheticImageData()
        let entry = try store.addImageEntry(competitionId: "PJV-2026-R1", data: data,
                                            source: "photo_import")
        XCTAssertEqual(entry.id, CoordinateEngine.imageSHA256(data))
        XCTAssertEqual(entry.widthPx, 64)
        XCTAssertEqual(entry.heightPx, 48)
        XCTAssertEqual(store.entries(competitionId: "PJV-2026-R1").count, 1)

        let blob = try XCTUnwrap(store.imageData(for: entry.id))
        XCTAssertEqual(blob, data)

        // reopening the store reloads encrypted state
        let reopened = WorkspaceStore(root: store.root, vault: store.vault)
        XCTAssertEqual(reopened.competitions(activeOnly: false).count, 1)
        XCTAssertEqual(reopened.entries(competitionId: "PJV-2026-R1").count, 1)

        try store.setStatus(competitionId: "PJV-2026-R1", status: "archived")
        XCTAssertEqual(store.competitions().count, 0)
        XCTAssertEqual(store.competitions(activeOnly: false).count, 1)
    }

    func testInvalidIdentifiersRejected() throws {
        let store = WorkspaceStore(root: tempRoot("ids"), vault: Vault.ephemeralVault())
        XCTAssertThrowsError(try store.addCompetition(id: "bad id", title: "x"))
        XCTAssertThrowsError(try store.addJudgeProfile(id: "bad/id", displayName: "x"))
        XCTAssertNoThrow(try store.addJudgeProfile(id: "JUDGE-01", displayName: "Alpha"))
        XCTAssertThrowsError(try store.addJudgeProfile(id: "JUDGE-01", displayName: "dup"))
    }
}

final class AuditLogTests: XCTestCase {

    private func tempRoot(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pjw-tests-\(name)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testAppendAndVerifyChain() throws {
        let log = WorkspaceAuditLog(root: tempRoot("audit"), vault: Vault.ephemeralVault())
        log.append(actor: "project-owner", action: "competition_created",
                   details: ["competition_id": "PJV-1"], now: "2026-11-21T10:00:00Z")
        log.append(actor: "JUDGE-01", action: "crosshair_record_saved",
                   details: ["record_id": String(repeating: "e", count: 64)],
                   now: "2026-11-21T10:01:00Z")
        XCTAssertTrue(log.verifyChain())
        XCTAssertEqual(log.entries.count, 2)
        XCTAssertEqual(log.entries[0].prevEntryHash, "GENESIS")
        XCTAssertEqual(log.entries[1].prevEntryHash, log.entries[0].entryHash)

        // persistence round trip
        let reopened = WorkspaceAuditLog(root: log.root, vault: log.vault)
        XCTAssertEqual(reopened.entries.count, 2)
        XCTAssertTrue(reopened.verifyChain())
    }

    func testTamperedEntryBreaksChain() throws {
        let log = WorkspaceAuditLog(root: tempRoot("audit-tamper"), vault: Vault.ephemeralVault())
        log.append(actor: "a", action: "one", details: [:], now: "t0")
        log.append(actor: "b", action: "two", details: [:], now: "t1")
        var entries = log.entries
        entries[0].action = "forged"
        let broken = WorkspaceAuditLog(root: tempRoot("audit-broken"), vault: Vault.ephemeralVault())
        // inject the forged entries directly through save path
        // (save is private; emulate by re-sealing with the same vault)
        let sealed = try broken.vault.seal(try JSONEncoder().encode(entries))
        try sealed.write(to: broken.root.appendingPathComponent("audit.enc"))
        let loaded = WorkspaceAuditLog(root: broken.root, vault: broken.vault)
        XCTAssertFalse(loaded.verifyChain())
    }

    func testExportJSONLShape() throws {
        let log = WorkspaceAuditLog(root: tempRoot("audit-export"), vault: Vault.ephemeralVault())
        log.append(actor: "a", action: "one", details: ["k": "v"], now: "t0")
        let jsonl = String(data: log.exportJSONL(), encoding: .utf8)!
        XCTAssertTrue(jsonl.contains("\"action\":\"one\""))
        XCTAssertTrue(jsonl.contains("\"prev_entry_hash\":\"GENESIS\""))
        XCTAssertTrue(jsonl.contains("\"entry_hash\":\""))
    }
}

final class BallProposalEngineTests: XCTestCase {

    /// 256x256 gray background with a dark disc centred at (180, 90) in
    /// TOP-LEFT origin coordinates (CGContext origin is bottom-left, so the
    /// disc is drawn at y = height - 90).
    private func syntheticBallImage() -> CGImage {
        let w = 256, h = 256
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: 0.6, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        context.setFillColor(gray: 0.05, alpha: 1)
        let topLeftY = CGFloat(h) - 90.0
        context.fillEllipse(in: CGRect(x: 180 - 6, y: topLeftY - 6, width: 12, height: 12))
        return context.makeImage()!
    }

    func testDetectsDarkDiscNearTruePosition() throws {
        let proposals = BallProposalEngine.proposals(cgImage: syntheticBallImage(),
                                                    maxProposals: 3)
        XCTAssertFalse(proposals.isEmpty, "detector must find the synthetic disc")
        let top = try XCTUnwrap(proposals.first)
        let truth = CoordinateEngine.PixelPoint(x: 180, y: 90)
        let distance = CoordinateEngine.euclideanDistancePx(
            CoordinateEngine.PixelPoint(x: top.xPx, y: top.yPx), truth)
        XCTAssertLessThanOrEqual(distance, 8.0,
                                 "top proposal must land within 8 px of the true centre")
        XCTAssertGreaterThanOrEqual(top.confidence, 0.05)
        XCTAssertLessThanOrEqual(top.confidence, 0.99)
        XCTAssertEqual(top.model, BallProposalEngine.modelId)
    }

    func testProposalsAreDistinctAndWithinBounds() throws {
        let proposals = BallProposalEngine.proposals(cgImage: syntheticBallImage(),
                                                    maxProposals: 3)
        for p in proposals {
            XCTAssertTrue(p.xPx >= 0 && p.xPx < 256)
            XCTAssertTrue(p.yPx >= 0 && p.yPx < 256)
        }
        let coords = proposals.map { "\($0.xPx),\($0.yPx)" }
        XCTAssertEqual(Set(coords).count, coords.count, "proposals must be distinct")
    }

    func testBlankImageYieldsNoCrash() throws {
        let context = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8,
                                bytesPerRow: 128, space: CGColorSpaceCreateDeviceGray(),
                                bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        let proposals = BallProposalEngine.proposals(cgImage: context.makeImage()!)
        XCTAssertLessThanOrEqual(proposals.count, 3)
    }
}
