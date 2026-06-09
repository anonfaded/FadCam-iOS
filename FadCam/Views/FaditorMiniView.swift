import SwiftUI

/// Placeholder screen for the upcoming Faditor Mini video editor.
struct FaditorMiniView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "film.stack")
                    .font(.system(size: 56))
                    .foregroundStyle(
                        LinearGradient(colors: [.red, .orange],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )

                Text("Faditor Mini")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [.red, .orange],
                                       startPoint: .leading,
                                       endPoint: .trailing)
                    )

                Text("Video Editor — Coming Soon")
                    .font(.title3)
                    .foregroundColor(.secondary)

                Text("Trim, merge, and enhance your recordings\nwith a quick built-in editor.")
                    .font(.subheadline)
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()
            }
        }
        .navigationViewStyle(.stack)
    }
}

#if DEBUG
struct FaditorMiniView_Previews: PreviewProvider {
    static var previews: some View {
        FaditorMiniView()
            .preferredColorScheme(.dark)
    }
}
#endif
