import SwiftUI

/// Backward-compatible view modifiers that use newer APIs on iOS 17+
/// while maintaining deployment target compatibility with iOS 15.6.
extension View {

    /// onChange that silences the iOS 17 deprecation warning by using the
    /// newer two-parameter closure on iOS 17+ and the legacy form on older OS.
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, _ action: @escaping (V) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { _, newValue in action(newValue) }
        } else {
            self.onChange(of: value, perform: action)
        }
    }
}

// NOTE: NavigationLink(isActive:) deprecation in SettingsView
// cannot be resolved while targeting iOS 15.6 because NavigationStack
// (iOS 16+) is not available. The deprecation warning is harmless —
// the API still functions correctly and the archive succeeds.

