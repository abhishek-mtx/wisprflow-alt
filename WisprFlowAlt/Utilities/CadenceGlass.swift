import SwiftUI

extension View {
    /// macOS 26 Liquid Glass on a capsule (Flow Bar, round controls).
    func cadenceGlassCapsule() -> some View {
        glassEffect(.regular, in: Capsule())
    }

    /// macOS 26 Liquid Glass on a continuous rounded rect (cards).
    func cadenceGlassCard(cornerRadius: CGFloat = 16) -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
