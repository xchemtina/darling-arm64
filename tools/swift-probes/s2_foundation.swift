// Probe 2: import Foundation -> exercises the libswiftFoundation SDK overlay.
import Foundation
let s = NSString(string: "abc").lowercased
let u = UUID().uuidString.count
print("SWIFT_FOUNDATION_OK \(s) \(u > 0)")
