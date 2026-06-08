import SwiftUI
import AVKit
import UIKit
import Photos

struct RecordsView: View {
    @StateObject private var viewModel = RecordsViewModel()
    @State private var selectedRecording: Recording?
    @State private var recordingPendingAction: Recording?
    @State private var showConfirmAlert = false
    @State private var confirmAlertType: ConfirmType = .delete
    @State private var recordingToRename: Recording?
    @State private var renameText = ""
    @State private var infoRecording: Recording?
    @State private var actionToast: String?
    @State private var isSelectionMode = false
    @State private var selectedIDs = Set<UUID>()
    @State private var scrolledToTop = true

    @AppStorage("records.sortOrder") private var storedSort = "newest"
    @AppStorage("records.viewMode") private var storedView = "grid"
    @State private var selectedFilter: MediaFilter = .all
    @State private var cameraSubFilter: CameraSubFilter = .all
    @State private var sortOption: SortOption = .newest
    @State private var viewMode: ViewMode = .grid

    enum ConfirmType { case delete, copy, move }

    enum MediaFilter: String, CaseIterable, Identifiable {
        case all = "All", video = "FadCam", photo = "FadShot"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .all: "square.grid.2x2.fill"
            case .video: "video.fill"
            case .photo: "camera.fill"
            }
        }
        func matches(_ r: Recording) -> Bool {
            switch self {
            case .all: true
            case .video: r.isVideo
            case .photo: r.isPhoto
            }
        }
    }

    enum CameraSubFilter: String, CaseIterable, Identifiable {
        case all = "All", back = "Back", front = "Front"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .all: "camera.fill"
            case .back: "camera"
            case .front: "person.crop.square"
            }
        }
        func matches(_ r: Recording) -> Bool {
            switch self {
            case .all: true
            case .back: r.cameraPosition == "Back"
            case .front: r.cameraPosition == "Front"
            }
        }
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case newest = "Newest", oldest = "Oldest", largest = "Largest", smallest = "Smallest"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .newest: "arrow.down.circle"
            case .oldest: "arrow.up.circle"
            case .largest: "arrow.down.left.circle"
            case .smallest: "arrow.up.right.circle"
            }
        }
    }

    enum ViewMode: String { case grid, list }

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                if viewModel.isLoading {
                    ProgressView().tint(.red)
                } else if viewModel.recordings.isEmpty {
                    emptyState
                } else {
                    contentView
                }

                if isSelectionMode { selectionBottomBar }
                if let toast = actionToast { toastView(toast) }
                if !scrolledToTop { scrollFAB }
            }
            .navigationTitle(isSelectionMode ? selectionTitle : "Recordings")
            .navigationBarTitleDisplayMode(isSelectionMode ? .inline : .large)
            .toolbar { toolbarContent }
            .refreshable { viewModel.loadRecordings() }
            .onAppear {
                sortOption = SortOption(rawValue: storedSort) ?? .newest
                viewMode = ViewMode(rawValue: storedView) ?? .grid
                viewModel.loadRecordings()
                viewModel.checkPhotosPermission()
            }
            .onChange(of: sortOption) { storedSort = $0.rawValue }
            .onChange(of: viewMode) { storedView = $0.rawValue }
            .sheet(item: $selectedRecording) { recording in
                if recording.isVideo {
                    VideoPlayerView(url: recording.url)
                } else {
                    PhotoViewerView(url: recording.url)
                }
            }
            .onChange(of: selectedRecording) { newValue in
                if let rec = newValue { viewModel.markAsViewed(rec) }
            }
            .sheet(item: $infoRecording) { FileInfoView(recording: $0) }
            .alert(confirmAlertTitle, isPresented: $showConfirmAlert) {
                Button("Cancel", role: .cancel) { cancelConfirm() }
                Button(confirmButtonLabel, role: confirmButtonRole) { executeConfirm() }
            } message: {
                Text(confirmMessage)
            }
            .alert("Rename File", isPresented: Binding(
                get: { recordingToRename != nil },
                set: { if !$0 { recordingToRename = nil } }
            )) {
                TextField("File name", text: $renameText)
                Button("Cancel", role: .cancel) {
                    recordingToRename = nil
                    renameText = ""
                }
                Button("Rename") {
                    if let r = recordingToRename {
                        showToast(viewModel.renameRecording(r, to: renameText) ? "Renamed" : "Rename failed")
                    }
                    recordingToRename = nil
                    renameText = ""
                }
            } message: { Text("Choose a new name for this file.") }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if isSelectionMode {
                Button {
                    withAnimation { isSelectionMode = false; selectedIDs.removeAll() }
                } label: {
                    Text("Done").font(.system(size: 16, weight: .semibold)).foregroundColor(.red)
                }
            }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            if isSelectionMode {
                Button { toggleSelectAll() } label: {
                    Text(selectedIDs.count == filteredRecordings.count ? "Deselect All" : "Select All")
                        .font(.system(size: 13)).foregroundColor(.red)
                }
            } else {
                Button { viewModel.loadRecordings() } label: {
                    Image(systemName: "arrow.clockwise").foregroundColor(.red)
                }
            }
        }
    }

    // MARK: - Confirmations

    private var confirmAlertTitle: String {
        switch confirmAlertType {
        case .delete: return "Delete \(isSelectionMode ? "selected" : "this") file?"
        case .copy: return "Copy \(selectedIDs.count) file(s) to Gallery?"
        case .move: return "Move \(selectedIDs.count) file(s) to Gallery?"
        }
    }

    private var confirmButtonLabel: String {
        switch confirmAlertType {
        case .delete: return isSelectionMode ? "Move to Trash" : "Move to Trash"
        case .copy: return "Copy"
        case .move: return "Move"
        }
    }

    private var confirmButtonRole: ButtonRole? {
        confirmAlertType == .delete ? .destructive : nil
    }

    private var confirmMessage: String {
        switch confirmAlertType {
        case .delete:
            return isSelectionMode
                ? "Move \(selectedIDs.count) selected file(s) to Trash?"
                : "This file will be moved to Trash."
        case .copy:
            return "Create copies of \(selectedIDs.count) file(s) in your Photos library?"
        case .move:
            return "Move \(selectedIDs.count) file(s) from FadCam to your Photos library?"
        }
    }

    private func cancelConfirm() {
        recordingPendingAction = nil
        if isSelectionMode { isSelectionMode = false; selectedIDs.removeAll() }
    }

    private func executeConfirm() {
        switch confirmAlertType {
        case .delete:
            if isSelectionMode {
                batchDelete()
                showToast("Moved \(selectedIDs.count) files to trash")
            } else if let rec = recordingPendingAction {
                viewModel.deleteRecording(rec)
                showToast("Moved to trash")
            }
            recordingPendingAction = nil
        case .copy:
            batchSaveToGallery(copyOnly: true)
        case .move:
            batchSaveToGallery(copyOnly: false)
        }
    }

    // MARK: - Selection UI

    private var selectionTitle: String {
        let sel = filteredRecordings.filter { selectedIDs.contains($0.id) }
        let totalSize = sel.reduce(Int64(0)) { $0 + $1.fileSize }
        let sizeStr = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
        return "\(selectedIDs.count) selected \u{00B7} \(sizeStr)"
    }

    private var selectionBottomBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 0) {
                Button {
                    confirmAlertType = .copy; showConfirmAlert = true
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "doc.on.doc").font(.system(size: 16))
                        Text("Copy").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                Divider().frame(height: 28).background(Color.white.opacity(0.15))
                Button {
                    confirmAlertType = .move; showConfirmAlert = true
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "tray.and.arrow.up").font(.system(size: 16))
                        Text("Move").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                Divider().frame(height: 28).background(Color.white.opacity(0.15))
                Button(role: .destructive) {
                    confirmAlertType = .delete; showConfirmAlert = true
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "trash").font(.system(size: 16))
                        Text("Delete").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
    }

    private var scrollFAB: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { scrolledToTop = true }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.15)))
                .padding(.trailing, 16)
                .padding(.bottom, isSelectionMode ? 80 : 20)
            }
        }
    }

    // MARK: - Toast

    private func showToast(_ m: String) {
        withAnimation(.easeInOut(duration: 0.2)) { actionToast = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.3)) { actionToast = nil }
        }
    }

    private func toastView(_ m: String) -> some View {
        Text(m)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Color.black.opacity(0.85))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.red.opacity(0.6), lineWidth: 1))
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
    }

    // MARK: - Stats & Filters

    private var statsHeader: some View {
        HStack(spacing: 0) {
            statItem(icon: "video.fill", value: "\(videoCount)", label: "Videos")
            divider
            statItem(icon: "camera.fill", value: "\(photoCount)", label: "FadShots")
            divider
            statItem(icon: "internaldrive", value: formattedTotalSize, label: "Used")
        }
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 28)
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 11)).foregroundColor(.red)
                Text(value).font(.system(size: 14, weight: .bold).monospacedDigit()).foregroundColor(.white)
            }
            Text(label).font(.system(size: 10, weight: .medium)).foregroundColor(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    private var videoCount: Int { filteredRecordings.filter { $0.isVideo }.count }
    private var photoCount: Int { filteredRecordings.filter { $0.isPhoto }.count }

    private var formattedTotalSize: String {
        ByteCountFormatter.string(
            fromByteCount: filteredRecordings.reduce(0) { $0 + $1.fileSize },
            countStyle: .file
        )
    }

    private var filterAndToolsRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sortedFilters, id: \.id) { chipView($0) }
                }
            }
            .mask(fadeMask)

            sortButton
            viewModeButton
        }
        .padding(.horizontal, 16)
    }

    private var fadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 20)

            Color.white

            LinearGradient(
                gradient: Gradient(colors: [.black, .clear]),
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 20)
        }
    }

    private var subFilterRow: some View {
        HStack(spacing: 8) {
            ForEach(CameraSubFilter.allCases) { sub in
                HStack(spacing: 4) {
                    Image(systemName: sub.icon).font(.system(size: 10))
                    Text(sub.rawValue).font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(cameraSubFilter == sub ? .white : .white.opacity(0.6))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(cameraSubFilter == sub ? Color.red.opacity(0.8) : Color.white.opacity(0.06))
                .clipShape(Capsule())
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { cameraSubFilter = sub }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var sortButton: some View {
        Menu {
            ForEach(SortOption.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { sortOption = option }
                } label: {
                    HStack {
                        Image(systemName: option.icon)
                        Text(option.rawValue)
                        if sortOption == option {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 32)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
    }

    private var viewModeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { viewMode = viewMode == .grid ? .list : .grid }
        } label: {
            Image(systemName: viewMode == .grid ? "rectangle.grid.1x2" : "square.grid.2x2")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 32)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var sortedFilters: [MediaFilter] {
        let counts = MediaFilter.allCases.map { ($0, countForFilter($0)) }
        return counts.sorted {
            if $0.0 == .all { return true }
            if $1.0 == .all { return false }
            return $0.1 > $1.1
        }.map { $0.0 }
    }

    private func countForFilter(_ f: MediaFilter) -> Int {
        viewModel.recordings.filter { f.matches($0) }.count
    }

    private func chipView(_ f: MediaFilter) -> some View {
        let count = countForFilter(f)
        let sel = selectedFilter == f
        return HStack(spacing: 6) {
            Image(systemName: f.icon).font(.system(size: 11, weight: .semibold))
            Text(f.rawValue).font(.system(size: 12, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(sel ? Color.white.opacity(0.25) : Color.red.opacity(0.3))
                .clipShape(Capsule())
        }
        .foregroundColor(sel ? .white : .white.opacity(0.7))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(sel ? Color.red : Color.white.opacity(0.06))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(sel ? Color.red : Color.white.opacity(0.1), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { selectedFilter = f } }
    }

    // MARK: - Content

    private var filteredRecordings: [Recording] {
        viewModel.recordings.filter {
            selectedFilter.matches($0) && cameraSubFilter.matches($0)
        }
    }

    private var sortedRecordings: [Recording] {
        switch sortOption {
        case .newest: return filteredRecordings.sorted { $0.date > $1.date }
        case .oldest: return filteredRecordings.sorted { $0.date < $1.date }
        case .largest: return filteredRecordings.sorted { $0.fileSize > $1.fileSize }
        case .smallest: return filteredRecordings.sorted { $0.fileSize < $1.fileSize }
        }
    }

    private var contentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    statsHeader.padding(.top, 4)
                    filterAndToolsRow
                    if selectedFilter != .all { subFilterRow }

                    ForEach(groupRecordingsByMonth().keys.sorted(by: >), id: \.self) { monthKey in
                        sectionView(monthKey)
                    }
                }
                .padding(.bottom, isSelectionMode ? 120 : 100)
                .background(GeometryReader { geometry in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: geometry.frame(in: .named("records-scroll")).minY
                    )
                })
            }
            .coordinateSpace(name: "records-scroll")
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                withAnimation(.easeInOut(duration: 0.2)) { scrolledToTop = offset > -100 }
            }
            .overlay(alignment: .trailing) { fastScrollThumb(proxy) }
        }
    }

    private func fastScrollThumb(_ proxy: ScrollViewProxy) -> some View {
        let months = groupRecordingsByMonth().keys.sorted(by: >)
        return VStack(spacing: 1) {
            ForEach(months, id: \.self) { month in
                Text(String(month.prefix(1)))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.red.opacity(0.6))
                    .frame(width: 16, height: 12)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let first = groupRecordingsByMonth()[month]?.first {
                            withAnimation { proxy.scrollTo(first.id, anchor: .top) }
                        }
                    }
            }
        }
        .padding(.trailing, 2)
        .padding(.top, 80)
    }

    private func sectionView(_ monthKey: String) -> some View {
        let items = groupRecordingsByMonth()[monthKey] ?? []
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(monthKey.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.red)
                    .tracking(1.2)
                Spacer()
                Text("\(items.count) items")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)

            if viewMode == .grid {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(items) { recording in
                        cardView(recording)
                    }
                }
                .padding(.horizontal, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { recording in
                        listRowView(recording)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func cardView(_ recording: Recording) -> some View {
        RecordingCard(
            recording: recording,
            isSelected: selectedIDs.contains(recording.id),
            isSelectionMode: isSelectionMode,
            onTap: {
                if isSelectionMode {
                    withAnimation(.easeInOut(duration: 0.15)) { toggleSelection(recording) }
                } else {
                    selectedRecording = recording
                }
            },
            onLongPress: {
                if !isSelectionMode {
                    withAnimation(.spring(response: 0.3)) {
                        isSelectionMode = true
                        selectedIDs.insert(recording.id)
                    }
                }
            },
            onOpen: { selectedRecording = recording },
            onDuplicate: { viewModel.duplicateRecording(recording); showToast("Duplicated") },
            onSaveCopy: {
                Task {
                    let ok = await viewModel.saveToGallery(recording, option: .copyOnly)
                    showToast(ok ? "Saved (copy)" : "Save failed")
                }
            },
            onSaveMove: {
                Task {
                    let ok = await viewModel.saveToGallery(recording, option: .move)
                    showToast(ok ? "Moved to Gallery" : "Save failed")
                }
            },
            onRename: {
                renameText = recording.url.deletingPathExtension().lastPathComponent
                recordingToRename = recording
            },
            onInfo: { infoRecording = recording },
            onDelete: {
                recordingPendingAction = recording
                confirmAlertType = .delete
                showConfirmAlert = true
            }
        )
    }

    private func listRowView(_ recording: Recording) -> some View {
        RecordingListRow(
            recording: recording,
            isSelected: selectedIDs.contains(recording.id),
            isSelectionMode: isSelectionMode,
            onTap: {
                if isSelectionMode {
                    withAnimation(.easeInOut(duration: 0.15)) { toggleSelection(recording) }
                } else {
                    selectedRecording = recording
                }
            },
            onLongPress: {
                if !isSelectionMode {
                    withAnimation(.spring(response: 0.3)) {
                        isSelectionMode = true
                        selectedIDs.insert(recording.id)
                    }
                }
            },
            onOpen: { selectedRecording = recording },
            onDuplicate: { viewModel.duplicateRecording(recording); showToast("Duplicated") },
            onSaveCopy: {
                Task {
                    let ok = await viewModel.saveToGallery(recording, option: .copyOnly)
                    showToast(ok ? "Saved (copy)" : "Save failed")
                }
            },
            onSaveMove: {
                Task {
                    let ok = await viewModel.saveToGallery(recording, option: .move)
                    showToast(ok ? "Moved to Gallery" : "Save failed")
                }
            },
            onRename: {
                renameText = recording.url.deletingPathExtension().lastPathComponent
                recordingToRename = recording
            },
            onInfo: { infoRecording = recording },
            onDelete: {
                recordingPendingAction = recording
                confirmAlertType = .delete
                showConfirmAlert = true
            }
        )
    }

    // MARK: - Selection

    private func toggleSelection(_ r: Recording) {
        if selectedIDs.contains(r.id) {
            selectedIDs.remove(r.id)
            if selectedIDs.isEmpty { isSelectionMode = false }
        } else {
            selectedIDs.insert(r.id)
        }
    }

    private func toggleSelectAll() {
        if selectedIDs.count == filteredRecordings.count {
            selectedIDs.removeAll()
        } else {
            selectedIDs = Set(filteredRecordings.map { $0.id })
        }
    }

    private func batchDelete() {
        for r in filteredRecordings where selectedIDs.contains(r.id) {
            viewModel.deleteRecording(r)
        }
        isSelectionMode = false
        selectedIDs.removeAll()
    }

    private func batchSaveToGallery(copyOnly: Bool) {
        let selected = filteredRecordings.filter { selectedIDs.contains($0.id) }
        Task {
            var ok = true
            for r in selected {
                let success = await viewModel.saveToGallery(r, option: copyOnly ? .copyOnly : .move)
                if !success { ok = false }
            }
            showToast(ok ? (copyOnly ? "Saved \(selected.count) files" : "Moved \(selected.count) files") : "Some files failed")
            isSelectionMode = false
            selectedIDs.removeAll()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("No Recordings Yet")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
            Text("Record a video or take a FadShot from the Home tab.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func groupRecordingsByMonth() -> [String: [Recording]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return Dictionary(grouping: sortedRecordings) { formatter.string(from: $0.date) }
    }
}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Info Sheet

struct FileInfoView: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss
    @State private var resolution: String?
    @State private var framerate: String?
    @State private var bitrate: String?
    @State private var photoResolution: String?
    @State private var copied = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    row("Name", recording.filename)
                    row("Type", recording.isVideo ? "Video" : "Photo")
                    row("Size", recording.formattedFileSize)
                    if recording.isVideo {
                        row("Duration", recording.formattedDuration)
                    }
                } header: { Text("File") }

                Section {
                    if let res = resolution ?? photoResolution {
                        row("Resolution", res)
                    }
                    if let fps = framerate {
                        row("Framerate", fps)
                    }
                    if let br = bitrate {
                        row("Bitrate", br)
                    }
                    row("Camera", recording.cameraPosition)
                } header: { Text("Details") }

                Section {
                    row("Date", relativeDate(recording.date))
                    row("Path", recording.url.path)
                } header: { Text("Info") }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("File Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        UIPasteboard.general.string = infoText
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                    } label: {
                        if copied {
                            Label("Copied", systemImage: "checkmark")
                        } else {
                            Label("Copy Info", systemImage: "doc.on.doc")
                        }
                    }
                }
            }
            .task { await loadMetadata() }
        }
    }

    private var infoText: String {
        var lines = [
            "Name: \(recording.filename)",
            "Type: \(recording.isVideo ? "Video" : "Photo")",
            "Size: \(recording.formattedFileSize)"
        ]
        if recording.isVideo { lines.append("Duration: \(recording.formattedDuration)") }
        if let res = resolution ?? photoResolution { lines.append("Resolution: \(res)") }
        if let fps = framerate { lines.append("Framerate: \(fps)") }
        if let br = bitrate { lines.append("Bitrate: \(br)") }
        lines.append("Camera: \(recording.cameraPosition)")
        lines.append("Date: \(recording.formattedDate)")
        lines.append("Path: \(recording.url.path)")
        return lines.joined(separator: "\n")
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .frame(width: 90, alignment: .leading)
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func loadMetadata() async {
        if recording.isVideo {
            let asset = AVAsset(url: recording.url)
            do {
                let vidTrack = try await asset.loadTracks(withMediaType: .video).first
                if let track = vidTrack {
                    let size = try await track.load(.naturalSize)
                    resolution = "\(Int(size.width)) x \(Int(size.height))"
                    let fps = try await track.load(.nominalFrameRate)
                    framerate = String(format: "%.1f fps", fps)
                    let br = try await track.load(.estimatedDataRate)
                    bitrate = br > 1_000_000
                        ? String(format: "%.1f Mbps", br / 1_000_000)
                        : (br > 1_000 ? String(format: "%.1f Kbps", br / 1_000) : "\(Int(br)) bps")
                }
            } catch {
                resolution = nil; framerate = nil; bitrate = nil
            }
        } else if let img = UIImage(contentsOfFile: recording.url.path) {
            photoResolution = "\(Int(img.size.width)) x \(Int(img.size.height))"
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 0 { return "Just now" }
        let seconds = Int(interval)
        if seconds < 60 { return "Just now" }
        let minutes = seconds / 60
        if minutes == 1 { return "1 minute ago" }
        if minutes < 60 { return "\(minutes) minutes ago" }
        let hours = minutes / 60
        if hours == 1 { return "1 hour ago" }
        if hours < 24 { return "\(hours) hours ago" }
        let days = hours / 24
        if days == 1 { return "1 day ago" }
        if days < 7 { return "\(days) days ago" }
        let weeks = days / 7
        if weeks == 1 { return "1 week ago" }
        if weeks < 5 { return "\(weeks) weeks ago" }
        let months = days / 30
        if months == 1 { return "1 month ago" }
        if months < 12 { return "\(months) months ago" }
        return recording.formattedDate
    }
}

// MARK: - Card Components

struct RecordingCard: View {
    let recording: Recording
    let isSelected: Bool
    let isSelectionMode: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onOpen: () -> Void
    let onDuplicate: () -> Void
    let onSaveCopy: () -> Void
    let onSaveMove: () -> Void
    let onRename: () -> Void
    let onInfo: () -> Void
    let onDelete: () -> Void
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(maxWidth: .infinity).frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)
                    .onLongPressGesture(perform: onLongPress)

                VStack {
                    HStack(alignment: .top) {
                        topLeftBadge
                        Spacer()
                        if !recording.hasBeenViewed && !isSelectionMode { newBadge }
                    }
                    Spacer()
                }
                .padding(6)

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        bottomLeftBadge
                        Spacer()
                        if recording.isVideo { durationBadge }
                    }
                }
                .padding(6)

                if isSelectionMode { selectionOverlay }
            }

            Text(recording.filename)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            sizeRow

            if !isSelectionMode {
                HStack {
                    HStack(spacing: 3) {
                        Image(systemName: "clock").font(.system(size: 9))
                        Text(relativeDate()).font(.system(size: 9))
                    }
                    Spacer()
                    menuButton
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.red : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        )
        .task { thumbnail = await ThumbnailService.shared.thumbnail(for: recording.url) }
    }

    private var selectionOverlay: some View {
        VStack {
            HStack {
                Spacer()
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.red : Color.white.opacity(0.2))
                        .frame(width: 28, height: 28)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Circle()
                            .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                    }
                }
            }
            Spacer()
        }
        .padding(6)
    }

    private var newBadge: some View {
        Text("NEW")
            .font(.system(size: 9, weight: .heavy))
            .foregroundColor(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.green)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var durationBadge: some View {
        Text(recording.formattedDuration)
            .font(.system(size: 10, design: .monospaced).weight(.bold))
            .foregroundColor(.white)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color.black.opacity(0.65))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder
    private var topLeftBadge: some View {
        let label = recording.isVideo ? "VIDEO" : "FADSHOT"
        let bg: Color = recording.isVideo ? .red : .orange
        HStack(spacing: 3) {
            Image(systemName: recording.isVideo ? "video.fill" : "camera.fill")
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 8, weight: .heavy))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(bg.opacity(0.85))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var bottomLeftBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: recording.cameraPosition == "Front" ? "person.crop.square" : "camera")
                .font(.system(size: 9))
            Text(recording.cameraPosition)
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
    }

    private var sizeRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.fill").font(.system(size: 9))
            Text(recording.formattedFileSize).font(.system(size: 9))
        }
        .foregroundColor(.white.opacity(0.45))
    }

    private var menuButton: some View {
        Menu {
            Button { onOpen() } label: { Label("Open", systemImage: "play.rectangle.fill") }
            Button { onInfo() } label: { Label("Info", systemImage: "info.circle") }
            Button { onDuplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Menu {
                Button { onSaveCopy() } label: {
                    Label("Copy to Gallery", systemImage: "doc.on.doc.fill")
                }
                Button { onSaveMove() } label: {
                    Label("Move to Gallery", systemImage: "tray.and.arrow.right.fill")
                }
            } label: { Label("Save to Gallery", systemImage: "photo.on.rectangle.angled") }
            Button { onRename() } label: { Label("Rename", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .rotationEffect(.degrees(90))
        }
    }

    private func relativeDate() -> String {
        let hours = Int(Date().timeIntervalSince(recording.date) / 3600)
        if hours < 1 { return "Just now" }
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        let weeks = days / 7
        if weeks < 4 { return "\(weeks)w ago" }
        return DateFormatter().then { $0.dateFormat = "MMM d" }.string(from: recording.date)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let t = thumbnail {
            Image(uiImage: t).resizable().aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Image(systemName: recording.isVideo ? "play.rectangle.fill" : "photo.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                )
        }
    }
}

struct RecordingListRow: View {
    let recording: Recording
    let isSelected: Bool
    let isSelectionMode: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onOpen: () -> Void
    let onDuplicate: () -> Void
    let onSaveCopy: () -> Void
    let onSaveMove: () -> Void
    let onRename: () -> Void
    let onInfo: () -> Void
    let onDelete: () -> Void
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(width: 80, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)
                    .onLongPressGesture(perform: onLongPress)

                if isSelectionMode {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.red : Color.white.opacity(0.2))
                            .frame(width: 22, height: 22)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            Circle()
                                .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                                .frame(width: 18, height: 18)
                        }
                    }
                    .padding(4)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(recording.filename)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !recording.hasBeenViewed && !isSelectionMode {
                        Text("NEW")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.green)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.fill").font(.system(size: 9))
                        Text(recording.formattedFileSize).font(.system(size: 9))
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "clock").font(.system(size: 9))
                        Text(relativeDate()).font(.system(size: 9))
                    }
                    if recording.isVideo {
                        Text(recording.formattedDuration)
                            .font(.system(size: 9, design: .monospaced).weight(.bold))
                    }
                }
                .foregroundColor(.white.opacity(0.5))
            }

            Spacer(minLength: 0)
            if !isSelectionMode { menuButton }
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.red : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        )
        .task { thumbnail = await ThumbnailService.shared.thumbnail(for: recording.url) }
    }

    private var menuButton: some View {
        Menu {
            Button { onOpen() } label: { Label("Open", systemImage: "play.rectangle.fill") }
            Button { onInfo() } label: { Label("Info", systemImage: "info.circle") }
            Button { onDuplicate() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Menu {
                Button { onSaveCopy() } label: {
                    Label("Copy to Gallery", systemImage: "doc.on.doc.fill")
                }
                Button { onSaveMove() } label: {
                    Label("Move to Gallery", systemImage: "tray.and.arrow.right.fill")
                }
            } label: { Label("Save to Gallery", systemImage: "photo.on.rectangle.angled") }
            Button { onRename() } label: { Label("Rename", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .rotationEffect(.degrees(90))
        }
    }

    private func relativeDate() -> String {
        let hours = Int(Date().timeIntervalSince(recording.date) / 3600)
        if hours < 1 { return "Just now" }
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        let weeks = days / 7
        if weeks < 4 { return "\(weeks)w ago" }
        return DateFormatter().then { $0.dateFormat = "MMM d" }.string(from: recording.date)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let t = thumbnail {
            Image(uiImage: t).resizable().aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Image(systemName: recording.isVideo ? "play.rectangle.fill" : "photo.fill")
                        .foregroundColor(.gray)
                )
        }
    }
}

extension DateFormatter {
    func then(_ block: (DateFormatter) -> Void) -> DateFormatter {
        block(self)
        return self
    }
}

struct PhotoViewerView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                if let img = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("Failed to load image")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview { RecordsView() }
