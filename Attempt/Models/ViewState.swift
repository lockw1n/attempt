//
//  ViewState.swift
//  Attempt
//
//  Created by lockw1n on 01.08.2026.
//

import Foundation

/// The lifecycle of a single piece of loadable content.
///
/// Modelling this as one value (rather than separate `isLoading` / `value` /
/// `error` properties) makes impossible states unrepresentable — a view can
/// never be loading *and* failed at the same time.
enum ViewState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(AppError)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var error: AppError? {
        if case .failed(let error) = self { return error }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

extension ViewState: Equatable where Value: Equatable {}
