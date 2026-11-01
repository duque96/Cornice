import Foundation

// MARK: - Values

/// A setting value. One JSON scalar, so widgets can read it from Swift or JS.
public enum SettingValue: Codable, Sendable, Equatable {
    case bool(Bool)
    case number(Double)
    case string(String)

    public var jsonObject: Any {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

// MARK: - Descriptor

/// A field a widget wants to expose in Options. The host renders the form and
/// stores the values; the widget only reads them.
public struct WidgetSetting: Sendable, Equatable, Identifiable {
    public struct Option: Sendable, Equatable {
        public let value: String
        public let title: String

        public init(value: String, title: String) {
            self.value = value
            self.title = title
        }
    }

    public enum Kind: Sendable, Equatable {
        case toggle
        case number(min: Double, max: Double, step: Double)
        case text(placeholder: String?)
        case select(options: [Option])
    }

    public let id: String
    public let title: String
    public let description: String?
    public let kind: Kind
    public let defaultValue: SettingValue

    public init(
        id: String,
        title: String,
        description: String? = nil,
        kind: Kind,
        defaultValue: SettingValue
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.kind = kind
        self.defaultValue = defaultValue
    }
}

// MARK: - Runtime values

/// The resolved values handed to a widget: defaults merged with what the user saved.
public struct WidgetSettings: Sendable, Equatable {
    public let values: [String: SettingValue]

    public init(values: [String: SettingValue] = [:]) {
        self.values = values
    }

    public subscript(id: String) -> SettingValue? { values[id] }

    public func bool(_ id: String, default fallback: Bool = false) -> Bool {
        values[id]?.boolValue ?? fallback
    }

    public func number(_ id: String, default fallback: Double) -> Double {
        values[id]?.numberValue ?? fallback
    }

    public func string(_ id: String, default fallback: String = "") -> String {
        values[id]?.stringValue ?? fallback
    }
}
