# LyricEditor

## Overview
LyricEditor is an iOS application for importing audio tracks, synchronizing lyrics, and editing timed lyric lines. It supports cloud-assisted transcription, on-device forced alignment using a quantized Qwen model, and manual timing adjustments. Synchronized lyrics are saved directly into the audio file using the SYLT (Synchronized Lyrics) metadata format.

## Key Features
- **Multi-Mode Sync**: Cloud transcription (`Qwen3AsrFlash`), on-device forced alignment (`QwenAligner`), or manual entry
- **Real-Time Playback & Scrubbing**: 50ms polling loop with safe seek suppression and interruption handling
- **Line-by-Line Editing**: Tap to play, long-press to edit, nudge/snap timing controls, and undo/restore
- **Ambient Theming**: Dynamic background gradients extracted from album artwork using CoreImage
- **SYLT I/O**: Reads and writes hybrid word-level + line-break markers directly into audio files
- **Safe File I/O**: Uses `NSFileCoordinator` to prevent iCloud/external storage write conflicts

## Architecture & Key Files
| File | Purpose |
|------|---------|
| `LyricEditor/ContentView.swift` | Root view, `AppState` observable, stage management, playback tracking, SYLT read/write, ambient color extraction, and all UI components (`DropView`, `TrackHomeView`, `ProcessingView`, `LyricsReviewView`, etc.) |
| `LyricEditor/LocalAligner.swift` | Swift FFI wrapper around the `QwenAligner` C library. Handles model loading, PCM decoding (16 kHz mono f32), and forced alignment via `qwen_asr_align_pcm` |
| `LyricEditor/LyricEditorApp.swift` | App entry point. Parses CLI arguments for API credentials and initializes the SwiftUI scene |
| `Package.swift` | Swift Package Manager configuration. Defines iOS 17+ target, SPM dependencies, and build paths |

## Installation & Setup
1. **Prerequisites**: Xcode 15+, iOS 17+ device or simulator, Swift 6.0 toolchain
2. **Clone & Open**: Open the repository in Xcode or run `swift package update`
3. **Add QwenAligner**: The `QwenAligner` C library is distributed as an xcframework and is not included in SPM. Place it in your project and link it to the `LyricEditor` target
4. **Bundle Model Files**: Ensure the `qwen3-aligner-0.6b` model directory (containing `vocab.json` and weights) is added to the app bundle. The app resolves the model path dynamically via `vocab.json`'s parent directory

## Building & Running
- **Xcode**: Open `Package.swift` or the generated `.xcodeproj`, select a device, and run
- **CLI**: `swift build && swift run` (requires passing API credentials via arguments; see Configuration)
- **Permissions**: The app requests audio playback permissions automatically via `AVAudioSession`. No microphone access is required

## Usage
1. **Import Track**: Tap the waveform button or drag-and-drop an audio file (MP3, M4A, etc.)
2. **Choose Sync Method**:
   - **Sync**: Triggers cloud transcription → local alignment
   - **I have the lyrics**: Opens a text editor to paste lyrics, then choose between AI alignment or manual timing
3. **Review & Edit**: 
   - Tap a line to play from that timestamp
   - Long-press to edit text
   - Use `+`/`-` chips to nudge timing, or tap the timestamp to snap to the current playhead
   - Swipe/delete to remove lines (5-second undo window)
4. **Save**: Taps the Save button to write SYLT metadata back to the original file. The app returns to the empty state after a brief success overlay

## Configuration & API Credentials
Cloud transcription requires authentication. Credentials are passed at launch via command-line arguments:
```bash
LyricEditor -u <username> -p <password>
```
These values are consumed in `LyricEditor/LyricEditorApp.swift` and stored in `LyricsAPI.user` and `LyricsAPI.password`. If omitted, cloud transcription will fail gracefully, but local alignment and manual editing remain fully functional.

## Technical Details & Conventions
- **State Machine**: `AppState.stage` cycles through `.empty` → `.loaded` → `.processing` → `.review` → `.saved`. Transitions are guarded by animations and cleanup tasks
- **Playback Tracking**: `startPlaybackTracking()` runs a 50ms `Task` loop. A `suppressSeek` flag prevents feedback loops when synchronizing the UI playhead with `AVAudioPlayer.currentTime`
- **SYLT Format**: Uses a hybrid structure where each word gets a timestamp entry, and line breaks are represented by a `\n` marker at the start of the next line. This preserves word-level alignment while enabling line-level editing
- **File Safety**: `writeSYLT()` copies the target file to a temporary sandbox path, modifies it via `AudioMarkerEngine`, then uses `NSFileCoordinator` to atomically replace the original. This avoids iCloud Drive write conflicts
- **Model Resolution**: `LocalAligner.modelDirectoryURL` finds the model folder by locating `vocab.json` in the bundle and stepping up one directory. This works regardless of whether the model was added as a folder reference or flattened group
- **Ambient Colors**: Extracted via `CIAreaAverage` on three horizontal bands of the album artwork. Luminance-aware dimming ensures readability against the dark canvas

## Dependencies
| Package | Version/Source | Purpose |
|---------|----------------|---------|
| `swiftapi` | `main` branch | HTTP client for `Qwen3AsrFlash` cloud transcription |
| `swift-audio-marker` | `0.1.1` | SYLT metadata reading/writing engine |
| `QwenAligner` | xcframework (manual) | C FFI for on-device forced alignment (`qwen_asr_align_pcm`) |
| `AVFoundation` | System | Audio playback, session management, PCM decoding |
| `CoreImage` | System | Ambient color extraction from artwork |
| `UniformTypeIdentifiers` | System | Audio file type filtering for document picker |