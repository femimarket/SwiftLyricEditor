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
        // Bearer token comes from launch argument `-idtoken <jwt>` (Xcode scheme).
        // Without one, fall back to the device's identifierForVendor so the server
        // still has a stable identity to attach the request to.
        let token = Self.argValue(for: "-idtoken") ?? UIDevice.current.identifierForVendor?.uuidString
        LyricsAPI.configure(bearerToken: token)
    }

    private static func argValue(for flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        let v = args[i + 1]
        return v.isEmpty ? nil : v
    }

    /// Decode JWT `sub` claim (no signature verification — server still validates).
    private static func subClaim(of jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        // Pad base64url to base64.
        payload = payload.replacingOccurrences(of: "-", with: "+")
                         .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload.append("=") }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String
        else { return nil }
        return sub
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
