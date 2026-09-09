//
//  iShuttleWatchApp.swift
//  iShuttleWatch Watch App
//
//  Created by 闫润邦 on 2026/9/9.
//

import SwiftUI

@main
struct iShuttleWatch_Watch_AppApp: App {
    @StateObject private var store: WatchReservationStore
    @StateObject private var receiver: WatchConnectivityReceiver

    init() {
        let store = WatchReservationStore()
        _store = StateObject(wrappedValue: store)
        _receiver = StateObject(wrappedValue: WatchConnectivityReceiver(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(receiver)
        }
    }
}
