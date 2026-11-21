// CanonicalJSON.swift
// Private Judges Workspace - canonical JSON serialization and hashing.
//
// Byte-for-byte parity with the Python reference implementation
// (engine/coordinate_engine.py: canonical_json):
//   json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
//
// Rules reproduced here:
//   - object keys sorted by unicode code point
//   - compact separators (no whitespace)
//   - strings: only `"` `\` and control characters are escaped
//     (\b \t \n \f \r, other < 0x20 as \uXXXX lowercase); "/" is NOT escaped;
//     non-ASCII is emitted as raw UTF-8
//   - integers as decimal integers; doubles via shortest round-trip
//     representation (Python repr semantics: 12.0 -> "12.0")
//
// This module is the ONLY serialization path for record hashes, assessment
// hashes, audit entry hashes and exported interchange files.

import Foundation
import CryptoKit

/// A dynamically typed value that maps 1:1 onto Python JSON values,
/// preserving the Int/Double distinction (Python int vs float).
enum CanonicalValue {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([CanonicalValue])
    case object([(String, CanonicalValue)])
}

enum CanonicalJSON {

    /// Canonical JSON string (see module documentation).
    static func string(_ value: CanonicalValue) -> String {
        switch value {
        case .null:
            return "null"
        case .bool(let b):
            return b ? "true" : "false"
        case .int(let i):
            return String(i)
        case .double(let d):
            precondition(d.isFinite, "canonical JSON forbids NaN/Infinity")
            return doubleRepr(d)
        case .string(let s):
            return escapedString(s)
        case .array(let items):
            return "[" + items.map(string).joined(separator: ",") + "]"
        case .object(let pairs):
            let sorted = pairs.sorted { $0.0 < $1.0 }
            let body = sorted.map { "\(escapedString($0.0)):\(string($0.1))" }
                .joined(separator: ",")
            return "{" + body + "}"
        }
    }

    /// SHA-256 hex digest of the canonical serialization.
    static func hash(_ value: CanonicalValue) -> String {
        CoordinateEngine.sha256Hex(Data(string(value).utf8))
    }

    /// Python repr() semantics for finite doubles: shortest string that
    /// round-trips; integral values keep a trailing ".0".
    static func doubleRepr(_ d: Double) -> String {
        if d == d.rounded(.towardZero) && abs(d) < 1e16 {
            // Integral value: ensure the ".0" suffix matches Python repr.
            let s = String(d)
            return s.contains(".") || s.contains("e") || s.contains("E") ? s : s + ".0"
        }
        return String(d)
    }

    private static func escapedString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += "\\u" + String(format: "%04x", scalar.value)
                } else {
                    out += String(scalar) // raw UTF-8, matches ensure_ascii=False
                }
            }
        }
        return out + "\""
    }
}
