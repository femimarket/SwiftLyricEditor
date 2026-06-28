//
//  LyricEditorApp.swift
//  LyricEditor
//
//  Created by u on 05/06/2026.
//

import SwiftUI

@main
struct LyricEditorApp: App {
    init() {
        let args = ProcessInfo.processInfo.arguments
        let user = args[args.firstIndex(of: "-u")! + 1]
        let password = args[args.firstIndex(of: "-p")! + 1]
        LyricsAPI.configure(user: user, password: password)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
