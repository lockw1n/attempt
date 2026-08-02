//
//  HomeViewModel.swift
//  Attempt
//
//  Created by lockw1n on 01.08.2026.
//

import Foundation
import Observation

/// Example of the view-model shape the rest of the app should follow:
/// `@Observable`, `@MainActor`, one `ViewState` per loadable thing, and
/// dependencies injected through the initialiser so tests can stub them.
@MainActor
@Observable
final class HomeViewModel {
    private(set) var state: ViewState<String> = .idle

    private let greeting: String

    init(greeting: String = "Hello, world") {
        self.greeting = greeting
    }

    func load() async {
        state = .loading
        // Replace with a real call once there is something to fetch:
        //   state = .loaded(try await apiClient.send(.item(id: id), as: Item.self))
        state = .loaded(greeting)
    }
}
