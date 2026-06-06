//
//  ContentView.swift
//  LyricEditor
//
//  Created by u on 05/06/2026.
//

import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import CoreImage

// MARK: - Theme

private enum Theme {
    static let canvas    = Color(red: 0.035, green: 0.039, blue: 0.055)
    static let surface   = Color(red: 0.078, green: 0.086, blue: 0.118)
    static let elevated  = Color(red: 0.110, green: 0.120, blue: 0.158)

    static let primary    = Color.white
    static let secondary  = Color.white.opacity(0.62)
    static let tertiary   = Color.white.opacity(0.32)
    static let hairline   = Color.white.opacity(0.08)

    static let accentA = Color(red: 0.71, green: 0.55, blue: 1.00)
    static let accentB = Color(red: 1.00, green: 0.50, blue: 0.78)

    static let accentGradient = LinearGradient(
        colors: [accentA, accentB],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let canvasGradient = RadialGradient(
        colors: [
            Color(red: 0.14, green: 0.08, blue: 0.22).opacity(0.55),
            canvas.opacity(0)
        ],
        center: .top,
        startRadius: 4,
        endRadius: 520
    )
}

// MARK: - Models & State

private enum Stage {
    case empty
    case loaded
    case processing
    case review
    case saved
}

private struct TrackInfo: Equatable {
    var fileURL: URL
    var title: String
    var artist: String
    var duration: TimeInterval
    var artwork: UIImage?

    static func == (lhs: TrackInfo, rhs: TrackInfo) -> Bool {
        lhs.fileURL == rhs.fileURL &&
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.duration == rhs.duration &&
        lhs.artwork === rhs.artwork
    }
}

private struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    var time: TimeInterval
    var text: String
}

@MainActor
@Observable
private final class AppState {
    var stage: Stage = .empty
    var track: TrackInfo?
    var lyrics: [LyricLine] = []
    var playhead: TimeInterval = 0 {
        didSet {
            guard !suppressSeek, let p = player else { return }
            if abs(p.currentTime - playhead) > 0.1 {
                p.currentTime = playhead
            }
        }
    }
    var isPlaying: Bool = false {
        didSet {
            guard let p = player else { return }
            if isPlaying {
                p.play()
            } else {
                p.pause()
            }
        }
    }
    var showManual: Bool = false
    var isDirty: Bool = false
    var showUndo: Bool = false
    var ambientColors: [Color] = []
    @ObservationIgnored private var lastDeleted: (line: LyricLine, index: Int)?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var displayTask: Task<Void, Never>?
    @ObservationIgnored private var suppressSeek: Bool = false

    var totalDuration: TimeInterval {
        if let d = track?.duration, d > 0 { return d }
        return max((lyrics.map(\.time).max() ?? 30) + 6, 30)
    }

    var currentLineIndex: Int? {
        guard !lyrics.isEmpty else { return nil }
        let hit = lyrics.enumerated()
            .filter { $0.element.time <= playhead }
            .max(by: { $0.element.time < $1.element.time })
        return hit?.offset ?? 0
    }

    func normalize() {
        lyrics.sort { $0.time < $1.time }
        playhead = max(0, min(playhead, totalDuration))
    }

    func loadFile(_ url: URL) {
        teardownPlayer()

        if url.startAccessingSecurityScopedResource() {
            scopedURL = url
        }

        let name = url.deletingPathExtension().lastPathComponent
        let parts = name.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let fallbackArtist = parts.count == 2 ? parts[0] : "Unknown"
        let fallbackTitle  = parts.count == 2 ? parts[1] : name

        var duration: TimeInterval = 0
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            duration = p.duration
            player = p
        } catch {
            player = nil
        }

        track = TrackInfo(
            fileURL: url,
            title: fallbackTitle,
            artist: fallbackArtist,
            duration: duration,
            artwork: nil
        )
        ambientColors = []

        withAnimation(.spring(duration: 0.65, bounce: 0.18)) {
            stage = .loaded
        }

        Task { [weak self] in
            await self?.loadMetadata(from: url)
        }
    }

    private func teardownPlayer() {
        player?.stop()
        player = nil
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    func startPlaybackTracking() {
        displayTask?.cancel()
        displayTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                if let p = player {
                    if p.isPlaying {
                        suppressSeek = true
                        playhead = p.currentTime
                        suppressSeek = false
                    } else if isPlaying {
                        // Player stopped naturally (end of file)
                        isPlaying = false
                        if playhead >= totalDuration - 0.5 {
                            suppressSeek = true
                            playhead = 0
                            suppressSeek = false
                        }
                    }
                } else if isPlaying {
                    // Fallback fake clock if file failed to load
                    let next = playhead + 0.05
                    if next >= totalDuration {
                        isPlaying = false
                        playhead = 0
                    } else {
                        playhead = next
                    }
                }
            }
        }
    }

    func stopPlaybackTracking() {
        displayTask?.cancel()
        displayTask = nil
    }

    private func loadMetadata(from url: URL) async {
        let asset = AVURLAsset(url: url)
        var foundTitle: String?
        var foundArtist: String?
        var foundArtwork: UIImage?

        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                switch item.commonKey {
                case .commonKeyTitle:
                    if let s = try? await item.load(.stringValue), !s.isEmpty { foundTitle = s }
                case .commonKeyArtist:
                    if let s = try? await item.load(.stringValue), !s.isEmpty { foundArtist = s }
                case .commonKeyArtwork:
                    if let data = try? await item.load(.dataValue), let img = UIImage(data: data) {
                        foundArtwork = img
                    }
                default:
                    break
                }
            }
        }

        let colors = foundArtwork?.ambientColors() ?? []

        await MainActor.run {
            if let t = foundTitle { self.track?.title = t }
            if let a = foundArtist { self.track?.artist = a }
            if let img = foundArtwork { self.track?.artwork = img }
            withAnimation(.smooth(duration: 1.0)) {
                self.ambientColors = colors
            }
        }
    }

    func runAI() async {
        withAnimation(.smooth(duration: 0.5)) { stage = .processing }
        try? await Task.sleep(for: .seconds(2.4))
        lyrics = LyricLine.sample
        playhead = 0
        isPlaying = true
        isDirty = false
        withAnimation(.spring(duration: 0.7, bounce: 0.22)) { stage = .review }
    }

    func alignPasted(_ raw: String) {
        let cleaned = raw
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }
        let estimatedDuration: TimeInterval = 180
        let step = estimatedDuration / Double(max(cleaned.count, 1))
        lyrics = cleaned.enumerated().map { i, t in
            LyricLine(time: Double(i) * step, text: t)
        }
        playhead = 0
        showManual = false
        isDirty = false
        withAnimation(.spring(duration: 0.7, bounce: 0.22)) { stage = .review }
    }

    @discardableResult
    func addLine(at time: TimeInterval) -> LyricLine.ID {
        let clamped = max(0, min(totalDuration, time))
        let new = LyricLine(time: clamped, text: "")
        lyrics.append(new)
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
            normalize()
        }
        isDirty = true
        return new.id
    }

    func deleteLine(id: LyricLine.ID) {
        guard let idx = lyrics.firstIndex(where: { $0.id == id }) else { return }
        lastDeleted = (lyrics[idx], idx)
        withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
            _ = lyrics.remove(at: idx)
        }
        isDirty = true
        revealUndo()
    }

    func undoDelete() {
        guard let d = lastDeleted else { return }
        let insertAt = min(d.index, lyrics.count)
        withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
            lyrics.insert(d.line, at: insertAt)
            normalize()
        }
        lastDeleted = nil
        withAnimation(.smooth(duration: 0.25)) { showUndo = false }
        undoTask?.cancel()
    }

    private func revealUndo() {
        undoTask?.cancel()
        withAnimation(.spring(duration: 0.4, bounce: 0.25)) { showUndo = true }
        undoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.3)) { showUndo = false }
            lastDeleted = nil
        }
    }

    func save() {
        normalize()
        isDirty = false
        // Real impl: write SYLT frame back to ID3 tag on track.fileURL.
        withAnimation(.smooth(duration: 0.4)) { stage = .saved }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            await MainActor.run { reset() }
        }
    }

    func reset() {
        undoTask?.cancel()
        lastDeleted = nil
        stopPlaybackTracking()
        teardownPlayer()
        withAnimation(.smooth(duration: 0.45)) {
            stage = .empty
            track = nil
            lyrics = []
            playhead = 0
            isPlaying = false
            showManual = false
            isDirty = false
            showUndo = false
            ambientColors = []
        }
    }
}

private extension LyricLine {
    static let sample: [LyricLine] = [
        .init(time: 0,    text: "We could be anything we want to be"),
        .init(time: 4.2,  text: "Quiet on the wire, loud in the dream"),
        .init(time: 8.6,  text: "And the night keeps holding what we leave behind"),
        .init(time: 13.4, text: "City flickers — every window a memory"),
        .init(time: 18.0, text: "Run with me till the morning bleeds white"),
        .init(time: 22.8, text: "We were never lost — just unwritten"),
        .init(time: 27.6, text: "Stars fall slow in the rear-view"),
        .init(time: 32.0, text: "I'll keep the chorus if you keep the key")
    ]
}

// MARK: - Root

struct ContentView: View {
    @State private var app = AppState()

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            ambientGradient
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(.smooth(duration: 1.2), value: app.ambientColors)

            stage
                .animation(.smooth(duration: 0.45), value: app.stage)

            if app.stage == .saved {
                SavedOverlay()
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accentA)
        .environment(app)
        .sheet(isPresented: Binding(get: { app.showManual }, set: { app.showManual = $0 })) {
            ManualEntryView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.canvas)
                .environment(app)
        }
    }

    @ViewBuilder
    private var stage: some View {
        switch app.stage {
        case .empty:      DropView().transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .loaded:     TrackHomeView().transition(.opacity.combined(with: .move(edge: .bottom)))
        case .processing: ProcessingView().transition(.opacity)
        case .review:     LyricsReviewView().transition(.opacity.combined(with: .scale(scale: 0.98)))
        case .saved:      LyricsReviewView()
        }
    }

    @ViewBuilder
    private var ambientGradient: some View {
        ZStack {
            if app.ambientColors.count >= 2 {
                RadialGradient(
                    colors: [app.ambientColors[0].opacity(0.55), .clear],
                    center: UnitPoint(x: 0.15, y: 0.05),
                    startRadius: 4, endRadius: 520
                )
                RadialGradient(
                    colors: [app.ambientColors[1].opacity(0.40), .clear],
                    center: UnitPoint(x: 0.85, y: 0.95),
                    startRadius: 4, endRadius: 520
                )
                if app.ambientColors.count >= 3 {
                    RadialGradient(
                        colors: [app.ambientColors[2].opacity(0.30), .clear],
                        center: UnitPoint(x: 0.5, y: 0.5),
                        startRadius: 4, endRadius: 440
                    )
                }
            } else if let c = app.ambientColors.first {
                RadialGradient(
                    colors: [c.opacity(0.55), .clear],
                    center: .top,
                    startRadius: 4, endRadius: 520
                )
            } else {
                Theme.canvasGradient
            }
        }
    }
}

// MARK: - Drop

private struct DropView: View {
    @Environment(AppState.self) private var app
    @State private var pulsing = false
    @State private var showImporter = false

    var body: some View {
        VStack {
            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                showImporter = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Theme.accentGradient)
                        .frame(width: 280, height: 280)
                        .blur(radius: 70)
                        .opacity(pulsing ? 0.55 : 0.28)

                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        .frame(width: 188, height: 188)
                        .scaleEffect(pulsing ? 1.04 : 1.0)

                    Circle()
                        .fill(Theme.surface)
                        .frame(width: 156, height: 156)
                        .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)

                    Image(systemName: "waveform")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Theme.accentGradient)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                }
                .scaleEffect(pulsing ? 1.0 : 0.985)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }

            Spacer()

            Text("Drop a track")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .padding(.bottom, 56)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.audio, .mp3],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                _ = url.startAccessingSecurityScopedResource()
                app.loadFile(url)
            }
        }
    }
}

// MARK: - Track Home

private struct TrackHomeView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            artwork
                .padding(.bottom, 32)
            metadata
            Spacer()
            primaryAction
            manualHint
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
    }

    private var topBar: some View {
        HStack {
            CircleIconButton(symbol: "xmark") { app.reset() }
            Spacer()
        }
        .padding(.top, 8)
    }

    private var artwork: some View {
        Group {
            if let img = app.track?.artwork {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.surface
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 56, weight: .ultraLight))
                            .foregroundStyle(Theme.tertiary)
                    }
            }
        }
        .frame(width: 232, height: 232)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 36, y: 16)
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(Theme.accentGradient)
                .frame(width: 14, height: 14)
                .blur(radius: 14)
                .offset(x: -28, y: -28)
        }
    }

    private var metadata: some View {
        VStack(spacing: 6) {
            Text(app.track?.title ?? "")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.primary)
                .lineLimit(1)
            Text(app.track?.artist ?? "")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Theme.secondary)
        }
    }

    private var primaryAction: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { await app.runAI() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .symbolEffect(.pulse, options: .repeating)
                Text("Sync")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(Theme.accentGradient, in: Capsule())
            .shadow(color: Theme.accentA.opacity(0.35), radius: 28, y: 10)
        }
        .buttonStyle(PressableStyle())
    }

    private var manualHint: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            app.showManual = true
        } label: {
            Text("Do it myself")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.tertiary)
                .padding(.top, 18)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Processing

private struct ProcessingView: View {
    @Environment(AppState.self) private var app
    @State private var animate = false
    @State private var statusIndex = 0
    private let statuses = ["Listening", "Aligning", "Polishing"]

    var body: some View {
        VStack(spacing: 56) {
            Spacer()

            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(
                            Theme.accentGradient.opacity(0.55 - Double(i) * 0.16),
                            lineWidth: 1
                        )
                        .frame(width: 90, height: 90)
                        .scaleEffect(animate ? 3.2 : 0.6)
                        .opacity(animate ? 0 : 1)
                        .animation(
                            .easeOut(duration: 2.2)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.55),
                            value: animate
                        )
                }

                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 16, height: 16)
                    .blur(radius: 6)
                    .scaleEffect(2)

                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
            }
            .frame(width: 300, height: 300)

            Text(statuses[statusIndex])
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .contentTransition(.opacity)
                .id(statusIndex)

            Spacer()

            Text(app.track?.title ?? "")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.tertiary)
                .padding(.bottom, 40)
        }
        .onAppear {
            animate = true
            Task {
                for i in 1..<3 {
                    try? await Task.sleep(for: .milliseconds(750))
                    await MainActor.run {
                        withAnimation(.smooth) { statusIndex = i }
                    }
                }
            }
        }
    }
}

// MARK: - Review

private struct LyricsReviewView: View {
    @Environment(AppState.self) private var app
    @State private var editingID: LyricLine.ID?
    @State private var scrubbing = false
    @State private var showDiscardConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            lyricsList
            transport
        }
        .overlay(alignment: .bottom) {
            if app.showUndo {
                undoToast
                    .padding(.horizontal, 20)
                    .padding(.bottom, 168)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .confirmationDialog(
            "Discard your edits?",
            isPresented: $showDiscardConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { app.reset() }
            Button("Keep editing", role: .cancel) {}
        }
        .onAppear { app.startPlaybackTracking() }
        .onDisappear { app.stopPlaybackTracking() }
    }

    private var undoToast: some View {
        HStack(spacing: 12) {
            Image(systemName: "trash.slash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondary)
            Text("Line deleted")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
            Spacer()
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                app.undoDelete()
            } label: {
                Text("Undo")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accentA)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .frame(height: 50)
        .background(Theme.elevated, in: Capsule())
        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 22, y: 10)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            CircleIconButton(symbol: "chevron.left") {
                if app.isDirty {
                    showDiscardConfirm = true
                } else {
                    app.reset()
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 10) {
                Group {
                    if let img = app.track?.artwork {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Theme.surface
                            .overlay {
                                Image(systemName: "music.note")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(Theme.tertiary)
                            }
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                )
                Text(app.track?.title ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                app.save()
            } label: {
                Text("Save")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(Theme.accentGradient, in: Capsule())
                    .opacity(app.isDirty ? 1.0 : 0.45)
            }
            .buttonStyle(PressableStyle())
            .disabled(!app.isDirty)
            .animation(.smooth(duration: 0.25), value: app.isDirty)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var lyricsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    Color.clear.frame(height: 80)
                    ForEach(Array(app.lyrics.enumerated()), id: \.element.id) { idx, line in
                        LyricRow(
                            line: line,
                            isCurrent: editingID == nil && idx == app.currentLineIndex,
                            isEditing: editingID == line.id,
                            onTap: {
                                UISelectionFeedbackGenerator().selectionChanged()
                                editingID = nil
                                app.playhead = line.time
                                app.isPlaying = true
                            },
                            onLongPress: {
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                editingID = line.id
                            },
                            onCommit: { newText in
                                if let i = app.lyrics.firstIndex(where: { $0.id == line.id }) {
                                    app.lyrics[i].text = newText
                                    app.isDirty = true
                                }
                                editingID = nil
                            },
                            onNudge: { delta in
                                if let i = app.lyrics.firstIndex(where: { $0.id == line.id }) {
                                    let new = app.lyrics[i].time + delta
                                    app.lyrics[i].time = max(0, min(app.totalDuration, new))
                                }
                            },
                            onNudgeEnd: {
                                app.isDirty = true
                                withAnimation(.spring(duration: 0.5, bounce: 0.18)) {
                                    app.normalize()
                                }
                            },
                            onSnap: {
                                if let i = app.lyrics.firstIndex(where: { $0.id == line.id }) {
                                    app.isDirty = true
                                    withAnimation(.spring(duration: 0.5, bounce: 0.25)) {
                                        app.lyrics[i].time = app.playhead
                                        app.normalize()
                                    }
                                }
                            },
                            onDelete: {
                                editingID = nil
                                app.deleteLine(id: line.id)
                            }
                        )
                        .id(line.id)
                    }
                    Color.clear.frame(height: 220)
                }
                .padding(.horizontal, 28)
            }
            .scrollIndicators(.hidden)
            .onChange(of: app.currentLineIndex) { _, new in
                guard editingID == nil, let new, new < app.lyrics.count else { return }
                if scrubbing {
                    proxy.scrollTo(app.lyrics[new].id, anchor: .center)
                } else {
                    withAnimation(.smooth(duration: 0.55)) {
                        proxy.scrollTo(app.lyrics[new].id, anchor: .center)
                    }
                }
            }
        }
    }

    private var transport: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let total = app.totalDuration
                let progress = min(1, max(0, app.playhead / total))
                let x = geo.size.width * CGFloat(progress)
                let thumbSize: CGFloat = scrubbing ? 14 : 8
                let barHeight: CGFloat = scrubbing ? 5 : 3
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: barHeight)
                    Capsule()
                        .fill(Theme.accentGradient)
                        .frame(width: x, height: barHeight)
                    Circle()
                        .fill(.white)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: Theme.accentA.opacity(0.55), radius: scrubbing ? 14 : 4)
                        .offset(x: x - thumbSize / 2)
                }
                .frame(height: 36)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !scrubbing {
                                scrubbing = true
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            }
                            let nx = max(0, min(geo.size.width, value.location.x))
                            app.playhead = (nx / geo.size.width) * total
                        }
                        .onEnded { _ in
                            scrubbing = false
                        }
                )
                .animation(.smooth(duration: 0.2), value: scrubbing)
            }
            .frame(height: 36)

            HStack {
                Text(timeString(app.playhead))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
                Spacer()
                HStack(spacing: 14) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        let newID = app.addLine(at: app.playhead)
                        editingID = newID
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 40, height: 40)
                            .background(Theme.surface, in: Circle())
                            .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        app.isPlaying.toggle()
                    } label: {
                        Image(systemName: app.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Theme.accentGradient))
                            .shadow(color: Theme.accentA.opacity(0.45), radius: 18, y: 8)
                    }
                    .buttonStyle(PressableStyle())
                }
                Spacer()
                Text(timeString(app.totalDuration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 28)
        .background(
            LinearGradient(
                colors: [Theme.canvas.opacity(0), Theme.canvas, Theme.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

}

private struct LyricRow: View {
    let line: LyricLine
    let isCurrent: Bool
    let isEditing: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onCommit: (String) -> Void
    let onNudge: (TimeInterval) -> Void
    let onNudgeEnd: () -> Void
    let onSnap: () -> Void
    let onDelete: () -> Void

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                TextField("Lyric…", text: $draft, axis: .vertical)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .tint(Theme.accentA)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { onCommit(draft) }
                    .toolbar {
                        if focused {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") {
                                    focused = false
                                    onCommit(draft)
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.accentA)
                            }
                        }
                    }

                HStack(spacing: 10) {
                    NudgeChip(symbol: "minus", direction: -1, onNudge: onNudge, onNudgeEnd: onNudgeEnd)
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSnap()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "scope")
                                .font(.system(size: 10, weight: .bold))
                            Text(timeString(line.time))
                                .monospacedDigit()
                        }
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.accentA)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Theme.elevated, in: Capsule())
                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                    NudgeChip(symbol: "plus", direction: 1, onNudge: onNudge, onNudgeEnd: onNudgeEnd)
                    Spacer()
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color(red: 0.86, green: 0.27, blue: 0.32), in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.10), lineWidth: 1))
                    }
                    .buttonStyle(PressableStyle())
                    Button("Done") { onCommit(draft) }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Theme.accentGradient, in: Capsule())
                }
                .padding(.top, 2)
            } else {
                Text(line.text)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(isCurrent ? Theme.primary : Theme.tertiary)
                    .shadow(
                        color: isCurrent ? Theme.accentA.opacity(0.4) : .clear,
                        radius: 18
                    )
            }
        }
        .scaleEffect(isCurrent && !isEditing ? 1.02 : 0.97, anchor: .leading)
        .animation(.smooth(duration: 0.35), value: isCurrent)
        .animation(.smooth(duration: 0.3), value: isEditing)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing { onTap() }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
            if !isEditing {
                draft = line.text
                onLongPress()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
            }
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        let ms = Int((t - Double(s)) * 100)
        return String(format: "%d:%02d.%02d", s / 60, s % 60, ms)
    }
}

private struct NudgeChip: View {
    let symbol: String
    let direction: Double
    let onNudge: (TimeInterval) -> Void
    let onNudgeEnd: () -> Void

    @State private var pressed = false
    @State private var didRepeat = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(Theme.primary)
            .frame(width: 30, height: 30)
            .background(pressed ? Theme.accentGradient.opacity(0.35) : nil)
            .background(Theme.elevated, in: Circle())
            .clipShape(Circle())
            .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
            .scaleEffect(pressed ? 0.92 : 1.0)
            .animation(.smooth(duration: 0.15), value: pressed)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        startHold()
                    }
                    .onEnded { _ in
                        pressed = false
                        holdTask?.cancel()
                        if !didRepeat {
                            UISelectionFeedbackGenerator().selectionChanged()
                            onNudge(0.1 * direction)
                        }
                        didRepeat = false
                        onNudgeEnd()
                    }
            )
    }

    private func startHold() {
        didRepeat = false
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            if Task.isCancelled { return }
            didRepeat = true
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            let startedAt = Date()
            while !Task.isCancelled {
                let held = Date().timeIntervalSince(startedAt)
                let step: TimeInterval = held < 1.0 ? 0.1 : (held < 2.5 ? 0.5 : 1.0)
                onNudge(step * direction)
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }
}

// MARK: - Manual

private struct ManualEntryView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("Paste lyrics")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                Text("One line per line. We'll handle the timing.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.tertiary)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 18)

                TextEditor(text: $text)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white)
                    .tint(Theme.accentA)
                    .padding(.horizontal, 20)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    app.alignPasted(text)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                        Text("Align with audio")
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Theme.accentGradient, in: Capsule())
                    .shadow(color: Theme.accentA.opacity(0.35), radius: 24, y: 8)
                }
                .buttonStyle(PressableStyle())
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                .padding(20)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { focused = true }
        }
    }
}

// MARK: - Saved overlay

private struct SavedOverlay: View {
    @State private var bounce = false
    var body: some View {
        ZStack {
            Theme.canvas.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Theme.accentGradient)
                        .frame(width: 80, height: 80)
                        .blur(radius: 30)
                        .opacity(0.6)
                    Circle()
                        .fill(Theme.surface)
                        .frame(width: 84, height: 84)
                        .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Theme.accentGradient)
                        .scaleEffect(bounce ? 1 : 0.3)
                        .opacity(bounce ? 1 : 0)
                }
                Text("Saved")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                    .opacity(bounce ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.55, bounce: 0.45)) { bounce = true }
        }
    }
}

// MARK: - Shared bits

private struct CircleIconButton: View {
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        }) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .frame(width: 38, height: 38)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.smooth(duration: 0.18), value: configuration.isPressed)
    }
}

private extension UIImage {
    func ambientColors() -> [Color] {
        guard let ci = CIImage(image: self) else { return [] }
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        let extent = ci.extent
        let w = extent.width
        let h = extent.height
        let regions: [CGRect] = [
            CGRect(x: extent.minX, y: extent.minY + h * 0.66, width: w, height: h * 0.34),
            CGRect(x: extent.minX, y: extent.minY + h * 0.33, width: w, height: h * 0.34),
            CGRect(x: extent.minX, y: extent.minY,            width: w, height: h * 0.34)
        ]
        return regions.compactMap { rect in
            averageColor(in: ci.cropped(to: rect), ctx: ctx)
        }
    }

    private func averageColor(in ci: CIImage, ctx: CIContext) -> Color? {
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ci,
            kCIInputExtentKey: CIVector(cgRect: ci.extent)
        ]),
        let output = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ctx.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        let r = Double(bitmap[0]) / 255
        let g = Double(bitmap[1]) / 255
        let b = Double(bitmap[2]) / 255

        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let factor: Double = lum > 0.55 ? 0.45 : (lum > 0.35 ? 0.62 : 0.85)
        return Color(red: r * factor, green: g * factor, blue: b * factor)
    }
}

#Preview {
    ContentView()
}
