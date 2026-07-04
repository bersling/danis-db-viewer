import AppKit
import SwiftUI

/// Darcula-inspired palette matching IntelliJ's Database tool window.
enum Theme {
    static let toolWindowBackground = Color(red: 0.16, green: 0.16, blue: 0.17)   // #2b2b2d
    static let editorBackground = Color(red: 0.12, green: 0.12, blue: 0.13)       // #1e1f22
    static let panelBackground = Color(red: 0.19, green: 0.19, blue: 0.20)
    static let selection = Color(red: 0.15, green: 0.28, blue: 0.48)
    static let border = Color(white: 0.28)
    static let text = Color(red: 0.86, green: 0.86, blue: 0.87)
    static let dimText = Color(white: 0.55)
    static let accent = Color(red: 0.21, green: 0.48, blue: 0.85)

    // Grid
    static let gridStripe = Color(white: 1).opacity(0.03)
    static let gridLine = Color(white: 0.24)
    static let cellModified = Color(red: 0.29, green: 0.35, blue: 0.20)   // staged update
    static let cellInserted = Color(red: 0.17, green: 0.31, blue: 0.19)   // staged insert
    static let cellDeleted = Color(red: 0.38, green: 0.19, blue: 0.19)    // staged delete
    static let nullText = Color(white: 0.45)

    // SQL highlighting (Darcula)
    static let sqlKeyword = NSColor(red: 0.80, green: 0.47, blue: 0.20, alpha: 1)   // orange
    static let sqlString = NSColor(red: 0.41, green: 0.53, blue: 0.35, alpha: 1)    // green
    static let sqlNumber = NSColor(red: 0.41, green: 0.60, blue: 0.75, alpha: 1)    // blue
    static let sqlComment = NSColor(white: 0.50, alpha: 1)
    static let sqlDefault = NSColor(red: 0.86, green: 0.86, blue: 0.87, alpha: 1)
    static let editorNSBackground = NSColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1)

    static let monoFont = Font.system(size: 12, design: .monospaced)
    static let uiFont = Font.system(size: 12.5)
    static let editorNSFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
}

/// Icon buttons with a real hit target: pads the glyph to at least 26×24 pt
/// and makes the whole area clickable, with subtle pressed feedback.
struct IconButtonStyle: ButtonStyle {
    var minWidth: CGFloat = 26
    var minHeight: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: minWidth, minHeight: minHeight)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isPressed ? Color.white.opacity(0.12) : .clear)
            )
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
}

/// Object-type icons like IntelliJ's.
enum ObjectIcon {
    static func dataSource(_ kind: DBKind) -> String { "cylinder.split.1x2" }
    static let schema = "square.stack.3d.up"
    static let table = "tablecells"
    static let view = "eye"
    static let column = "circle.grid.2x1"
    static let index = "arrow.up.arrow.down"
    static let foreignKey = "key"
    static let primaryKey = "key.fill"
    static let console = "terminal"
}
