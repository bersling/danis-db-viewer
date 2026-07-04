// Move the mouse cursor to screen coords. Usage: swift movemouse.swift X Y
import CoreGraphics
import Foundation
let x = Double(CommandLine.arguments[1]) ?? 0
let y = Double(CommandLine.arguments[2]) ?? 0
let pt = CGPoint(x: x, y: y)
CGWarpMouseCursorPosition(pt)
// A move event helps AppKit register the hover for tooltips.
if let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left) {
    e.post(tap: .cghidEventTap)
}
