// Probe 1: pure Swift, no SDK overlay imports -> exercises libswiftCore only.
let xs = [3, 1, 2].sorted()
print("SWIFT_CORE_OK \(xs)")
