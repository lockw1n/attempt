#if os(iOS)

    import CoreGraphics
    import Foundation
    import ImageIO
    import SwiftUI
    import Testing
    import UniformTypeIdentifiers

    @testable import DesignSystem

    // TR-1.12's harness, in-house rather than a dependency.
    //
    // WHY IN-HOUSE. `ImageRenderer` renders a SwiftUI view to a `CGImage` with no window, no scene and
    // no host app, which is the whole of what a component snapshot needs — measured before this file
    // was written: bytes are stable within a process and across separate `xcodebuild` runs, and the
    // renderer honours `colorScheme` and `dynamicTypeSize`. The comparison and the file layout below
    // are ~200 lines. A dependency would be the first one in the graph for that.
    //
    // WHY THIS TARGET RUNS ON THE SIMULATOR AND NOWHERE ELSE. Everything here is `#if os(iOS)`: the
    // references are iOS renderings, and `build-packages.sh --test` runs `swift test` on macOS, where
    // the same view resolves macOS font metrics and would fail against every reference. On macOS this
    // target compiles to nothing and reports no tests — which is a silent pass, so the CI job asserts a
    // minimum test count rather than trusting the exit status (scripts/snapshot-tests.sh).
    //
    // WHAT A SNAPSHOT HERE CANNOT SEE — two limits, both measured rather than assumed.
    //
    // A UIKit-backed view does not rasterise. `ImageRenderer` draws its unsupported-view placeholder
    // instead, which is what the loading state's `ProgressView` gets: see the comment on that test.
    // Everything else in this module is pure SwiftUI and renders as it ships.
    //
    // And it is a bitmap: it observes what renders, never what VoiceOver
    // reads. Hosting a view to walk its accessibility tree needs a `UIWindowScene`, and a SwiftPM test
    // bundle has none (measured: `connectedScenes` is empty, so `UIHostingController` renders no UIView
    // hierarchy at all). Modifier effects such as `.accessibilityHidden` therefore stay owed to an
    // audit with a real app behind it (`G-4.2`, T-1.82).

    /// Which appearance a reference is rendered in (`G-7.1`).
    nonisolated enum SnapshotAppearance: String, CaseIterable {
        case light
        case dark

        var colorScheme: ColorScheme {
            switch self {
            case .light: .light
            case .dark: .dark
            }
        }
    }

    /// Which Dynamic Type size a reference is rendered at.
    ///
    /// Two, not the whole scale: the default, and `NFR-1.10`'s own ceiling. Everything between them is
    /// the same layout at a different measure, and a reference per step would be a reference per step
    /// to regenerate.
    nonisolated enum SnapshotTypeSize: String, CaseIterable {
        case `default`
        case accessibility3

        var dynamicTypeSize: DynamicTypeSize {
            switch self {
            case .default: .large
            case .accessibility3: .accessibility3
            }
        }
    }

    /// A rendered bitmap, normalised to 8-bit sRGB RGBA with no row padding.
    ///
    /// Normalising is what makes a pixel comparison mean anything: `ImageRenderer` is free to hand back
    /// whatever `CGImage` layout it likes, and two images that differ only in byte order are not a
    /// design regression.
    nonisolated struct Bitmap {
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    /// Why a snapshot did not match.
    nonisolated enum SnapshotMismatch: Error, CustomStringConvertible {
        /// The rendering changed size — a layout regression, and no pixel comparison is possible.
        case size(reference: (Int, Int), rendered: (Int, Int))

        /// The rendering changed appearance, in `differing` of `total` pixels.
        case pixels(differing: Int, total: Int, maxChannelDelta: Int)

        var description: String {
            switch self {
            case .size(let reference, let rendered):
                "size changed: reference \(reference.0)×\(reference.1), rendered \(rendered.0)×\(rendered.1)"
            case .pixels(let differing, let total, let maxChannelDelta):
                "\(differing) of \(total) pixels differ (max channel delta \(maxChannelDelta))"
            }
        }
    }

    /// Rendering and comparison, with the reference files it reads and writes.
    nonisolated enum Snapshot {
        /// The width every reference is rendered at, in points.
        ///
        /// Fixed rather than taken from a device, so the destination simulator decides nothing: the
        /// only thing a device contributes is its OS version, which is what resolves the fonts. A
        /// component that claims the full width gets a defined measure to claim.
        static let width: CGFloat = 320

        /// The scale every reference is rendered at. 2, not 3: the same pixels on any runner.
        static let scale: CGFloat = 2

        /// Channel differences at or below this are anti-aliasing noise, not a change.
        ///
        /// **1, and a perceptual tolerance would be the wrong instrument here.** Measured against the
        /// mutation this task's own "done when" names: moving a card's radius one step down the scale
        /// (16 → 12) changes 540 pixels with a *maximum channel delta of 13*, because the surface and
        /// the background it is drawn over are 12 apart in the dark palette. A tolerance picked to
        /// absorb rendering differences would absorb that too, and the gate would be green through the
        /// exact regression it was built for.
        static let channelTolerance = 1

        /// Where the committed references live — beside this file, resolved from `#filePath` so the
        /// simulator process writes back into the source tree rather than into its own container.
        static let referenceDirectory = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "__Snapshots__")

        /// Where a failing run leaves what it rendered. Inside `.build/`, which `.gitignore` already
        /// covers — a failure must not turn up as an untracked file to be committed by accident.
        static let failureDirectory = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".build/snapshot-failures")

        /// Renders `view` in one configuration.
        ///
        /// The view is padded, given the fixed width and backed with the app's background token — a
        /// component draws no background of its own, and comparing transparent pixels would compare
        /// nothing.
        @MainActor
        static func render(
            _ view: some View,
            appearance: SnapshotAppearance,
            typeSize: SnapshotTypeSize
        ) throws -> Bitmap {
            let content =
                view
                .padding(Spacing.lg.points)
                .frame(width: width)
                .background(ColorToken.background)
                .environment(\.colorScheme, appearance.colorScheme)
                .dynamicTypeSize(typeSize.dynamicTypeSize)

            let renderer = ImageRenderer(content: content)
            renderer.scale = scale
            guard let image = renderer.cgImage else {
                throw SnapshotError.renderFailed
            }
            return try normalise(image)
        }

        /// Redraws `image` into a known 8-bit sRGB RGBA buffer.
        static func normalise(_ image: CGImage) throws -> Bitmap {
            let width = image.width
            let height = image.height
            guard
                let space = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                let base = context.data
            else {
                throw SnapshotError.renderFailed
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let buffer = UnsafeBufferPointer(
                start: base.assumingMemoryBound(to: UInt8.self),
                count: width * height * 4
            )
            return Bitmap(width: width, height: height, pixels: Array(buffer))
        }

        /// Compares two bitmaps, or `nil` when they match.
        static func compare(_ reference: Bitmap, _ rendered: Bitmap) -> SnapshotMismatch? {
            guard reference.width == rendered.width, reference.height == rendered.height else {
                return .size(
                    reference: (reference.width, reference.height),
                    rendered: (rendered.width, rendered.height)
                )
            }
            var differing = 0
            var maxDelta = 0
            for pixel in stride(from: 0, to: reference.pixels.count, by: 4) {
                var pixelDiffers = false
                for channel in 0..<4 {
                    let delta = abs(Int(reference.pixels[pixel + channel]) - Int(rendered.pixels[pixel + channel]))
                    maxDelta = max(maxDelta, delta)
                    if delta > channelTolerance { pixelDiffers = true }
                }
                if pixelDiffers { differing += 1 }
            }
            guard differing > 0 else { return nil }
            return .pixels(differing: differing, total: reference.width * reference.height, maxChannelDelta: maxDelta)
        }

        /// PNG bytes for a bitmap.
        static func pngData(_ bitmap: Bitmap) throws -> Data {
            guard
                let space = CGColorSpace(name: CGColorSpace.sRGB),
                let provider = CGDataProvider(data: Data(bitmap.pixels) as CFData),
                let image = CGImage(
                    width: bitmap.width,
                    height: bitmap.height,
                    bitsPerComponent: 8,
                    bitsPerPixel: 32,
                    bytesPerRow: bitmap.width * 4,
                    space: space,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider,
                    decode: nil,
                    shouldInterpolate: false,
                    intent: .defaultIntent
                )
            else {
                throw SnapshotError.encodeFailed
            }
            let output = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    output as CFMutableData,
                    UTType.png.identifier as CFString,
                    1,
                    nil
                )
            else {
                throw SnapshotError.encodeFailed
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw SnapshotError.encodeFailed }
            return output as Data
        }

        /// Reads a PNG back as a normalised bitmap.
        static func bitmap(fromPNG data: Data) throws -> Bitmap {
            guard
                let source = CGImageSourceCreateWithData(data as CFData, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                throw SnapshotError.decodeFailed
            }
            return try normalise(image)
        }

        /// A bitmap marking every differing pixel red and dimming the rest, for a failing run to leave
        /// behind. Comparing two images by eye is the part of a snapshot failure that is otherwise
        /// slow.
        static func differenceImage(_ reference: Bitmap, _ rendered: Bitmap) -> Bitmap? {
            guard reference.width == rendered.width, reference.height == rendered.height else { return nil }
            var pixels = rendered.pixels
            for pixel in stride(from: 0, to: pixels.count, by: 4) {
                let differs = (0..<4).contains {
                    abs(Int(reference.pixels[pixel + $0]) - Int(rendered.pixels[pixel + $0])) > channelTolerance
                }
                if differs {
                    pixels[pixel] = 255
                    pixels[pixel + 1] = 0
                    pixels[pixel + 2] = 0
                    pixels[pixel + 3] = 255
                } else {
                    for channel in 0..<3 { pixels[pixel + channel] /= 3 }
                }
            }
            return Bitmap(width: reference.width, height: reference.height, pixels: pixels)
        }

        /// What went wrong below the level of a mismatch.
        enum SnapshotError: Error {
            case renderFailed
            case encodeFailed
            case decodeFailed
        }
    }

    /// Renders `view` in all four configurations and compares each against its committed reference.
    ///
    /// A missing reference is **recorded and then failed**, never recorded and passed: a green CI run
    /// on a reference that has never been reviewed would make the gate self-approving. Regenerating is
    /// `scripts/snapshot-tests.sh --record`, which deletes the directory and runs the suite twice for
    /// exactly this reason.
    @MainActor
    func assertSnapshots(
        named name: String,
        sourceLocation: SourceLocation = #_sourceLocation,
        @ViewBuilder of view: () -> some View
    ) throws {
        let content = view()
        for appearance in SnapshotAppearance.allCases {
            for typeSize in SnapshotTypeSize.allCases {
                try assertSnapshot(
                    content,
                    named: "\(name).\(appearance.rawValue).\(typeSize.rawValue)",
                    appearance: appearance,
                    typeSize: typeSize,
                    sourceLocation: sourceLocation
                )
            }
        }
    }

    @MainActor
    private func assertSnapshot(
        _ view: some View,
        named name: String,
        appearance: SnapshotAppearance,
        typeSize: SnapshotTypeSize,
        sourceLocation: SourceLocation
    ) throws {
        let rendered = try Snapshot.render(view, appearance: appearance, typeSize: typeSize)
        let reference = Snapshot.referenceDirectory.appending(path: "\(name).png")

        guard let referenceData = try? Data(contentsOf: reference) else {
            try FileManager.default.createDirectory(
                at: Snapshot.referenceDirectory,
                withIntermediateDirectories: true
            )
            try Snapshot.pngData(rendered).write(to: reference)
            print("SNAPSHOT RECORDED \(name)")
            Issue.record(
                "no reference for \(name) — recorded one at \(reference.path). Review it, then re-run.",
                sourceLocation: sourceLocation
            )
            return
        }

        let referenceBitmap = try Snapshot.bitmap(fromPNG: referenceData)
        guard let mismatch = Snapshot.compare(referenceBitmap, rendered) else { return }

        try? FileManager.default.createDirectory(at: Snapshot.failureDirectory, withIntermediateDirectories: true)
        try? Snapshot.pngData(rendered).write(to: Snapshot.failureDirectory.appending(path: "\(name).rendered.png"))
        if let difference = Snapshot.differenceImage(referenceBitmap, rendered) {
            try? Snapshot.pngData(difference).write(to: Snapshot.failureDirectory.appending(path: "\(name).diff.png"))
        }
        let detail = "SNAPSHOT MISMATCH \(name): \(mismatch)"
        // Printed as well as recorded: xcodebuild's console output shows a recorded issue as the bare
        // words "Issue recorded", so the comment — which is the only thing saying *which* of the four
        // configurations moved and by how much — never reaches a CI log without this.
        print(detail)
        Issue.record(
            Comment(rawValue: detail + ". Rendered image and diff: \(Snapshot.failureDirectory.path)"),
            sourceLocation: sourceLocation
        )
    }

#endif
