import SwiftUI
import AVKit

struct RecordsView: View {
    @StateObject private var viewModel = RecordsViewModel()
    @State private var selectedRecording: Recording?
    @State private var recordingToDelete: Recording?

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.red)
                } else if viewModel.recordings.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No Recordings Yet")
                            .font(.title2)
                            .foregroundColor(.primary)
                        Text("Record your first video from the Home tab.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    List {
                        ForEach(viewModel.recordings) { recording in
                            RecordingRow(recording: recording)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedRecording = recording
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        recordingToDelete = recording
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Recordings")
            .refreshable {
                viewModel.loadRecordings()
            }
            .onAppear {
                viewModel.loadRecordings()
            }
            .sheet(item: $selectedRecording) { recording in
                VideoPlayerView(url: recording.url)
            }
            .alert("Delete Recording", isPresented: .constant(recordingToDelete != nil)) {
                Button("Cancel", role: .cancel) {
                    recordingToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let recording = recordingToDelete {
                        viewModel.deleteRecording(recording)
                    }
                    recordingToDelete = nil
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }
}

struct RecordingRow: View {
    let recording: Recording
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView
                .frame(width: 80, height: 60)
                .cornerRadius(8)
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.filename)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 12) {
                    Text(recording.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(recording.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(recording.formattedFileSize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .task {
            thumbnail = await ThumbnailService.shared.thumbnail(for: recording.url)
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail = thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .overlay(
                    Image(systemName: "play.rectangle.fill")
                        .font(.title3)
                        .foregroundColor(.gray)
                )
        }
    }
}

#Preview {
    RecordsView()
}
