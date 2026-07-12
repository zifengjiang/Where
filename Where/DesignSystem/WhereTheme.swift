import SwiftUI

enum WhereTheme {
    static let canvas = Color("WhereCanvas")
    static let surface = Color("WhereSurface")
    static let ink = Color("WhereInk")
    static let orange = Color("WhereOrange")
    static let pin = Color("WherePin")
    static let paper = Color("WherePaper")
    static let pagePadding: CGFloat = 16
    static let cardRadius: CGFloat = 20
}

struct WhereGlassHUD<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder let content: Content

    @ViewBuilder
    var body: some View {
        if reduceTransparency {
            content.padding(14).background(
                RoundedRectangle(cornerRadius: 16).fill(WhereTheme.surface)
                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(WhereTheme.ink.opacity(0.18)) }
            )
        } else {
            content.padding(14).glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }
}
