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
        // TODO: replace with real auth flow (Sign in with Apple → bearer token).
        // Short-lived Apple ID JWT for dev wiring only. Do not commit to source control.
        LyricsAPI.configure(
            bearerToken: "eyJraWQiOiIxRTZWaW9JYU5JIiwiYWxnIjoiUlMyNTYifQ.eyJpc3MiOiJodHRwczovL2FwcGxlaWQuYXBwbGUuY29tIiwiYXVkIjoibWFya2V0LmZlbWkiLCJleHAiOjE3ODA4NTExMDQsImlhdCI6MTc4MDc2NDcwNCwic3ViIjoiMDAwNTM5LjFjMGFhZmZlY2NjNTQwNjI5ODc1OTliMDEwM2U2ZWNkLjExMTEiLCJjX2hhc2giOiJHNWxISE9xYWIxbzVGVXVxQjBzeEtRIiwiZW1haWwiOiJidXNpbmVzc0BmZW1pLm1hcmtldCIsImVtYWlsX3ZlcmlmaWVkIjp0cnVlLCJhdXRoX3RpbWUiOjE3ODA3NjQ3MDQsIm5vbmNlX3N1cHBvcnRlZCI6dHJ1ZX0.ZJ1FePgx1Qii_9QZFLj8pjRKc3OyL4ybuxgdVyTkR8Bj3W3qotB0Dl6UOWe800WIgGowg__RCdxm-c8HjUU8E1T85BNoNiwoG8cJL9HffTfyu9VFoJw6pwxw_3awIeyL8fcisfl6sxlR_MGpdQeuJGOI67fUOcEBU5uPvMA8wcNQYr5c2pEurFxjNBATVQC3Z0849tShEa1_W0eif4MGlJ_j3oBnYmrY7NIrs2PUvRhdyUQ4neqS1OUUad8rGFv3yQza4-GJ8LT4yGWkUCGTrNz__GoFvkdDmI0TtRLGNpZQYUbpzWBE_nqhPC5wAVVoF1qCmK8npfiODbvehFGXZw",
            userId: "000539.1c0aaffeccc54062987599b0103e6ecd.1111"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
