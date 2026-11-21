// VideoFrameExtractor.swift
// Private Judges Workspace - authorized video-frame analysis.
//
// Frames come from a user-selected video (PhotosPicker / file importer).
// A captured frame is re-encoded to JPEG and becomes an ordinary image entry:
// its identity is the SHA-256 of the frame bytes, and every coordinate on it
// flows through the same coordinate engine as photo entries. The source video
// id and timestamp are recorded in the entry metadata.

import Foundation
import AVFoundation
import CoreGraphics
import UIKit
import CoreTransferable
import UniformTypeIdentifiers

struct LoadedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("pjw-\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return LoadedVideo(url: copy)
        }
    }
}

enum VideoFrameExtractor {

    struct VideoInfo {
        let durationSeconds: Double
        let sourceVideoId: String
    }

    static func videoInfo(url: URL) async throws -> VideoInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let bytes = try Data(contentsOf: url)
        return VideoInfo(durationSeconds: duration.seconds.isFinite ? duration.seconds : 0,
                         sourceVideoId: CoordinateEngine.imageSHA256(bytes))
    }

    /// Extract a single frame; exact when available, nearest otherwise.
    static func extractFrame(url: URL, atSeconds seconds: Double) async throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        let result = try await generator.image(at: time)
        return result.image
    }

    /// Frame -> JPEG bytes (identity base for the image entry).
    static func frameData(from cgImage: CGImage, quality: CGFloat = 0.95) -> Data? {
        UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
    }
}
