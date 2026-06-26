# LyricEditor

**LyricEditor** is a native iOS application for synchronizing lyrics with audio tracks. It supports three workflows: server-side transcription with local alignment, local forced alignment of user-provided lyrics, and manual timing adjustment. The app features a polished dark-mode interface with ambient color extraction from album art, real-time playback scrubbing, and persistent storage of synchronized lyrics directly into the audio file's metadata (SYLT).

## Features

- **Three Alignment Modes**:
  1. **Server Transcription**: Uploads audio to a server (Qwen3AsrFlash) to generate lyrics, then performs local forced alignment.
  2. **Local Alignment**: User pastes lyrics; the app uses an on-device `qwen3-aligner-0.6b` model to force-align timings.
  3. **Manual Mode**: User pastes lyrics; the app distributes them evenly by default, allowing manual nudging and snapping.
- **Real-Time Playback**: Scrubbing transport, play/pause, and automatic scrolling to the current lyric line.
- **Metadata Persistence**: Writes synchronized lyrics (SYLT) directly into the audio file using `AudioMarker`, preserving the original file structure.
- **Ambient UI**: Extracts dominant colors from album artwork to create dynamic radial gradients in the background.
- **Undo Support**: Non-destructive editing with a 5-second undo window for deleted lines.

## Architecture

The project is built with SwiftUI and follows a state-driven architecture.

### Key Files

- **`LyricEditor/ContentView.swift`**: The core of the application. Contains the `AppState` observable class, all view models, and the UI components (`DropView`, `TrackHomeView`, `LyricsReviewView`, etc.).
- **`LyricEditor/LocalAligner.swift`**: Swift wrapper around the `QwenAligner` C FFI. Handles model loading, audio decoding (to 16kHz mono f32 PCM), and the actual forced alignment process.
- **`LyricEditor/LyricEditorApp.swift`**: App entry point. Handles JWT token configuration from launch arguments.
- **`Package.swift`**: Swift Package Manager manifest defining dependencies (`swiftapi`, `swift-audio-marker`).

### Data Flow

1. **Input**: User drops an audio file or picks one via `UIDocumentPickerViewController`.
2. **Processing**:
   - `AppState.loadFile()` initializes the `AVAudioPlayer` and extracts metadata.
   - Depending on the mode, `LyricsAPI` (server) or `LocalAligner` (on-device) generates word-level timings.
3. **Review**: `LyricsReviewView` displays lines. Users can edit text, nudge timings, or snap lines to the playhead.
4. **Save**: `writeSYLT()` copies the file to a sandbox, modifies the metadata using `AudioMarkerEngine`, and uses `NSFileCoordinator` to write back safely.

## Installation & Setup

### Prerequisites

- **iOS 17+**
- **Xcode 15+**
- **Swift 6.0**

### Dependencies

The project uses Swift Package Manager. Ensure you have the following packages resolved:

1. **`swiftapi`**: For API communication.
   - URL: `https://github.com/femimarket/swiftapi` (branch: `main`)
2. **`swift-audio-marker`**: For reading/writing SYLT metadata.
   - URL: `https://github.com/atelier-socle/swift-audio-marker` (version: `0.1.1`+)
3. **`QwenAligner`**: An xcframework containing the C FFI for the alignment engine.
   - *Note*: This framework is not listed in `Package.swift` dependencies explicitly in the provided snippet but is imported in `LocalAligner.swift`. Ensure `QwenAligner.xcframework` is linked in your Xcode project target settings.
4. **Model Files**: The app expects the `qwen3-aligner-0.6b` model files (including `vocab.json`) to be present in the app bundle. The `LocalAligner` locates them via `Bundle.main.url(forResource: "vocab", withExtension: "json")`.

### Building

1. Clone the repository.
2. Open the project in Xcode.
3. Resolve Swift Package Manager dependencies.
4. Ensure `QwenAligner.xcframework` is added to the **LyricEditor** target's **Frameworks, Libraries, and Embedded Content**.
5. Ensure the `qwen3-aligner-0.6b` model directory is added to the app bundle resources.
6. Build and run on a physical iOS device (local alignment requires significant compute resources).

## Usage

### Starting the App

1. Launch the app. You will see a pulsing "Drop a track" button.
2. Tap the button to open the file picker, or drag and drop an audio file (if supported by your environment).

### Workflow 1: Server Transcription (AI Sync)

1. After loading a track, tap **"Sync"**.
2. The app uploads the audio to the server (requires network).
3. The server returns transcribed lyrics.
4. The app performs local forced alignment.
5. You are taken to the **Review** stage.

### Workflow 2: Local Alignment (I have the lyrics)

1. After loading a track, tap **"I have the lyrics"**.
2. Paste your lyrics into the text editor.
3. Tap **"Align with AI"**.
4. The app uses the on-device `qwen3-aligner` to time the lyrics.
5. You are taken to the **Review** stage.

### Workflow 3: Manual Timing

1. After loading a track, tap **"I have the lyrics"**.
2. Paste your lyrics.
3. Tap **"I'll time them myself"**.
4. Lyrics are distributed evenly. Use the **Nudge** buttons (+/-) or **Snap** to the playhead to adjust timings.

### Editing & Saving

- **Edit Text**: Long-press a lyric line to enter edit mode.
- **Adjust Timing**: Use the `+`/`-` nudge chips or drag the playhead to snap a line.
- **Delete**: Tap the trash icon to delete a line. An "Undo" toast appears for 5 seconds.
- **Save**: Tap **"Save"** in the top bar. The app writes the SYLT metadata back to the original audio file.

## Configuration

### API Token

The app can be configured with a bearer token for server-side transcription.

- **Launch Argument**: Pass `-idtoken <JWT>` in the Xcode scheme's **Arguments Passed On Launch**.
- **Fallback**: If no token is provided, the app uses `UIDevice.current.identifierForVendor` as an anonymous user ID.

Example Xcode Scheme Configuration:
1. Go to **Product > Scheme > Edit Scheme...**
2. Select **Run** > **Arguments** tab.
3. Add `-idtoken` and `your_jwt_token_here` to the **Arguments Passed On Launch** list.

## Non-Obvious Conventions

- **SYLT Format**: The app uses a hybrid SYLT format where each word has its own timestamp, and a special entry with `text == "\n"` marks line breaks. This allows for precise word-level alignment while preserving line structure.
- **File Writing**: Due to security restrictions (e.g., iCloud Drive), the app cannot write directly to the source file's parent directory. It copies the file to the temp directory, modifies it, and uses `NSFileCoordinator` to safely replace the original.
- **Audio Decoding**: The local aligner requires 16kHz, mono, float32 PCM. The app handles automatic conversion from various source formats (MP3, AAC, etc.) using `AVAudioConverter`.
- **Ambient Colors**: Colors are extracted from the album art by dividing the image into three horizontal bands and calculating the average color of each, then applying luminance-based opacity adjustments for better contrast.