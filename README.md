# LyricEditor

LyricEditor is an iOS application built with SwiftUI that enables precise synchronization of lyrics to audio tracks. It supports AI-powered transcription, local forced alignment using an on-device Qwen model, manual timing adjustments, and seamless saving of synchronized lyrics back into the audio file's metadata.

## Features
- **Audio Import**: Drag-and-drop or file picker support for standard audio formats.
- **Metadata & Theming**: Auto-extracts title, artist, and artwork. Derives ambient UI colors from album art for dynamic theming.
- **AI Sync**: Server-side transcription via Qwen3AsrFlash followed by local forced alignment.
- **Manual Entry**: Paste lyrics and choose between AI alignment or manual timing.
- **Real-time Editing**: Scrub playback, nudge line timings, snap to playhead, delete with a 5-second undo window.
- **SYLT Export**: Saves word-level synchronized lyrics back into the original audio file's metadata.

## Architecture & Key Files
- `LyricEditor/ContentView.swift` — Core application logic, UI composition, state management (`AppState`), playback tracking, SYLT I/O, ambient color extraction, and all view components.
- `LyricEditor/LocalAligner.swift` — Swift wrapper around the `QwenAligner` C FFI. Handles model loading, audio decoding (16 kHz mono f32), and forced alignment.
- `LyricEditor/LyricEditorApp.swift` — App entry point. Parses launch arguments for API credentials and configures the `LyricsAPI`.
- `Package.swift` — Swift Package Manager manifest defining dependencies and build configuration. Note: The SPM target excludes the app entry point, indicating this package is consumed by a host Xcode project.

## Installation & Setup
1. **Clone the repository** and open the host Xcode project (or use SPM to resolve dependencies).
2. **Resolve dependencies**:
   ```bash
   swift package resolve
   ```
3. **API Credentials**: The app requires authentication for the AI transcription service. Credentials are passed at launch via command-line arguments:
   ```bash
   -u <username> -p <password>
   ```
   Configure these in your Xcode scheme under `Run > Arguments > Arguments Passed On Launch`, or modify `LyricEditorApp.swift` for development builds.
4. **Framework Integration**: Ensure the `QwenAligner` xcframework is linked in your Xcode project. It is not managed by SPM in this repository.

## Building & Running
- **Platform**: iOS 17+
- **Swift Version**: 6.0
- Open the project in Xcode 15+ and build/run. The app targets the iOS simulator or physical device.
- If building via SPM alone, note that `LyricEditorApp.swift` is excluded from the library target and must be included in a host app target.

## Usage Guide
1. **Import a Track**: Tap the waveform button or drop an audio file. The app extracts metadata, artwork, and ambient colors.
2. **Sync Lyrics**:
   - Tap **Sync** to run AI transcription + local alignment.
   - Tap **I have the lyrics** to paste text and choose between AI alignment or manual timing.
3. **Edit & Refine**:
   - Play/pause and scrub the timeline.
   - Tap a line to play it; long-press to edit text.
   - Use the **Nudge** buttons or **Snap to Playhead** to adjust timing.
   - Delete lines with a built-in 5-second undo window.
4. **Save**: Tap **Save** to write the synchronized lyrics back into the audio file's SYLT metadata. The app handles iCloud/external storage safely via `NSFileCoordinator`.

## Technical Details & Conventions
- **State Management**: Uses the `@Observable` macro (`AppState`) with `@ObservationIgnored` for non-UI tasks (players, tasks, temporary state). All state mutations occur on `@MainActor`.
- **Playback Tracking**: A dedicated `Task` polls `AVAudioPlayer.currentTime` every 50ms. Falls back to a synthetic clock if playback fails. Handles audio session interruptions automatically.
- **SYLT Format**: Hybrid structure with one entry per word, separated by `\n` markers for line breaks. Read/written via `swift-audio-marker`.
- **Model Loading**: `LocalAligner` infers the model directory by locating `vocab.json` in the app bundle. The model is lazily loaded on a dedicated serial queue (`engineQueue`) to avoid blocking the main thread.
- **File I/O Safety**: Direct writes to iCloud/external URLs are blocked by sandbox restrictions. The app copies files to a temporary directory, modifies them, then uses `NSFileCoordinator` to atomically replace the original.
- **Ambient Theming**: Album artwork is processed via CoreImage (`CIAreaAverage`) to extract three dominant colors, adjusted for luminance, and applied as radial gradients in the UI.
- **Lyric Data Model**: `LyricItem` groups `Word` objects. Setting `time` shifts all words in the line by the same delta. Setting `text` collapses the line to a single word at the previous start time.

## Dependencies
- `swiftapi` (GitHub: `femimarket/swiftapi`) — API client for Qwen3AsrFlash transcription.
- `swift-audio-marker` (GitHub: `atelier-socle/swift-audio-marker`) — SYLT metadata reading/writing.
- `QwenAligner` — C FFI framework for on-device forced alignment (requires manual framework integration).
- Apple Frameworks: `SwiftUI`, `AVFoundation`, `CoreImage`, `UniformTypeIdentifiers`, `AudioMarker`, `Api`.