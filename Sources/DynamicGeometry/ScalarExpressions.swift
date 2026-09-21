import Foundation

/// Failures raised while creating or validating scalar inputs.
public enum ScalarValidationError: Error, Equatable, LocalizedError, Sendable {
  /// A literal expression value was NaN or infinite.
  case nonFiniteConstant

  /// A parameter name was empty or contained only whitespace.
  case emptyParameterName

  /// A parameter value was NaN or infinite.
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
  /// Resolves a parameter by its stable identifier.
  case identified(ScalarParameterID)

  /// Resolves a parameter by its exact name.
  case named(String)
}

/// A supported binary arithmetic operation.
public enum ScalarArithmeticOperator: String, Codable, Equatable, Sendable {
  /// Adds the right operand to the left operand.
  case addition

  /// Subtracts the right operand from the left operand.
  case subtraction

  /// Multiplies the two operands.
  case multiplication

  /// Divides the left operand by the right operand.
  case division

  /// Raises the left operand to the power of the right operand.
  case power
}

/// A supported single-argument scalar function.
public enum ScalarFunction: String, Codable, Equatable, Sendable {
  /// The trigonometric sine function, with a radian argument.
  case sine

  /// The trigonometric cosine function, with a radian argument.
  case cosine

  /// The trigonometric tangent function, with a radian argument.
  case tangent

  /// The nonnegative magnitude of a scalar.
  case absoluteValue

  /// The principal square root.
  case squareRoot

  /// The natural logarithm.
  case naturalLogarithm

  /// The exponential function with base e.
  case exponential
}

/// The result of evaluating a scalar expression.
public enum ScalarEvaluationOutcome: Codable, Equatable, Sendable {
  /// Evaluation produced a value whose exactness is established by the expression node.
  case exact(value: Double, diagnostic: String)

  /// Evaluation produced a finite numerical approximation.
  case approximate(value: Double, diagnostic: String)

  /// Evaluation has no value for the supplied inputs.
  case undefined(diagnostic: String)

  /// The expression is valid, but this evaluator does not implement it.
  case unsupported(diagnostic: String)

  /// Evaluation did not converge to a usable value.
  case nonconvergent(diagnostic: String)

  /// Evaluation has not completed yet.
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

/// A UI-independent syntax tree for a real-valued scalar expression.
public indirect enum ScalarExpression: Codable, Equatable, Sendable {
  /// A literal numeric value.
  case constant(Double)

  /// A reference to a separately stored scalar parameter.
  case parameter(ScalarParameterReference)

  /// The additive inverse of another scalar expression.
  case negation(ScalarExpression)

  /// A binary arithmetic operation over two scalar expressions.
  case arithmetic(
    left: ScalarExpression,
    operation: ScalarArithmeticOperator,
    right: ScalarExpression)

  /// Applies a standard mathematical function to a scalar expression.
  case function(ScalarFunction, argument: ScalarExpression)

  /// Evaluates the expression using the supplied scalar parameter bindings.
  public func evaluate(parameters: [ScalarParameter] = []) -> ScalarEvaluationOutcome {
    switch self {
    case .constant(let value):
      guard value.isFinite else {
        return .undefined(diagnostic: "A scalar constant must be finite.")
      }
      return .exact(value: value, diagnostic: "Finite literal.")
    case .parameter(let reference):
      return evaluate(reference: reference, parameters: parameters)
    case .negation(let expression):
      return evaluateNegation(expression, parameters: parameters)
    case .arithmetic(let left, let operation, let right):
      return evaluate(
        left: left,
        operation: operation,
        right: right,
        parameters: parameters)
    case .function(let function, let argument):
      return evaluate(function: function, argument: argument, parameters: parameters)
    }
  }

  /// Validates finite literals and well-formed named references throughout the tree.
  public func validate() throws {
    switch self {
    case .constant(let value):
      guard value.isFinite else {
        throw ScalarValidationError.nonFiniteConstant
      }
    case .parameter(.identified):
      break
    case .parameter(.named(let name)):
      guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ScalarValidationError.emptyParameterName
      }
    case .negation(let expression):
      try expression.validate()
    case .arithmetic(let left, _, let right):
      try left.validate()
      try right.validate()
    case .function(_, let argument):
      try argument.validate()
    }
  }

  private func evaluateNegation(
    _ expression: ScalarExpression,
    parameters: [ScalarParameter]
  ) -> ScalarEvaluationOutcome {
    switch expression.evaluate(parameters: parameters) {
    case .exact(let value, _):
      return .exact(value: -value, diagnostic: "Exact negation.")
    case .approximate(let value, _):
      return .approximate(value: -value, diagnostic: "Approximate negation.")
    case .undefined(let diagnostic):
      return .undefined(diagnostic: diagnostic)
    case .unsupported(let diagnostic):
      return .unsupported(diagnostic: diagnostic)
    case .nonconvergent(let diagnostic):
      return .nonconvergent(diagnostic: diagnostic)
    case .pending(let diagnostic):
      return .pending(diagnostic: diagnostic)
    }
  }

  private func evaluate(
    left: ScalarExpression,
    operation: ScalarArithmeticOperator,
    right: ScalarExpression,
    parameters: [ScalarParameter]
  ) -> ScalarEvaluationOutcome {
    let leftOutcome = left.evaluate(parameters: parameters)
    guard let leftValue = leftOutcome.value else {
      return leftOutcome
    }
    let rightOutcome = right.evaluate(parameters: parameters)
    guard let rightValue = rightOutcome.value else {
      return rightOutcome
    }

    let result: Double
    switch operation {
    case .addition:
      result = leftValue + rightValue
    case .subtraction:
      result = leftValue - rightValue
    case .multiplication:
      result = leftValue * rightValue
    case .division:
      guard rightValue != 0 else {
        return .undefined(diagnostic: "Division by zero is undefined.")
      }
      result = leftValue / rightValue
    case .power:
      result = pow(leftValue, rightValue)
    }
    guard result.isFinite else {
      return .undefined(diagnostic: "Arithmetic produced a non-finite result.")
    }
    return .approximate(value: result, diagnostic: "Finite floating-point arithmetic.")
  }

  private func evaluate(
    function: ScalarFunction,
    argument: ScalarExpression,
    parameters: [ScalarParameter]
  ) -> ScalarEvaluationOutcome {
    let argumentOutcome = argument.evaluate(parameters: parameters)
    guard let argumentValue = argumentOutcome.value else {
      return argumentOutcome
    }
    if let domainFailure = functionDomainFailure(function, argument: argumentValue) {
      return domainFailure
    }

    let result = apply(function, to: argumentValue)
    guard result.isFinite else {
      return .undefined(diagnostic: "The function has no finite value for this argument.")
    }
    return .approximate(
      value: result,
      diagnostic: "\(function.rawValue) evaluated numerically.")
  }

  private func functionDomainFailure(
    _ function: ScalarFunction,
    argument: Double
  ) -> ScalarEvaluationOutcome? {
    switch function {
    case .squareRoot where argument < 0:
      return .undefined(diagnostic: "Square root requires a nonnegative argument.")
    case .naturalLogarithm where argument <= 0:
      return .undefined(diagnostic: "Natural logarithm requires a positive argument.")
    case .tangent where abs(cos(argument)) <= 0.000_000_000_001:
      return .undefined(diagnostic: "Tangent is undefined where cosine is zero.")
    default:
      return nil
    }
  }

  private func apply(_ function: ScalarFunction, to argument: Double) -> Double {
    switch function {
    case .sine:
      return sin(argument)
    case .cosine:
      return cos(argument)
    case .tangent:
      return tan(argument)
    case .absoluteValue:
      return abs(argument)
    case .squareRoot:
      return sqrt(argument)
    case .naturalLogarithm:
      return log(argument)
    case .exponential:
      return exp(argument)
    }
  }

  private func evaluate(
    reference: ScalarParameterReference,
    parameters: [ScalarParameter]
  ) -> ScalarEvaluationOutcome {
    let parameter: ScalarParameter?
    let missingDiagnostic: String
    switch reference {
    case .identified(let id):
      let matches = parameters.filter { $0.id == id }
      guard matches.count <= 1 else {
        return .undefined(diagnostic: "Multiple scalar parameters have identifier \(id).")
      }
      parameter = matches.first
      missingDiagnostic = "No scalar parameter with identifier \(id) was supplied."
    case .named(let name):
      let matches = parameters.filter { $0.name == name }
      guard matches.count <= 1 else {
        return .undefined(diagnostic: "Multiple scalar parameters are named \(name).")
      }
      parameter = matches.first
      missingDiagnostic = "No scalar parameter named \(name) was supplied."
    }
    guard let parameter else {
      return .undefined(diagnostic: missingDiagnostic)
    }
    return .exact(value: parameter.value, diagnostic: "Parameter \(parameter.name).")
  }
}
