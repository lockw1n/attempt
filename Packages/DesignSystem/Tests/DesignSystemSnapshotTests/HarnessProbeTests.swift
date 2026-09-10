#if os(iOS)

    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import DesignSystem

    // The two-directional check every gate in this project gets: the suite above proves the components
    // render as they did, and this file proves the comparison can actually fail. A snapshot gate whose
    // comparison is too tolerant is green for the same reason a correct one is, which is the failure
    // mode that looks like success.

    @MainActor
    @Suite("Snapshot harness")
    struct SnapshotHarnessTests {
        /// The positive control. Without it, a comparison that reported *everything* as different would
        /// pass every test below.
        @Test(arguments: [(SnapshotAppearance.light, SnapshotTypeSize.default), (.dark, .accessibility3)])
        func identicalRendersMatch(appearance: SnapshotAppearance, typeSize: SnapshotTypeSize) throws {
            let card = Card { Text(verbatim: "Card content") }
            let first = try Snapshot.render(card, appearance: appearance, typeSize: typeSize)
            let second = try Snapshot.render(card, appearance: appearance, typeSize: typeSize)
            #expect(!first.pixels.isEmpty)
            #expect(Snapshot.compare(first, second) == nil)
        }

        /// The control on the appearance axis, and the one the other two do not imply. `G-7.1` is half
        /// this suite's coverage, and it rests entirely on `.environment(\.colorScheme,)` still taking
        /// effect — a mechanism with a silent-failure twin, since `.preferredColorScheme` reaches
        /// `ImageRenderer` not at all. If it ever stopped biting, `--record` would write every light
        /// reference and its dark pair identical and all of this would stay green.
        @Test func appearancesRenderDifferently() throws {
            let card = Card { Text(verbatim: "Card content") }
            let light = try Snapshot.render(card, appearance: .light, typeSize: .default)
            let dark = try Snapshot.render(card, appearance: .dark, typeSize: .default)
            let mismatch = try #require(Snapshot.compare(light, dark))
            guard case .pixels(let differing, let total, _) = mismatch else {
                Issue.record("expected a pixel difference, got \(mismatch)")
                return
            }
            // Not "some pixels": the card's surface and the background behind it both inverted, so a
            // handful of differing pixels would mean the appearance had stopped reaching most of the
            // rendering rather than that it had been applied.
            #expect(differing > total / 2)
        }

        /// A `ProgressView` is animated, and an animation frame chosen at render time would make the
        /// loading reference flap. It does not — asserted rather than assumed, because the failure
        /// would be an intermittent red CI job rather than an obvious one.
        @Test func animatedContentRendersDeterministically() throws {
            let loading = LoadingStateView(message: Text(verbatim: "Reading from Health"))
            let first = try Snapshot.render(loading, appearance: .dark, typeSize: .default)
            let second = try Snapshot.render(loading, appearance: .dark, typeSize: .default)
            #expect(Snapshot.compare(first, second) == nil)
        }

        /// A PNG round trip must not itself be a difference, or every reference would fail the run
        /// after the one that wrote it.
        @Test func pngRoundTripPreservesPixels() throws {
            let rendered = try Snapshot.render(
                MetricTile(label: Text(verbatim: "Squat e1RM"), value: Text(verbatim: "142.5 kg")),
                appearance: .light,
                typeSize: .default
            )
            let decoded = try Snapshot.bitmap(fromPNG: Snapshot.pngData(rendered))
            #expect(Snapshot.compare(rendered, decoded) == nil)
        }

        /// The wrong-corner-radius mutation named in this task's own "done when", as a rendered
        /// difference rather than a described one. The mutant takes ``CornerRadius/control`` where
        /// ``CornerRadius/card`` belongs — one step down the same scale, which is the plausible
        /// mistake rather than an exaggerated one.
        @Test func wrongCornerRadiusFailsTheComparison() throws {
            let correct = try Snapshot.render(
                Card { Text(verbatim: "Card content") },
                appearance: .dark,
                typeSize: .default
            )
            let mutated = try Snapshot.render(
                MutatedCard(cornerRadius: .control, surface: .surface),
                appearance: .dark,
                typeSize: .default
            )
            let mismatch = try #require(Snapshot.compare(correct, mutated))
            guard case .pixels(let differing, _, _) = mismatch else {
                Issue.record("expected a pixel difference, got \(mismatch)")
                return
            }
            #expect(differing > 0)
        }

        /// The wrong-colour mutation, one step along the same palette — surface against surfaceRaised
        /// is the elevation mistake a reviewer is least likely to catch by eye.
        @Test func wrongSurfaceColourFailsTheComparison() throws {
            let correct = try Snapshot.render(
                Card { Text(verbatim: "Card content") },
                appearance: .dark,
                typeSize: .default
            )
            let mutated = try Snapshot.render(
                MutatedCard(cornerRadius: .card, surface: .surfaceRaised),
                appearance: .dark,
                typeSize: .default
            )
            #expect(Snapshot.compare(correct, mutated) != nil)
        }

        /// A layout regression that changes the rendering's *size* is reported as one, not as a pixel
        /// count against an image of a different shape.
        @Test func sizeChangeIsReportedAsSizeChange() throws {
            let small = try Snapshot.render(
                Card { Text(verbatim: "Card content") },
                appearance: .dark,
                typeSize: .default
            )
            let large = try Snapshot.render(
                Card { Text(verbatim: "Card content") },
                appearance: .dark,
                typeSize: .accessibility3
            )
            let mismatch = try #require(Snapshot.compare(small, large))
            guard case .size = mismatch else {
                Issue.record("expected a size mismatch, got \(mismatch)")
                return
            }
        }

        // TR-1.12's blank guard, in both directions and at both of the points it sits.
        //
        // THE DEFECT IT CLOSES IS THE ONE THIS SUITE'S OTHER PROBES CANNOT SEE. Every test above
        // asks whether the comparison can fail. None can ask whether the two things compared say
        // anything, and `compare` tests dimensions before pixels — so a reference recorded blank
        // agrees with a blank render on both counts and matches forever. T-15.06 cleared the two
        // blanks that were on `dev` and left the class untouched; this is the class.
        //
        // NO TOLERANCE AND NO OPT-OUT, because T-1.92 measured that none is needed: 0 of the 992
        // references in the tree had four or fewer distinct pixel values. See ``Bitmap/isUniform``.

        /// The predicate's negative direction. Without it, an `isUniform` that answered `true` for
        /// everything would satisfy every assertion below.
        @Test func realContentIsNotUniform() throws {
            let card = try Snapshot.render(
                Card { Text(verbatim: "Card content") }, appearance: .dark, typeSize: .default)
            #expect(!card.isUniform)
        }

        /// The positive direction, on the case the design question actually asked about: an empty
        /// state over a flat background, which is the one legitimate view that could render this way.
        @Test func anEmptyRenderIsUniform() throws {
            let blank = try Snapshot.render(EmptyView(), appearance: .dark, typeSize: .default)
            #expect(blank.isUniform)
            #expect(!blank.pixels.isEmpty)
        }

        /// **The guard fires rather than recording**, which is the half that stops a blank entering
        /// the tree at all. `withKnownIssue` is the instrument: it fails unless an issue is raised,
        /// so this test passes only while the guard works.
        ///
        /// **`matching:` is what makes that true rather than nearly true.** A bare `withKnownIssue`
        /// is satisfied by *any* issue, and this run raises others when the guard is off — one per
        /// reference recorded. Naming the diagnostic is the difference between asserting that
        /// something went wrong and asserting that the guard is what noticed.
        @Test func recordingIsRefusedForABlankRender() throws {
            let suite = try ScratchSuite()
            try withKnownIssue {
                try assertSnapshots(named: "blank", testFile: suite.testFile) { EmptyView() }
            } matching: {
                $0.isBlankRenderRefusal
            }
            // And nothing was written — the whole point, since a file recorded here is a file that
            // matches itself forever.
            #expect(
                !FileManager.default.fileExists(
                    atPath: suite.reference("blank.dark.default").path))
        }

        /// **The guard fires on a blank already committed**, which is the half that sweeps what is
        /// there. Distinct from the probe above: that one never reaches the comparison, and a fix
        /// applied only at recording time would leave every existing blank matching.
        ///
        /// **This probe's first version could not fail, and the way it could not is worth keeping.**
        /// It rendered one blank at `.dark`/`.default` and wrote that bitmap into all four
        /// configuration slots — so the two `accessibility3` references disagreed on *size* with
        /// what was rendered against them, `compare` raised two issues, and `withKnownIssue` was
        /// satisfied by the size mismatch. With ``Bitmap/isUniform`` hard-wired to `false` — the
        /// guard removed entirely — it still passed. Both halves of the repair matter: each
        /// reference is now rendered at its own configuration, so nothing but the guard can raise
        /// anything, and `matching:` names the diagnostic so a future accident cannot borrow
        /// another issue the way this one did.
        @Test func aBlankReferenceIsRejectedRatherThanMatched() throws {
            let suite = try ScratchSuite()
            try FileManager.default.createDirectory(
                at: suite.snapshots, withIntermediateDirectories: true)
            // A blank reference for all four configurations, each rendered AT ITS OWN — which is
            // what the harness would have written, and what makes the comparison below agree on
            // both axes.
            for appearance in SnapshotAppearance.allCases {
                for typeSize in SnapshotTypeSize.allCases {
                    let blank = try Snapshot.render(
                        EmptyView(), appearance: appearance, typeSize: typeSize)
                    #expect(blank.isUniform)
                    // Identical dimensions, identical pixels: `compare` returns nil for this
                    // configuration, so the run is green without the guard. Asserted four times
                    // over, because one configuration agreeing says nothing about the other three.
                    #expect(Snapshot.compare(blank, blank) == nil)
                    try Snapshot.pngData(blank).write(
                        to: suite.reference("blank.\(appearance.rawValue).\(typeSize.rawValue)"))
                }
            }
            try withKnownIssue {
                try assertSnapshots(named: "blank", testFile: suite.testFile) { EmptyView() }
            } matching: {
                $0.isBlankReferenceRejection
            }
        }

        /// A scratch directory shaped like a suite's, so `assertSnapshots` resolves its references
        /// there instead of into this package's committed tree.
        ///
        /// **`testFile:` is passed deliberately, which is the one thing the harness's own doc
        /// comment warns against** — pointing a run at another directory's references is exactly
        /// what these two probes need, and it is the only way to exercise the guard without
        /// committing a blank to prove a blank is refused.
        private struct ScratchSuite {
            /// The notional test file, whose directory resolves the references beside it.
            let testFile: String

            /// Where `assertSnapshots` will look — the three stripped components are what
            /// `Snapshot.failureDirectory(forTestFile:)` expects, so a failing probe leaves its
            /// artefacts here too rather than in the package.
            let snapshots: URL

            init() throws {
                let root = URL(filePath: NSTemporaryDirectory())
                    .appending(path: "blank-guard-\(UUID().uuidString)")
                    .appending(path: "Tests/Suite")
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                testFile = root.appending(path: "Probe.swift").path
                snapshots = root.appending(path: "__Snapshots__")
            }

            /// One reference file by name.
            func reference(_ name: String) -> URL { snapshots.appending(path: "\(name).png") }
        }

        /// A replica of ``Card``'s body with its two token choices opened up, so a mutation can be
        /// rendered without editing the component.
        ///
        /// **Both knobs are tokens rather than literals, because the `G-7.7` rules reach this file
        /// too** — `.swiftlint.yml` says why they reach further than they appear to. So a mutation
        /// here has to be a *wrong token*, which is the better probe anyway: taking the control radius
        /// where the card radius belongs is the mistake someone would actually make.
        private struct MutatedCard: View {
            let cornerRadius: CornerRadius
            let surface: ColorToken

            var body: some View {
                Text(verbatim: "Card content")
                    .padding(Spacing.lg.points)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(surface, in: .rect(cornerRadius: cornerRadius.points))
            }
        }
    }

    // G-4.5 / G-7.3, and T-1.03's one unticked "done when": the delta cue was argued to survive without
    // colour and unit-tested on the constants behind it, which is reading the code by another name.
    // Here it is measured on the pixels.
    //
    // The instrument is an ink mask — every pixel that differs from the background, with hue discarded
    // entirely. That is a stronger reading than a colourblindness filter: a filter still leaves two
    // tints that might map to different greys, where a mask leaves nothing but shape. If the glyph and
    // the sign character were ever dropped and the tint left to carry the meaning, these masks would
    // become identical and this suite would go red.
    @MainActor
    @Suite("Delta cues without colour")
    struct DeltaColourIndependenceTests {
        @Test(
            arguments: [
                (DeltaDirection.increase, DeltaDirection.decrease),
                (.increase, .unchanged),
                (.decrease, .unchanged),
            ],
            SnapshotTypeSize.allCases
        )
        func directionsAreDistinguishableWithColourDiscarded(
            _ pair: (DeltaDirection, DeltaDirection),
            _ typeSize: SnapshotTypeSize
        ) throws {
            let one = try inkMask(for: pair.0, typeSize: typeSize)
            let other = try inkMask(for: pair.1, typeSize: typeSize)
            #expect(one.count == other.count)
            let differing = zip(one, other).count { $0.0 != $0.1 }
            // The floor is not separating signal from noise — two identical shapes produce an identical
            // mask, which the control below asserts — it is separating a *cue* from a cosmetic wobble.
            // 100 pixels at scale 2 is 25 point², about a 5×5pt mark. Measured at the default size:
            // increase/decrease 174, increase/unchanged 972, decrease/unchanged 956. The first pair is
            // the tight one, and it is the pair G-4.5 is actually about: arrow.up and arrow.down are
            // mirror images and + and − share their horizontal bar, so what separates them under a
            // red/green filter is 174 pixels of stroke and nothing else. At accessibility3 every pair
            // clears the floor by an order of magnitude.
            #expect(differing > 100, "\(pair.0) and \(pair.1) differ in only \(differing) ink pixels")
        }

        /// The control for the assertion above: the same direction twice has an identical mask, so a
        /// difference between two directions is the cue and not the instrument's own noise.
        @Test func theMaskIsStableForOneDirection() throws {
            let first = try inkMask(for: .increase, typeSize: .default)
            let second = try inkMask(for: .increase, typeSize: .default)
            // Counted rather than compared: `#expect(first == second)` prints both masks, and a mask
            // is one `Bool` per pixel.
            #expect(first.count == second.count)
            #expect(zip(first, second).count { $0.0 != $0.1 } == 0)
        }

        /// Every direction actually draws something. A mask that was empty for all three would satisfy
        /// nothing above and everything below it.
        @Test(arguments: DeltaDirection.allCases)
        func eachDirectionDrawsInk(_ direction: DeltaDirection) throws {
            let ink = try inkMask(for: direction, typeSize: .default)
            #expect(ink.count { $0 } > 200)
        }

        /// Which pixels are drawn on, with colour discarded: anything that differs from the background
        /// the renderer laid down, whatever hue either of them is.
        private func inkMask(for direction: DeltaDirection, typeSize: SnapshotTypeSize) throws -> [Bool] {
            let bitmap = try Snapshot.render(
                DeltaIndicator(direction, value: "2.5 kg").frame(maxWidth: .infinity, alignment: .leading),
                appearance: .dark,
                typeSize: typeSize
            )
            let background = Array(bitmap.pixels[0..<4])
            return stride(from: 0, to: bitmap.pixels.count, by: 4).map { pixel in
                (0..<3).contains { abs(Int(bitmap.pixels[pixel + $0]) - Int(background[$0])) > 8 }
            }
        }
    }

    // T-1.09 left three accessibility-rendering mutations that no unit test could observe. One of them
    // — whether the scaffold's action button renders at all when a handler is supplied — is a question
    // about pixels, so it is answered here.
    //
    // The other two are not, and this harness cannot close them: `.accessibilityHidden(true)` on the
    // glyph and `.accessibilityElement(children: .combine)` on the copy are what VoiceOver reads, and
    // reading it needs a hosted view in a window. A SwiftPM test bundle has no `UIWindowScene`
    // (measured), so `UIHostingController` renders no UIView hierarchy and vends no accessibility
    // elements. They stay owed to an audit with a real app behind it (`G-4.2`).
    @MainActor
    @Suite("State action rendering")
    struct StateActionRenderingTests {
        @Test(arguments: SnapshotAppearance.allCases)
        func retryHandlerRendersAButton(_ appearance: SnapshotAppearance) throws {
            let withRetry = try Snapshot.render(
                ErrorStateView(message: Text(verbatim: "That could not be saved."), retryEmphasis: .primary, retry: {}),
                appearance: appearance,
                typeSize: .default
            )
            let withoutRetry = try Snapshot.render(
                ErrorStateView(message: Text(verbatim: "That could not be saved.")),
                appearance: appearance,
                typeSize: .default
            )
            #expect(withRetry.width == withoutRetry.width)
            // Taller by at least a touch target: G-4.3's minimum extent is what the button claims, so a
            // smaller difference would mean something else appeared.
            let grew = withRetry.height - withoutRetry.height
            #expect(Double(grew) >= TouchTarget.standard.points * Snapshot.scale)
        }

        /// The offline state offers the same retry, and it is the one whose copy the module owns
        /// outright — so a caller passing no handler must still get no button.
        @Test func offlineWithoutRetryRendersNoButton() throws {
            let withRetry = try Snapshot.render(
                OfflineStateView(retryEmphasis: .primary, retry: {}),
                appearance: .dark,
                typeSize: .default)
            let withoutRetry = try Snapshot.render(OfflineStateView(), appearance: .dark, typeSize: .default)
            #expect(withRetry.width == withoutRetry.width)
            // The same measure its sibling above uses, and for the same reason: any growth at all
            // would also be satisfied by a stray point of padding.
            let grew = withRetry.height - withoutRetry.height
            #expect(Double(grew) >= TouchTarget.standard.points * Snapshot.scale)
        }
    }

    /// Which blank diagnostic an issue is, if either (`TR-1.12`).
    ///
    /// **The instrument `withKnownIssue`'s `matching:` closure needs, and it exists because the
    /// absence of one cost a probe its ability to fail.** A bare `withKnownIssue` accepts any issue
    /// at all, so a probe that raises a second issue by accident is green on that one instead of on
    /// the failure it was written to prove — which is exactly what happened to
    /// `aBlankReferenceIsRejectedRatherThanMatched`.
    ///
    /// Two properties rather than one predicate taking a string, so the guard's two ends cannot be
    /// asserted with each other's marker — the render one is defined as the diagnostic that is *not*
    /// the reference one, which is the only way to tell them apart by prefix.
    ///
    /// **Neither marker names the reference.** The harness's `name` at the point it raises these is
    /// the per-configuration one — `blank.dark.default`, not `blank` — and a marker written against
    /// the name a probe passes to `assertSnapshots` matches nothing. That mistake makes a probe fail
    /// loudly rather than pass quietly, which is the right way round for a matcher.
    extension Issue {
        /// Whether this is ``blankRenderDiagnostic(named:bitmap:)`` — recording refused.
        fileprivate nonisolated var isBlankRenderRefusal: Bool {
            carries("SNAPSHOT BLANK ") && !isBlankReferenceRejection
        }

        /// Whether this is ``blankReferenceDiagnostic(named:at:)`` — a committed blank rejected.
        fileprivate nonisolated var isBlankReferenceRejection: Bool {
            carries("SNAPSHOT BLANK REFERENCE ")
        }

        /// Whether any of this issue's comments contains `marker`.
        private nonisolated func carries(_ marker: String) -> Bool {
            comments.contains { $0.rawValue.contains(marker) }
        }
    }

#endif
