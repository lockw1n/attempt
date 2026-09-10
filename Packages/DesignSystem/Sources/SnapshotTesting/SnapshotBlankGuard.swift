#if os(iOS)

    import Foundation

    // TR-1.12's blank guard: the one state the comparison in SnapshotHarness.swift cannot detect by
    // comparing.
    //
    // WHY IT IS NOT A TOLERANCE ON THE COMPARISON. `Snapshot.compare` tests dimensions and then
    // pixels, and a reference recorded blank agrees with a blank render on both — so it matches
    // forever, and no amount of tuning the comparison changes that. The claim has to be made about
    // one image on its own, which is what `Bitmap.isUniform` is.
    //
    // THE TWO ROUTES IN ARE UNRELATED, which is why "keep the fixture short" never covered this.
    // `ImageRenderer` hands back nothing past roughly 7k pixels of height; and separately, a
    // `ScrollView` rasterises its UIKit-backed placeholder whatever its size (T-16.06). A fixture
    // looks correct in both cases, and the only tell anybody ever found by eye was a re-recorded
    // reference that shrank while getting taller.
    //
    // A file of its own rather than more of SnapshotHarness.swift, which had reached SwiftLint's
    // length ceiling. It is also the honest split: everything here is about whether an image says
    // anything, and nothing here is about whether two images agree.

    extension Bitmap {
        /// Whether every pixel is the same colour — the shape a blank rendering has (`TR-1.12`).
        ///
        /// **Exact, with no tolerance and no opt-out.** A threshold here would be a number nobody
        /// could justify later, and T-1.92 measured that none is needed: of the 992 references in
        /// the tree, **zero** had four or fewer distinct pixel values. Real content is anti-aliased
        /// text over a token background and is nowhere near this predicate; a blank is exactly one
        /// value. The gap between them is the whole range, so the cheapest rule is also the honest
        /// one — including for a genuinely empty state on a flat ground, which was the case the
        /// measurement was taken to settle.
        ///
        /// An empty bitmap is **not** uniform. Nothing renders to zero pixels, and answering `true`
        /// would make the guard reject a case it has no evidence about.
        public var isUniform: Bool {
            guard pixels.count >= 8 else { return false }
            return !stride(from: 4, to: pixels.count, by: 4).contains { pixel in
                (0..<4).contains { pixels[$0] != pixels[pixel + $0] }
            }
        }
    }

    /// Why a rendering was refused, and the two things that cause it (`TR-1.12`).
    ///
    /// **The advice is here rather than in a document, because this is where the question gets
    /// asked.** Both routes into a blank are invisible from the fixture, so a reader who has just
    /// hit one has no way to tell which of the two they are in.
    ///
    /// - Parameters:
    ///   - name: The reference that was not written.
    ///   - bitmap: What rendered.
    /// - Returns: The diagnostic.
    func blankRenderDiagnostic(named name: String, bitmap: Bitmap) -> String {
        """
        SNAPSHOT BLANK \(name): rendered \(bitmap.width)×\(bitmap.height) in a single colour, so no \
        reference was written. `ImageRenderer` produces this in two unrelated ways and the fixture \
        looks correct in both. (1) It hands back nothing past roughly 7k pixels of height — when a \
        render crosses that, SPLIT THE REFERENCE rather than shrinking the fixture, which costs no \
        claim. (2) A `ScrollView` rasterises its UIKit-backed placeholder, which has nothing to do \
        with size — SNAPSHOT THE CONTENT VIEW, NEVER THE SCROLLER: put the scroller in a one-line \
        wrapper and give the stack or grid inside it a type of its own, which is what \
        `SchemeTableGrid` and `SchemeGrid` are for.
        """
    }

    /// Why a committed reference was rejected (`TR-1.12`).
    ///
    /// Separate from ``blankRenderDiagnostic(named:bitmap:)`` because the remedy differs: nothing
    /// here is about what to render, only about a file that should never have been committed.
    ///
    /// - Parameters:
    ///   - name: The reference.
    ///   - url: Where it is.
    /// - Returns: The diagnostic.
    func blankReferenceDiagnostic(named name: String, at url: URL) -> String {
        """
        SNAPSHOT BLANK REFERENCE \(name): the committed reference at \(url.path) is a single \
        colour, so it pictures nothing and matches a blank rendering forever — the comparison tests \
        dimensions and then pixels, and a blank agrees with a blank on both. Delete it, re-record \
        the suite, and check what comes back: `shasum` the light and dark pair, where identical \
        hashes mean neither has content.
        """
    }

#endif
