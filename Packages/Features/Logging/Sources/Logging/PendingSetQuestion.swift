import DerivedValues
import SwiftUI

/// `FR-16.4.4`'s one question at Finish: the workout still holds sets nobody attempted, and it is
/// not ended until that is answered.
///
/// **A modifier rather than a block inside the screen**, so the same question can be asked wherever
/// a workout is ended — and so `ActiveSessionView.swift` stays under SwiftLint's file ceiling.
///
/// **An alert rather than a confirmation dialog, and three answers rather than two.** This is a
/// question with two real answers plus a way back, where a discard is one destructive action to
/// confirm.
private struct PendingSetQuestion: ViewModifier {
    /// How many sets the workout holds that nobody has attempted.
    let count: Int

    /// Whether the question is open.
    @Binding var isPresented: Bool

    /// What the lifter chose.
    let resolve: (SessionFinish.Resolution) -> Void

    /// The screen, with the question over it.
    ///
    /// - Parameter content: The screen.
    /// - Returns: Both.
    func body(content: Content) -> some View {
        content
            .alert(
                Text(LoggingStrings.sessionFinishPendingTitle(count)),
                isPresented: $isPresented
            ) {
                // An alert rather than a confirmation dialog, and three answers rather than two: this
                // is a question with two real answers plus a way back, where the discard above is one
                // destructive action to confirm. The two are never open together — Finish is only
                // reached with the workout still held.
                Button(role: .destructive) {
                    resolve(.remove)
                } label: {
                    Text(LoggingStrings.sessionFinishPendingRemove)
                }
                Button {
                    resolve(.keepAsFailed)
                } label: {
                    Text(LoggingStrings.sessionFinishPendingKeep)
                }
                Button(role: .cancel) {
                } label: {
                    Text(LoggingStrings.sessionFinishPendingCancel)
                }
            } message: {
                Text(LoggingStrings.sessionFinishPendingMessage)
            }
    }
}

extension View {
    /// Asks `FR-16.4.4`'s question over this view.
    ///
    /// - Parameters:
    ///   - count: How many sets nobody attempted.
    ///   - isPresented: Whether the question is open.
    ///   - resolve: What to do with them.
    /// - Returns: The view, with the question over it.
    func pendingSetQuestion(
        count: Int,
        isPresented: Binding<Bool>,
        resolve: @escaping (SessionFinish.Resolution) -> Void
    ) -> some View {
        modifier(
            PendingSetQuestion(count: count, isPresented: isPresented, resolve: resolve))
    }
}
