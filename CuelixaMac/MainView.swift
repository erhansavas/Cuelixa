// SPDX-License-Identifier: Apache-2.0
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
  @EnvironmentObject private var model: AppModel
  @State private var columnVisibility: NavigationSplitViewVisibility = .all
  @State private var searchText = ""
  @State private var selectedSection: LibrarySection? = .all
  @State private var selectedTrackID: Track.ID?
  @State private var showingBatchStatus = false
  @State private var showingResetSubtitlesConfirmation = false

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      LibrarySidebar(selection: $selectedSection)
        .environmentObject(model)
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
    } detail: {
      LibraryContent(selection: $selectedTrackID, player: model.player)
        .environmentObject(model)
        .searchable(text: $searchText, placement: .toolbar, prompt: Text("Search Lessons"))
    }
    .tint(CuelixaDesign.identityAccent)
    .task(id: searchText) {
      if model.query != searchText { model.setQuery(searchText) }
    }
    .task(id: selectedSection) {
      if let selectedSection, model.section != selectedSection {
        model.setSection(selectedSection)
      }
    }
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Menu {
          Button {
            model.openLibraryFolder()
          } label: {
            Label("Open Library Folder", systemImage: "folder")
          }

          Divider()

          Button(role: .destructive) {
            showingResetSubtitlesConfirmation = true
          } label: {
            Label("Reset Prepared Subtitles…", systemImage: "trash")
          }
          .disabled(!model.canResetPreparedSubtitles)
        } label: {
          Label("Library Actions", systemImage: "ellipsis.circle")
        }
        .help("Library and subtitle actions")
      }

      ToolbarItem(placement: .secondaryAction) {
        Button {
          if !model.batch.visible {
            model.prepareAll()
          }
          showingBatchStatus = true
        } label: {
          Label(
            model.batch.active ? "Preparing Subtitles" : "Prepare All Subtitles",
            systemImage: model.batch.active ? "captions.bubble.fill" : "captions.bubble"
          )
        }
        .disabled(model.missingSubtitleCount == 0 && !model.batch.visible)
        .help(
          model.batch.active
            ? "Show subtitle preparation progress"
            : "Prepare subtitles for every lesson that still needs them"
        )
        .popover(isPresented: $showingBatchStatus, arrowEdge: .top) {
          BatchStatusPopover(isPresented: $showingBatchStatus)
            .environmentObject(model)
            .frame(width: 380, height: 158, alignment: .topLeading)
            .padding(16)
        }
      }
    }
    .alert("Reset all prepared subtitles?", isPresented: $showingResetSubtitlesConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Reset Subtitles", role: .destructive) {
        model.resetPreparedSubtitles()
      }
    } message: {
      Text(
        "This deletes subtitles generated and managed by Cuelixa, including compatible legacy Cuelixa caches. Your lesson audio and your own sidecar .srt files are not changed. You can prepare subtitles again at any time."
      )
    }
    .dropDestination(for: URL.self) { urls, _ in
      model.importFiles(urls)
      return true
    }
  }
}

private struct LibrarySidebar: View {
  @EnvironmentObject private var model: AppModel
  @Binding var selection: LibrarySection?

  var body: some View {
    List(selection: $selection) {
      Section("Library") {
        ForEach(LibrarySection.allCases) { section in
          SidebarSectionRow(section: section, count: model.counts[section])
            .tag(section)
        }
      }

      Section("Folders") {
        Button(action: model.openLibraryFolder) {
          Label("Library Folder", systemImage: "folder")
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Cuelixa’s lesson library folder")
      }
    }
    .listStyle(.sidebar)
    .scrollContentBackground(.hidden)
    .background(CuelixaDesign.sidebarBackground)
  }
}

private struct SidebarSectionRow: View {
  let section: LibrarySection
  let count: Int

  var body: some View {
    Label {
      HStack(spacing: 8) {
        Text(section.title)
          .lineLimit(1)
          .layoutPriority(1)
        Spacer(minLength: 8)
        Text("\(count)")
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: true, vertical: false)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } icon: {
      Image(systemName: section.symbol)
        .symbolRenderingMode(.monochrome)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(section.title), \(count)")
  }
}

private struct LibraryContent: View {
  @EnvironmentObject private var model: AppModel
  @Binding var selection: Track.ID?
  @ObservedObject var player: PlaybackController
  @FocusState private var listHasFocus: Bool

  var body: some View {
    Group {
      if model.tracks.isEmpty {
        emptyState
      } else {
        List(model.tracks, selection: $selection) { track in
          TrackRow(
            track: track,
            selected: selection == track.id,
            player: player
          )
          .environmentObject(model)
          .tag(track.id)
          .listRowSeparator(.visible, edges: .bottom)
          .listRowSeparatorTint(Color.secondary.opacity(0.11), edges: .bottom)
          .listRowBackground(
            player.activeHash == track.contentHash && player.isRunning
              ? CuelixaDesign.identityAccent.opacity(0.05)
              : Color.clear
          )
        }
        .listStyle(.inset)
        .accessibilityLabel("Lessons")
        .focused($listHasFocus)
        .onChange(of: selection) { _, selection in
          if selection != nil { listHasFocus = true }
        }
        .simultaneousGesture(TapGesture().onEnded { listHasFocus = true })
        .onKeyPress(.return) { activateSelection() }
        .onKeyPress(.space) { activateSelection() }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle(model.section.title)
  }

  private func activateSelection() -> KeyPress.Result {
    guard let selection,
      let track = model.tracks.first(where: { $0.id == selection })
    else { return .ignored }
    // Key handling can run during SwiftUI's focus update; publish playback state afterward.
    Task { @MainActor [model] in
      if model.player.activeHash == track.contentHash && model.player.isRunning {
        model.togglePlayPause()
      } else {
        model.playTrack(track)
      }
    }
    return .handled
  }

  @ViewBuilder
  private var emptyState: some View {
    if model.query.isEmpty {
      if model.section == .all {
        ContentUnavailableView(
          "Your Library is Empty",
          systemImage: "waveform",
          description: Text("Drop supported audio files here or add them to your Library Folder.")
        )
      } else {
        ContentUnavailableView(
          "Nothing Here Yet",
          systemImage: model.section.symbol,
          description: Text("This section updates automatically as you listen.")
        )
      }
    } else {
      ContentUnavailableView.search(text: model.query)
    }
  }
}

private struct BatchStatusPopover: View {
  @EnvironmentObject private var model: AppModel
  @Binding var isPresented: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Text(model.batch.title)
          .font(.headline)
          .lineLimit(1)
        Spacer(minLength: 12)
        if !model.batch.count.isEmpty {
          Text(model.batch.count)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }

      Text(model.batch.track.isEmpty ? " " : model.batch.track)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(height: 18, alignment: .leading)
        .opacity(model.batch.track.isEmpty ? 0 : 1)

      Group {
        if model.batch.active {
          if let progress = model.batch.progress {
            ProgressView(value: progress, total: 1)
              .progressViewStyle(.linear)
          } else {
            ProgressView()
              .progressViewStyle(.linear)
          }
        } else {
          Color.clear
        }
      }
      .frame(height: 8)

      Text(model.batch.detail.isEmpty ? " " : model.batch.detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .frame(height: 30, alignment: .topLeading)
        .opacity(model.batch.detail.isEmpty ? 0 : 1)

      HStack {
        Spacer()
        if model.batch.active {
          Button(model.batch.cancelling ? "Cancelling…" : "Cancel") {
            model.cancelBatch()
          }
          .disabled(model.batch.cancelling)
        } else if model.batch.visible {
          Button("Dismiss") {
            model.hideBatch()
            isPresented = false
          }
          Button("Prepare Again") {
            model.hideBatch()
            model.prepareAll()
          }
          .disabled(model.missingSubtitleCount == 0)
        }
      }
    }
  }
}

struct TrackActionsMenu: View {
  @EnvironmentObject private var model: AppModel
  let track: Track

  private var isActive: Bool {
    model.player.activeHash == track.contentHash && model.player.isRunning
  }

  private var playTitle: String {
    if isActive { return model.player.isPlaybackRequested ? "Pause" : "Play" }
    return track.completed || track.position < 10 ? "Play" : "Resume"
  }

  var body: some View {
    Menu {
      Button(playTitle) {
        if isActive { model.togglePlayPause() } else { model.playTrack(track) }
      }
      Divider()
      Button(track.completed ? "Mark as Unfinished" : "Mark as Finished") {
        model.mark(track, completed: !track.completed)
      }
      if !model.subtitleReady(track) {
        Button("Prepare Subtitles") { model.prepareTrack(track) }
      }
      Button("Start from Beginning") { model.restart(track) }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(CuelixaDesign.identityAccent)
        .frame(width: 30, height: 30)
        .contentShape(Rectangle())
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
  }
}

struct TrackRow: View {
  @EnvironmentObject private var model: AppModel
  @State private var hovering = false
  let track: Track
  let selected: Bool
  @ObservedObject var player: PlaybackController

  private var isActive: Bool {
    player.activeHash == track.contentHash && player.isRunning
  }

  private var playTitle: String {
    if isActive { return player.isPlaybackRequested ? "Pause" : "Play" }
    return track.completed || track.position < 10 ? "Play" : "Resume"
  }

  private var progressLabel: String? {
    if track.completed { return "Completed" }
    if track.position >= 10 { return "Resume \(clockLabel(track.position))" }
    return nil
  }

  var body: some View {
    HStack(spacing: 12) {
      Button {
        if isActive {
          model.togglePlayPause()
        } else {
          model.playTrack(track)
        }
      } label: {
        ZStack {
          Circle()
            .fill(CuelixaDesign.identityAccent.opacity(hovering || isActive ? 0.18 : 0.10))
          Image(systemName: isActive && player.isPlaybackRequested ? "pause.fill" : "play.fill")
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(CuelixaDesign.identityAccent)
        }
        .frame(width: 26, height: 26)
        .frame(width: 34, height: 34)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("\(playTitle) \(track.title)")
      .accessibilityLabel("\(playTitle) \(track.title)")

      VStack(alignment: .leading, spacing: 3) {
        Text(track.title)
          .font(.body.weight(isActive ? .semibold : .regular))
          .foregroundStyle(.primary)
          .lineLimit(1)

        HStack(spacing: 7) {
          if let progressLabel {
            Label(progressLabel, systemImage: track.completed ? "checkmark.circle.fill" : "clock")
              .labelStyle(.titleAndIcon)
          }
          if model.subtitleReady(track) {
            Image(systemName: "captions.bubble.fill")
              .foregroundStyle(.tertiary)
              .accessibilityLabel("Subtitles ready")
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer(minLength: 12)

      Text(durationLabel(track.duration))
        .font(.caption.monospacedDigit())
        .foregroundStyle(.primary)
        .frame(width: 46, alignment: .trailing)

      TrackActionsMenu(track: track)
        .environmentObject(model)
        .opacity(hovering || selected ? 1 : 0.72)
        .accessibilityLabel("More actions for \(track.title)")
    }
    .padding(.vertical, 5)
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .simultaneousGesture(
      TapGesture(count: 2).onEnded {
        if isActive { model.togglePlayPause() } else { model.playTrack(track) }
      }
    )
    .contextMenu {
      Button(playTitle) {
        if isActive { model.togglePlayPause() } else { model.playTrack(track) }
      }
      Divider()
      Button(track.completed ? "Mark as Unfinished" : "Mark as Finished") {
        model.mark(track, completed: !track.completed)
      }
      if !model.subtitleReady(track) {
        Button("Prepare Subtitles") { model.prepareTrack(track) }
      }
      Button("Start from Beginning") { model.restart(track) }
    }
  }
}
