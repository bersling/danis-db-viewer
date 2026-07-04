// Prints the CGWindowID of the frontmost window of the named app.
// Usage: swift scripts/windowid.swift DanisDBViewer
import CoreGraphics
import Foundation

let target = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "DanisDBViewer"
guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}
for info in list {
    guard let owner = info[kCGWindowOwnerName as String] as? String, owner == target,
          let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
          let id = info[kCGWindowNumber as String] as? Int else { continue }
    print(id)
    exit(0)
}
exit(2)
