import Foundation

/// The result of an exact, structure-preserving symbolic transformation.
public enum SymbolicExpressionResult: Equatable, Sendable {
  /// A validated expression that represents the exact symbolic result.
  case exact(ScalarExpression)

  /// An expression that cannot be handled without making an unsafe assumption.
  case unsupported(diagnostic: String)

  /// An input that violates the scalar-expression invariants.
  case invalid(diagnostic: String)

  /// The exact expression when the transformation succeeded.
  public var expression: ScalarExpression? {
    guard case .exact(let expression) = self else {
      return nil
    }
    return expression
  }
}

extension ScalarExpression {
  /// Validates and simplifies this expression without numerical approximation.
  public func simplifiedSymbolically() -> SymbolicExpressionResult {
    do {
      try validate()
    } catch {
      return .invalid(diagnostic: error.localizedDescription)
    }
    return .exact(simplifiedStructure())
  }

  /// Returns the exact symbolic derivative with respect to a stable parameter identity.
  public func differentiated(
    withRespectTo parameterID: ScalarParameterID
  ) -> SymbolicExpressionResult {
    do {
      try validate()
    } catch {
      return .invalid(diagnostic: error.localizedDescription)
    }
    return simplifiedStructure().differentiateStructure(withRespectTo: parameterID)
  }

  fileprivate func simplifiedStructure() -> ScalarExpression {
    switch self {
    case .constant, .parameter:
      self
    case .negation(let expression):
      simplifyNegation(expression.simplifiedStructure())
    case .arithmetic(let left, let operation, let right):
      simplifyArithmetic(
        left: left.simplifiedStructure(),
        operation: operation,
        right: right.simplifiedStructure())
    case .function(let function, let argument):
      .function(function, argument: argument.simplifiedStructure())
    }
  }

  fileprivate func differentiateStructure(
    withRespectTo parameterID: ScalarParameterID
  ) -> SymbolicExpressionResult {
    switch self {
    case .constant:
      .exact(.constant(0))
    case .parameter(.identified(let id)):
      .exact(.constant(id == parameterID ? 1 : 0))
    case .parameter(.named(let name)):
      .unsupported(
        diagnostic: "Named parameter \(name) has no stable identity for differentiation.")
    case .negation(let expression):
      expression.differentiateStructure(withRespectTo: parameterID).mapExact {
        simplifyNegation($0)
      }
    case .arithmetic(let left, let operation, let right):
      differentiateArithmetic(
        left: left,
        operation: operation,
        right: right,
        parameterID: parameterID)
    case .function(let function, let argument):
      differentiateFunction(
        function,
        argument: argument,
        parameterID: parameterID)
    }
  }
}

private func differentiateFunction(
  _ function: ScalarFunction,
  argument: ScalarExpression,
  parameterID: ScalarParameterID
) -> SymbolicExpressionResult {
  guard function != .absoluteValue else {
    return .unsupported(
      diagnostic: "Absolute value is not differentiable at every point.")
  }
  let argumentResult = argument.differentiateStructure(withRespectTo: parameterID)
  guard let argumentDerivative = argumentResult.expression else { return argumentResult }
  let outerDerivative: ScalarExpression
  switch function {
  case .sine:
    outerDerivative = .function(.cosine, argument: argument)
  case .cosine:
    outerDerivative = .negation(.function(.sine, argument: argument))
  case .tangent:
    outerDerivative = .arithmetic(
      left: .constant(1),
      operation: .division,
      right: .arithmetic(
        left: .function(.cosine, argument: argument),
        operation: .power,
        right: .constant(2)))
  case .squareRoot:
    outerDerivative = .arithmetic(
      left: .constant(1),
      operation: .division,
      right: .arithmetic(
        left: .constant(2),
        operation: .multiplication,
        right: .function(.squareRoot, argument: argument)))
  case .naturalLogarithm:
    outerDerivative = .arithmetic(
      left: .constant(1),
      operation: .division,
      right: argument)
  case .exponential:
    outerDerivative = .function(.exponential, argument: argument)
  case .absoluteValue:
    preconditionFailure("Absolute value is handled before the differentiable-function switch.")
  }
  return .exact(
    simplifyArithmetic(
      left: outerDerivative,
      operation: .multiplication,
      right: argumentDerivative))
}

extension SymbolicExpressionResult {
  fileprivate func mapExact(
    _ transform: (ScalarExpression) -> ScalarExpression
  ) -> SymbolicExpressionResult {
    switch self {
    case .exact(let expression):
      .exact(transform(expression).simplifiedStructure())
    case .unsupported, .invalid:
      self
    }
  }
}

private func differentiateArithmetic(
  left: ScalarExpression,
  operation: ScalarArithmeticOperator,
  right: ScalarExpression,
  parameterID: ScalarParameterID
) -> SymbolicExpressionResult {
  switch operation {
  case .addition, .subtraction:
    return combineDerivatives(
      left: left,
      operation: operation,
      right: right,
      parameterID: parameterID)
  case .multiplication:
    return productDerivative(left: left, right: right, parameterID: parameterID)
  case .division:
    return quotientDerivative(numerator: left, denominator: right, parameterID: parameterID)
  case .power:
    return powerDerivative(base: left, exponent: right, parameterID: parameterID)
  }
}

private func quotientDerivative(
  numerator: ScalarExpression,
  denominator: ScalarExpression,
  parameterID: ScalarParameterID
) -> SymbolicExpressionResult {
  let numeratorResult = numerator.differentiateStructure(withRespectTo: parameterID)
  guard let numeratorDerivative = numeratorResult.expression else { return numeratorResult }
  let denominatorResult = denominator.differentiateStructure(withRespectTo: parameterID)
  guard let denominatorDerivative = denominatorResult.expression else { return denominatorResult }
  let first = simplifyArithmetic(
    left: numeratorDerivative,
    operation: .multiplication,
    right: denominator)
  let second = simplifyArithmetic(
    left: numerator,
    operation: .multiplication,
    right: denominatorDerivative)
  let quotientNumerator = simplifyArithmetic(
    left: first,
    operation: .subtraction,
    right: second)
  let quotientDenominator = simplifyArithmetic(
    left: denominator,
    operation: .power,
    right: .constant(2))
  return .exact(
    simplifyArithmetic(
      left: quotientNumerator,
      operation: .division,
      right: quotientDenominator))
}

private func combineDerivatives(
  left: ScalarExpression,
  operation: ScalarArithmeticOperator,
  right: ScalarExpression,
  parameterID: ScalarParameterID
) -> SymbolicExpressionResult {
  let leftResult = left.differentiateStructure(withRespectTo: parameterID)
  guard let leftDerivative = leftResult.expression else { return leftResult }
  let rightResult = right.differentiateStructure(withRespectTo: parameterID)
  guard let rightDerivative = rightResult.expression else { return rightResult }
  return .exact(
    simplifyArithmetic(left: leftDerivative, operation: operation, right: rightDerivative))
}

private func productDerivative(
  left: ScalarExpression,
  right: ScalarExpression,
  parameterID: ScalarParameterID
) -> SymbolicExpressionResult {
  let leftResult = left.differentiateStructure(withRespectTo: parameterID)
  guard let leftDerivative = leftResult.expression else { return leftResult }
  let rightResult = right.differentiateStructure(withRespectTo: parameterID)
  guard let rightDerivative = rightResult.expression else { return rightResult }
  let first = simplifyArithmetic(left: leftDerivative, operation: .multiplication, right: right)
  let second = simplifyArithmetic(left: left, operation: .multiplication, right: rightDerivative)
  return .exact(simplifyArithmetic(left: first, operation: .addition, right: second))
}

private func powerDerivative(
  base: ScalarExpression,
  exponent: ScalarExpression,
  parameterID: ScalarParameterID
) -> SymbolicExpressionResult {
  guard case .constant(let power) = exponent else {
    return .unsupported(diagnostic: "A nonconstant exponent is not supported.")
  }
  let baseResult = base.differentiateStructure(withRespectTo: parameterID)
  guard let baseDerivative = baseResult.expression else { return baseResult }
  let loweredPower = simplifyArithmetic(
    left: base,
    operation: .power,
    right: .constant(power - 1))
  let coefficient = simplifyArithmetic(
    left: .constant(power),
    operation: .multiplication,
    right: loweredPower)
  return .exact(
    simplifyArithmetic(
      left: coefficient,
      operation: .multiplication,
      right: baseDerivative))
}

private func simplifyNegation(_ expression: ScalarExpression) -> ScalarExpression {
  switch expression {
  case .constant(let value):
    .constant(-value)
  case .negation(let inner):
    inner
  default:
    .negation(expression)
  }
}

private func simplifyArithmetic(
  left: ScalarExpression,
  operation: ScalarArithmeticOperator,
  right: ScalarExpression
) -> ScalarExpression {
  switch operation {
  case .addition:
    return simplifyAddition(left, right)
  case .subtraction:
    return simplifySubtraction(left, right)
  case .multiplication:
    return simplifyMultiplication(left, right)
  case .division:
    return right.isConstant(1)
      ? left
      : .arithmetic(left: left, operation: operation, right: right)
  case .power:
    return simplifyPower(left, right)
  }
}

private func simplifyAddition(
  _ left: ScalarExpression,
  _ right: ScalarExpression
) -> ScalarExpression {
  if right.isConstant(0) { return left }
  if left.isConstant(0) { return right }
  return .arithmetic(left: left, operation: .addition, right: right)
}

private func simplifySubtraction(
  _ left: ScalarExpression,
  _ right: ScalarExpression
) -> ScalarExpression {
  if right.isConstant(0) { return left }
  if left == right { return .constant(0) }
  return .arithmetic(left: left, operation: .subtraction, right: right)
}

private func simplifyMultiplication(
  _ left: ScalarExpression,
  _ right: ScalarExpression
) -> ScalarExpression {
  if left.isConstant(0) || right.isConstant(0) { return .constant(0) }
  if left.isConstant(1) { return right }
  if right.isConstant(1) { return left }
  return .arithmetic(left: left, operation: .multiplication, right: right)
}

private func simplifyPower(
  _ base: ScalarExpression,
  _ exponent: ScalarExpression
) -> ScalarExpression {
  if exponent.isConstant(1) { return base }
  if exponent.isConstant(0), !base.isConstant(0) { return .constant(1) }
  return .arithmetic(left: base, operation: .power, right: exponent)
}

extension ScalarExpression {
  fileprivate func isConstant(_ expected: Double) -> Bool {
    guard case .constant(let value) = self else {
      return false
    }
    return value == expected
  }
}
