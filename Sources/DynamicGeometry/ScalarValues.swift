import Foundation

/// Failures raised while creating or validating scalar inputs.
public enum ScalarValidationError: Error, Equatable, LocalizedError, Sendable {
  case nonFiniteConstant
  case emptyParameterName
  case nonFiniteParameterValue(ScalarParameterID)

  /// A human-readable description of the validation failure.
  public var errorDescription: String? {
    switch self {
    case .nonFiniteConstant:
      "A scalar constant must be finite."
    case .emptyParameterName:
      "A scalar parameter name cannot be empty."
    case .nonFiniteParameterValue(let id):
      "Scalar parameter \(id) must have a finite value."
    }
  }
}

/// Failures raised while managing scalar parameters owned by a geometry scene.
public enum ScalarParameterError: Error, Equatable, LocalizedError, Sendable {
  case duplicateParameter(ScalarParameterID)
  case missingParameter(ScalarParameterID)

  /// A human-readable description of the parameter failure.
  public var errorDescription: String? {
    switch self {
    case .duplicateParameter(let id):
      "Scalar parameter \(id) already exists."
    case .missingParameter(let id):
      "The construction refers to missing scalar parameter \(id)."
    }
  }
}

/// A stable, app-independent identifier for a scalar parameter.
public struct ScalarParameterID: Codable, CustomStringConvertible, Hashable, Sendable {
  /// The underlying universally unique identifier.
  public let rawValue: UUID

  /// Creates an identifier, generating a new UUID by default.
  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }

  /// A printable form of the identifier.
  public var description: String {
    rawValue.uuidString
  }
}

/// A finite scalar input that expressions can share by identity or name.
public struct ScalarParameter: Codable, Equatable, Sendable {
  /// The stable identity of the parameter.
  public let id: ScalarParameterID

  /// The human-readable name used by named references.
  public let name: String

  /// The parameter's finite scalar value.
  public let value: Double

  /// Creates a validated scalar parameter.
  public init(id: ScalarParameterID = ScalarParameterID(), name: String, value: Double) throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ScalarValidationError.emptyParameterName
    }
    guard value.isFinite else {
      throw ScalarValidationError.nonFiniteParameterValue(id)
    }
    self.id = id
    self.name = name
    self.value = value
  }

  private enum CodingKeys: CodingKey {
    case id
    case name
    case value
  }

  /// Decodes a parameter while preserving its name and finite-value invariants.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(ScalarParameterID.self, forKey: .id),
      name: container.decode(String.self, forKey: .name),
      value: container.decode(Double.self, forKey: .value))
  }
}

/// A stable or human-readable reference to a scalar parameter.
public enum ScalarParameterReference: Codable, Equatable, Sendable {
  case identified(ScalarParameterID)
  case named(String)
}

/// A supported binary arithmetic operation.
public enum ScalarArithmeticOperator: String, Codable, Equatable, Sendable {
  case addition
  case subtraction
  case multiplication
  case division
  case power
}

/// A supported single-argument scalar function.
public enum ScalarFunction: String, Codable, Equatable, Sendable {
  case sine
  case cosine
  case tangent
  case absoluteValue
  case squareRoot
  case naturalLogarithm
  case exponential
}

/// The result of evaluating a scalar expression.
public enum ScalarEvaluationOutcome: Codable, Equatable, Sendable {
  case exact(value: Double, diagnostic: String)
  case approximate(value: Double, diagnostic: String)
  case undefined(diagnostic: String)
  case unsupported(diagnostic: String)
  case nonconvergent(diagnostic: String)
  case pending(diagnostic: String)

  /// The evaluated number when this outcome contains one; otherwise `nil`.
  public var value: Double? {
    switch self {
    case .exact(let value, _), .approximate(let value, _):
      value
    case .undefined, .unsupported, .nonconvergent, .pending:
      nil
    }
  }

  /// Whether this outcome contains a numerical approximation.
  public var isApproximate: Bool {
    if case .approximate = self {
      return true
    }
    return false
  }
}
