/// Parses space-separated hex bytes, e.g. "0b 84 01".
func hex(_ s: String) -> [UInt8] {
    s.split(separator: " ").map { UInt8($0, radix: 16)! }
}
