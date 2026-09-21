import Foundation

/// An exact symbolic solution for a supported univariate polynomial equation `expression = 0`.
public enum SymbolicPolynomialSolution: Equatable, Sendable {
  /// Exact root expressions and the polynomial degree that produced them.
  case exact(degree: Int, roots: [ScalarExpression])

  /// A supported polynomial whose real solution set is empty.
  case noRealRoots(degree: Int, diagnostic: String)

  /// A valid expression outside the solver's documented polynomial boundary.
  case unsupported(diagnostic: String)

  /// An expression that violates scalar-expression invariants.
  case invalid(diagnostic: String)

  /// Evaluates exact root expressions into explicitly approximate floating-point values.
  public func approximated() -> PolynomialApproximationResult {
    switch self {
    case .exact(let degree, let roots):
      var values: [Double] = []
      for root in roots {
        guard let value = root.evaluate().value else {
          return .unsupported(
            diagnostic: "An exact root could not be evaluated as a finite real number.")
        }
        values.append(value)
      }
      return .approximate(degree: degree, roots: values)
    case .noRealRoots(let degree, let diagnostic):
      return .noRealRoots(degree: degree, diagnostic: diagnostic)
    case .unsupported(let diagnostic):
      return .unsupported(diagnostic: diagnostic)
    case .invalid(let diagnostic):
      return .invalid(diagnostic: diagnostic)
    }
  }
}

/// A floating-point view of a symbolic polynomial solution.
public enum PolynomialApproximationResult: Equatable, Sendable {
  /// Finite floating-point approximations of the exact real roots.
  case approximate(degree: Int, roots: [Double])

  /// A supported polynomial whose real solution set is empty.
  case noRealRoots(degree: Int, diagnostic: String)

  /// A valid expression outside the solver's documented polynomial boundary.
  case unsupported(diagnostic: String)

  /// An expression that violates scalar-expression invariants.
  case invalid(diagnostic: String)
}

extension ScalarExpression {
  /// Solves `self = 0` as a univariate polynomial up to the requested bounded degree.
  public func solvePolynomial(
    withRespectTo parameterID: ScalarParameterID,
    maximumDegree: Int = 2
  ) -> SymbolicPolynomialSolution {
    do {
      try validate()
    } catch {
      return .invalid(diagnostic: error.localizedDescription)
    }
    guard maximumDegree >= 1 else {
      return .unsupported(diagnostic: "The maximum polynomial degree must be at least one.")
    }
    switch polynomialCoefficients(for: parameterID, maximumDegree: maximumDegree) {
    case .coefficients(let coefficients):
      return solveExtractedPolynomial(coefficients)
    case .unsupported(let diagnostic):
      return .unsupported(diagnostic: diagnostic)
    }
  }
}

private enum PolynomialCoefficientExtraction {
  case coefficients([Double])
  case unsupported(String)
}

private func solveExtractedPolynomial(
  _ untrimmedCoefficients: [Double]
) -> SymbolicPolynomialSolution {
  let coefficients = trimmingTrailingZeros(untrimmedCoefficients)
  let degree = coefficients.count - 1
  switch degree {
  case 1:
    let root = ScalarExpression.arithmetic(
      left: .negation(.constant(coefficients[0])),
      operation: .division,
      right: .constant(coefficients[1]))
    return .exact(degree: degree, roots: [root])
  case 2:
    return solveQuadratic(coefficients)
  default:
    return .unsupported(diagnostic: "Only linear and quadratic polynomials are supported.")
  }
}

private func solveQuadratic(_ coefficients: [Double]) -> SymbolicPolynomialSolution {
  let constant = coefficients[0]
  let linear = coefficients[1]
  let quadratic = coefficients[2]
  let discriminant = linear * linear - 4 * quadratic * constant
  guard discriminant >= 0 else {
    return .noRealRoots(
      degree: 2,
      diagnostic: "The quadratic discriminant is negative.")
  }
  let denominator = ScalarExpression.constant(2 * quadratic)
  let squareRoot = ScalarExpression.function(
    .squareRoot,
    argument: .constant(discriminant))
  let positiveRoot = quadraticRoot(
    linearCoefficient: linear,
    squareRoot: squareRoot,
    operation: .addition,
    denominator: denominator)
  guard discriminant != 0 else {
    return .exact(degree: 2, roots: [positiveRoot])
  }
  let negativeRoot = quadraticRoot(
    linearCoefficient: linear,
    squareRoot: squareRoot,
    operation: .subtraction,
    denominator: denominator)
  return .exact(degree: 2, roots: [positiveRoot, negativeRoot])
}

private func quadraticRoot(
  linearCoefficient: Double,
  squareRoot: ScalarExpression,
  operation: ScalarArithmeticOperator,
  denominator: ScalarExpression
) -> ScalarExpression {
  .arithmetic(
    left: .arithmetic(
      left: .negation(.constant(linearCoefficient)),
      operation: operation,
      right: squareRoot),
    operation: .division,
    right: denominator)
}

private func trimmingTrailingZeros(_ coefficients: [Double]) -> [Double] {
  var result = coefficients
  while result.count > 1, result.last == 0 {
    result.removeLast()
  }
  return result
}

extension ScalarExpression {
  fileprivate func polynomialCoefficients(
    for parameterID: ScalarParameterID,
    maximumDegree: Int
  ) -> PolynomialCoefficientExtraction {
    switch self {
    case .constant(let value):
      return .coefficients([value])
    case .parameter(.identified(let id)) where id == parameterID:
      return .coefficients([0, 1])
    case .parameter:
      return .unsupported("The polynomial contains another or ambiguously named parameter.")
    case .negation(let expression):
      return expression.polynomialCoefficients(
        for: parameterID,
        maximumDegree: maximumDegree
      ).map { $0.map(-) }
    case .arithmetic(let left, let operation, let right):
      return polynomialArithmeticCoefficients(
        left: left,
        operation: operation,
        right: right,
        parameterID: parameterID,
        maximumDegree: maximumDegree)
    case .function:
      return .unsupported("Scalar functions are not polynomial terms.")
    }
  }
}

extension PolynomialCoefficientExtraction {
  fileprivate func map(_ transform: ([Double]) -> [Double]) -> PolynomialCoefficientExtraction {
    switch self {
    case .coefficients(let coefficients):
      .coefficients(transform(coefficients))
    case .unsupported:
      self
    }
  }
}

private func polynomialArithmeticCoefficients(
  left: ScalarExpression,
  operation: ScalarArithmeticOperator,
  right: ScalarExpression,
  parameterID: ScalarParameterID,
  maximumDegree: Int
) -> PolynomialCoefficientExtraction {
  let leftResult = left.polynomialCoefficients(for: parameterID, maximumDegree: maximumDegree)
  guard case .coefficients(let leftCoefficients) = leftResult else { return leftResult }
  let rightResult = right.polynomialCoefficients(for: parameterID, maximumDegree: maximumDegree)
  guard case .coefficients(let rightCoefficients) = rightResult else { return rightResult }

  switch operation {
  case .addition:
    return .coefficients(adding(leftCoefficients, rightCoefficients, scale: 1))
  case .subtraction:
    return .coefficients(adding(leftCoefficients, rightCoefficients, scale: -1))
  case .multiplication:
    return boundedProduct(leftCoefficients, rightCoefficients, maximumDegree: maximumDegree)
  case .power:
    return boundedPower(leftCoefficients, rightCoefficients, maximumDegree: maximumDegree)
  case .division:
    return .unsupported("This polynomial arithmetic form is not supported.")
  }
}

private func boundedProduct(
  _ left: [Double],
  _ right: [Double],
  maximumDegree: Int
) -> PolynomialCoefficientExtraction {
  let product = multiplying(left, right)
  guard product.count - 1 <= maximumDegree else {
    return .unsupported("The polynomial exceeds the requested maximum degree.")
  }
  return .coefficients(product)
}

private func boundedPower(
  _ base: [Double],
  _ exponent: [Double],
  maximumDegree: Int
) -> PolynomialCoefficientExtraction {
  guard
    exponent.count == 1,
    exponent[0] >= 0,
    exponent[0].rounded() == exponent[0],
    exponent[0] <= Double(maximumDegree)
  else {
    return .unsupported("A polynomial power must be a bounded nonnegative integer constant.")
  }
  var power = [1.0]
  for _ in 0..<Int(exponent[0]) {
    power = multiplying(power, base)
    guard power.count - 1 <= maximumDegree else {
      return .unsupported("The polynomial exceeds the requested maximum degree.")
    }
  }
  return .coefficients(power)
}

private func adding(_ left: [Double], _ right: [Double], scale: Double) -> [Double] {
  let count = max(left.count, right.count)
  return (0..<count).map { index in
    let leftValue = index < left.count ? left[index] : 0
    let rightValue = index < right.count ? right[index] : 0
    return leftValue + scale * rightValue
  }
}

private func multiplying(_ left: [Double], _ right: [Double]) -> [Double] {
  var result = Array(repeating: 0.0, count: left.count + right.count - 1)
  for (leftDegree, leftValue) in left.enumerated() {
    for (rightDegree, rightValue) in right.enumerated() {
      result[leftDegree + rightDegree] += leftValue * rightValue
    }
  }
  return trimmingTrailingZeros(result)
}
