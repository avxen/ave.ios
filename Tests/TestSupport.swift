// TestSupport.swift
// Test scaffolding: fixture loading with Python-int/float distinction.

import Foundation
import XCTest
@testable import PrivateJudgesWorkspace

final class TestAssetMarker {}

/// JSON value tree parsed from fixtures, preserving the int/float distinction
/// the Python canonical serializer depends on (12 vs 12.0).
enum JSONValue {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    static func parse(_ data: Data) throws -> JSONValue {
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return convert(obj)
    }

    static func convert(_ any: Any) -> JSONValue {
        switch any {
        case is NSNull:
            return .null
        case let n as NSNumber:
            let type = String(cString: n.objCType)
            switch type {
            case "c": return .bool(n.boolValue)
            case "d": return .double(n.doubleValue)
            default: return .int(n.intValue)
            }
        case let s as String:
            return .string(s)
        case let a as [Any]:
            return .array(a.map(convert))
        case let o as [String: Any]:
            return .object(o.mapValues(convert))
        default:
            return .null
        }
    }

    var canonical: CanonicalValue {
        switch self {
        case .null: return .null
        case .bool(let b): return .bool(b)
        case .int(let i): return .int(i)
        case .double(let d): return .double(d)
        case .string(let s): return .string(s)
        case .array(let items): return .array(items.map { $0.canonical })
        case .object(let dict):
            return .object(dict.map { ($0.key, $0.value.canonical) })
        }
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let dict) = self { return dict }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let items) = self { return items }
        return nil
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    var intValue: Int? {
        if case .int(let i) = self { return i }
        return nil
    }
}

enum Fixtures {
    static func fixtureData(_ name: String) throws -> Data {
        let bundle = Bundle(for: TestAssetMarker.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: nil),
                                "missing fixture \(name)")
        return try Data(contentsOf: url)
    }

    static func referenceVectors() throws -> [String: JSONValue] {
        let value = try JSONValue.parse(try fixtureData("reference_vectors.json"))
        return value.objectValue ?? [:]
    }
}
