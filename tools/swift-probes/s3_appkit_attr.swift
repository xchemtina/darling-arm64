// Probe 3: the exact failing symbol family — AttributeScopes.AppKitAttributes.
import Foundation
import AppKit
var c = AttributeContainer()
c[AttributeScopes.AppKitAttributes.ForegroundColorAttribute.self] = NSColor.black
let a = AttributedString("x", attributes: c)
print("SWIFT_APPKIT_ATTR_OK \(a.characters.count)")
