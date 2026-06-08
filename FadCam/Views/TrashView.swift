import SwiftUI
import AVFoundation

struct TrashView: View {
    @StateObject private var vm = TrashViewModel()
    @AppStorage("FadCam.trashAutoDeleteSeconds") private var autoDeleteSeconds: Int = 2592000
    @State private var showEmptyConfirm = false
    @State private var itemToDelete: TrashItem?
    @State private var showDeleteConfirm = false
    @State private var permanentDeleteText = ""
    @State private var actionToast: String?
    @State private var isSelectionMode = false
    @State private var selectedIDs = Set<String>()

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                if vm.isLoading {
                    ProgressView().tint(.red)
                } else if vm.items.isEmpty {
                    emptyState
                } else {
                    contentView
                }

                if isSelectionMode {
                    selectionBottomBar
                }

                if let toast = actionToast {
                    toastView(toast)
                }
            }
            .navigationTitle(isSelectionMode ? selectionTitle : "Trash")
            .navigationBarTitleDisplayMode(isSelectionMode ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isSelectionMode {
                        Button {
                            withAnimation { isSelectionMode = false; selectedIDs.removeAll() }
                        } label: {
                            Text("Cancel").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        if isSelectionMode {
                            Button { toggleSelectAll() } label: {
                                Text(selectedIDs.count == vm.items.count ? "Deselect" : "Select All")
                                    .font(.system(size: 13)).foregroundColor(.red)
                            }
                            Button {
                                showEmptyConfirm = true
                            } label: {
                                Text("Delete").font(.system(size: 13, weight: .semibold)).foregroundColor(.red)
                            }
                        } else {
                            Button { vm.loadItems() } label: {
                                Image(systemName: "arrow.clockwise").font(.system(size: 14)).foregroundColor(.red)
                            }
                            if !vm.items.isEmpty {
                                Button(role: .destructive) { showEmptyConfirm = true } label: {
                                    Text("Empty").font(.system(size: 13, weight: .semibold)).foregroundColor(.red)
                                }
                            }
                        }
                    }
                }
            }
            .refreshable { vm.loadItems() }
            .onAppear { vm.loadItems() }
            .alert("Empty Trash", isPresented: $showEmptyConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive) {
                    if isSelectionMode {
                        batchDelete()
                        withAnimation { isSelectionMode = false; selectedIDs.removeAll() }
                    } else {
                        vm.emptyTrash()
                    }
                    showToast("Trash emptied")
                }
            } message: {
                if isSelectionMode {
                    Text("Permanently delete \(selectedIDs.count) selected item(s)? This cannot be undone.")
                } else {
                    Text("Permanently delete all items in Trash? This cannot be undone.")
                }
            }
            .alert("Delete Permanently?", isPresented: $showDeleteConfirm) {
                TextField("Type DELETE to confirm", text: $permanentDeleteText)
                Button("Cancel", role: .cancel) {
                    itemToDelete = nil
                    permanentDeleteText = ""
                }
                Button("Delete", role: .destructive) {
                    if let item = itemToDelete {
                        vm.permanentlyDelete(item)
                        showToast("Deleted permanently")
                    }
                    itemToDelete = nil
                    permanentDeleteText = ""
                }
                .disabled(permanentDeleteText != "DELETE")
            } message: {
                Text("This will permanently delete the file. Type DELETE to confirm.")
            }
        }
        .navigationViewStyle(.stack)
    }

    private var selectionTitle: String {
        let sel = vm.items.filter { selectedIDs.contains($0.id) }
        let totalSize = ByteCountFormatter.string(fromByteCount: sel.reduce(0) { $0 + $1.fileSize }, countStyle: .file)
        return "\(selectedIDs.count) selected · \(totalSize)"
    }

    private var selectionBottomBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 0) {
                Button {
                    batchRestore()
                    showToast("Restored \(selectedIDs.count) items")
                    withAnimation { isSelectionMode = false; selectedIDs.removeAll() }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 16))
                        Text("Restore").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                Divider().frame(height: 28).background(Color.white.opacity(0.15))
                Button(role: .destructive) {
                    showEmptyConfirm = true
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

    private func showToast(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) { actionToast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.3)) { actionToast = nil }
        }
    }

    private func toastView(_ message: String) -> some View {
        Text(message)
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

    private var statsHeader: some View {
        HStack(spacing: 0) {
            statItem(icon: "trash", value: "\(vm.items.count)", label: "Items")
            divider
            statItem(icon: "internaldrive", value: formattedTotalSize, label: "Size")
            divider
            autoDeleteStat
        }
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var autoDeleteStat: some View {
        Menu {
            ForEach(TrashAutoDeleteOption.allCases) { option in
                Button {
                    autoDeleteSeconds = option.seconds
                    vm.loadItems()
                } label: {
                    HStack {
                        Text(option.label)
                        if autoDeleteSeconds == option.seconds {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            autoDeleteLabelView
        }
    }

    private var autoDeleteLabelView: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                Text(autoDeleteShortLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.4))
            }
            Text("Auto-delete")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
        }
        .padding(8)
        .contentShape(Rectangle())
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 28)
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                Text(value)
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundColor(.white)
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    private var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: vm.totalBytes, countStyle: .file)
    }

    private var autoDeleteShortLabel: String {
        if autoDeleteSeconds < 0 { return "Never" }
        let days = autoDeleteSeconds / 86400
        if days >= 1 { return "\(days)d" }
        let hours = autoDeleteSeconds / 3600
        if hours >= 1 { return "\(hours)h" }
        return "Now"
    }

    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statsHeader.padding(.top, 4)

                let grouped = groupByMonth()
                ForEach(grouped.keys.sorted(by: >), id: \.self) { monthKey in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(monthKey.uppercased())
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundColor(.red)
                                .tracking(1.2)
                            Spacer()
                            Text("\(grouped[monthKey]?.count ?? 0) items")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 16)

                        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(grouped[monthKey] ?? []) { item in
                                trashCard(item)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.bottom, isSelectionMode ? 120 : 100)
        }
    }

    private func trashCard(_ item: TrashItem) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                thumbnailView(for: item)
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelectionMode {
                            toggleSelection(item)
                        }
                    }
                    .onLongPressGesture {
                        if !isSelectionMode {
                            withAnimation(.spring(response: 0.3)) {
                                isSelectionMode = true
                                selectedIDs.insert(item.id)
                            }
                        }
                    }

                if isSelectionMode {
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

                VStack {
                    HStack(alignment: .top) {
                        topLeftBadge(item)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(6)

                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        bottomLeftBadge(item)
                        Spacer()
                        if item.isVideo {
                            Text(item.formattedDuration)
                                .font(.system(size: 10, design: .monospaced).weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.black.opacity(0.65))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
                .padding(6)
            }

            Text(item.filename)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Image(systemName: "doc.fill").font(.system(size: 9))
                Text(item.formattedFileSize).font(.system(size: 9))
            }
            .foregroundColor(.white.opacity(0.45))

            HStack {
                HStack(spacing: 3) {
                    Image(systemName: "timer").font(.system(size: 9))
                    Text(timeRemaining(for: item)).font(.system(size: 9))
                }
                .foregroundColor(timeRemainingColor(for: item))
                Spacer()
                if !isSelectionMode {
                    menuButton(for: item)
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
    }

    private func toggleSelection(_ item: TrashItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
            if selectedIDs.isEmpty { isSelectionMode = false }
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private func toggleSelectAll() {
        if selectedIDs.count == vm.items.count {
            selectedIDs.removeAll()
        } else {
            selectedIDs = Set(vm.items.map { $0.id })
        }
    }

    private func batchRestore() {
        for item in vm.items where selectedIDs.contains(item.id) {
            vm.restoreItem(item)
        }
    }

    private func batchDelete() {
        for item in vm.items where selectedIDs.contains(item.id) {
            vm.permanentlyDelete(item)
        }
    }

    private func timeRemaining(for item: TrashItem) -> String {
        let autoSeconds = autoDeleteSeconds
        guard autoSeconds >= 0 else { return "Never" }
        let deleteAt = item.deletedAt.addingTimeInterval(TimeInterval(autoSeconds))
        let remaining = deleteAt.timeIntervalSinceNow
        if remaining <= 0 { return "Expiring" }
        if remaining < 3600 { return "\(Int(remaining / 60))m left" }
        if remaining < 86400 { return "\(Int(remaining / 3600))h left" }
        return "\(Int(remaining / 86400))d left"
    }

    private func timeRemainingColor(for item: TrashItem) -> Color {
        let autoSeconds = autoDeleteSeconds
        guard autoSeconds >= 0 else { return .white.opacity(0.45) }
        let deleteAt = item.deletedAt.addingTimeInterval(TimeInterval(autoSeconds))
        let remaining = deleteAt.timeIntervalSinceNow
        if remaining <= 0 { return .red.opacity(0.8) }
        if remaining < 86400 { return .orange.opacity(0.7) }
        return .white.opacity(0.45)
    }

    private func menuButton(for item: TrashItem) -> some View {
        Menu {
            Button {
                vm.restoreItem(item)
                showToast("Restored")
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            Divider()
            Button(role: .destructive) {
                itemToDelete = item
                permanentDeleteText = ""
                showDeleteConfirm = true
            } label: {
                Label("Delete Permanently", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .rotationEffect(.degrees(90))
        }
    }

    private func topLeftBadge(_ item: TrashItem) -> some View {
        let label = item.isVideo ? "VIDEO" : "FADSHOT"
        let color: Color = item.isVideo ? .red : .orange
        return HStack(spacing: 3) {
            Image(systemName: item.isVideo ? "video.fill" : "camera.fill")
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 8, weight: .heavy))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(color.opacity(0.85))
        .clipShape(Capsule())
    }

    private func bottomLeftBadge(_ item: TrashItem) -> some View {
        HStack(spacing: 3) {
            Image(systemName: item.cameraPosition == "Front" ? "person.crop.square" : "camera")
                .font(.system(size: 9))
            Text(item.cameraPosition)
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(Color.black.opacity(0.6))
        .clipShape(Capsule())
    }

    private func thumbnailView(for item: TrashItem) -> some View {
        let trashURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FadCam/Trash")
            .appendingPathComponent(item.trashFilename)
        return AsyncThumbnailView(url: trashURL, isVideo: item.isVideo)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "trash.slash")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("Trash is Empty")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
            Text("Deleted files appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func groupByMonth() -> [String: [TrashItem]] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return Dictionary(grouping: vm.items) { formatter.string(from: $0.deletedAt) }
    }
}

private struct AsyncThumbnailView: View {
    let url: URL
    let isVideo: Bool
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let t = thumbnail {
                Image(uiImage: t)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: isVideo ? "play.rectangle.fill" : "photo.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    )
            }
        }
        .task { thumbnail = await ThumbnailService.shared.thumbnail(for: url) }
    }
}
