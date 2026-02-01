//
//  MoDytApp.swift
//  MoDyt
//
//  Created by Thibault Wittemberg on 30/01/2026.
//

import SwiftUI

@main
struct MoDytApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store)
        }
    }
}
