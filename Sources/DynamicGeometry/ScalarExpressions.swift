import Foundation

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

  /// Stable parameter identifiers referenced by the expression, in first-use order.
  public var referencedParameterIDs: [ScalarParameterID] {
    var seen: Set<ScalarParameterID> = []
    var result: [ScalarParameterID] = []
    collectReferencedParameterIDs(into: &result, seen: &seen)
    return result
  }

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

  private func collectReferencedParameterIDs(
    into result: inout [ScalarParameterID],
    seen: inout Set<ScalarParameterID>
  ) {
    switch self {
    case .constant, .parameter(.named):
      break
    case .parameter(.identified(let id)):
      if seen.insert(id).inserted {
        result.append(id)
      }
    case .negation(let expression):
      expression.collectReferencedParameterIDs(into: &result, seen: &seen)
    case .arithmetic(let left, _, let right):
      left.collectReferencedParameterIDs(into: &result, seen: &seen)
      right.collectReferencedParameterIDs(into: &result, seen: &seen)
    case .function(_, let argument):
      argument.collectReferencedParameterIDs(into: &result, seen: &seen)
    }
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
