import SwiftUI

struct LinkPreviewView: View {
    let url: URL
    let title: String?
    @Environment(\.dismiss) var dismiss
    @State private var copied = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)

                Image(systemName: "safari")
                    .font(.system(size: 48))
                    .foregroundColor(.red.opacity(0.7))

                if let title = title {
                    Text(title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }

                Text(url.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(10)
                    .padding(.horizontal, 24)

                HStack(spacing: 16) {
                    Button {
                        UIPasteboard.general.string = url.absoluteString
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    } label: {
                        Label(copied ? "Copied" : "Copy Link", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(10)
                    }
                    .foregroundColor(.white)

                    Button {
                        UIApplication.shared.open(url)
                        dismiss()
                    } label: {
                        Label("Open", systemImage: "arrow.up.right")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(10)
                    }
                    .foregroundColor(.white)
                }
                .padding(.horizontal, 24)

                Spacer()
            }
            .navigationTitle("External Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

extension View {
    func linkSheet(url: URL, title: String? = nil, isPresented: Binding<Bool>) -> some View {
        self.sheet(isPresented: isPresented) {
            LinkPreviewView(url: url, title: title)
        }
    }
}
