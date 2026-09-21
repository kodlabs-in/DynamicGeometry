import Foundation
import Testing

@testable import DynamicGeometry

@Suite("Symbolic algebra")
struct SymbolicAlgebraTests {
  @Test("Simplification removes arithmetic identities without changing parameter identity")
  func simplificationRemovesArithmeticIdentities() throws {
    let parameterID = ScalarParameterID()
    let parameter = ScalarExpression.parameter(.identified(parameterID))
    let expression = ScalarExpression.arithmetic(
      left: .arithmetic(left: parameter, operation: .multiplication, right: .constant(1)),
      operation: .addition,
      right: .constant(0))

    let result = expression.simplifiedSymbolically()

    #expect(result == .exact(parameter))
    let encoded = try JSONEncoder().encode(expression)
    #expect(try JSONDecoder().decode(ScalarExpression.self, from: encoded) == expression)
  }

  @Test("A polynomial derivative evaluates correctly at multiple parameter values")
  func polynomialDerivativeEvaluatesAtMultiplePoints() throws {
    let parameterID = ScalarParameterID()
    let parameter = ScalarExpression.parameter(.identified(parameterID))
    let expression = ScalarExpression.arithmetic(
      left: .arithmetic(left: parameter, operation: .power, right: .constant(3)),
      operation: .addition,
      right: .arithmetic(left: .constant(2), operation: .multiplication, right: parameter))
    let derivative = try #require(
      expression.differentiated(withRespectTo: parameterID).expression)

    for value in [-2.0, 0.5, 3.0] {
      let binding = try ScalarParameter(id: parameterID, name: "x", value: value)
      let actual = try #require(derivative.evaluate(parameters: [binding]).value)
      #expect(abs(actual - (3 * value * value + 2)) < 0.000_000_001)
    }
  }

  @Test("Supported scalar functions differentiate with the chain rule")
  func supportedFunctionsDifferentiate() throws {
    let parameterID = ScalarParameterID()
    let parameter = ScalarExpression.parameter(.identified(parameterID))
    let expectations: [(ScalarFunction, (Double) -> Double)] = [
      (.sine, { cos($0) }),
      (.cosine, { -sin($0) }),
      (.tangent, { 1 / pow(cos($0), 2) }),
      (.squareRoot, { 1 / (2 * sqrt($0)) }),
      (.naturalLogarithm, { 1 / $0 }),
      (.exponential, { exp($0) }),
    ]

    for (function, expected) in expectations {
      let input = ScalarExpression.arithmetic(
        left: parameter,
        operation: .power,
        right: .constant(2))
      let expression = ScalarExpression.function(function, argument: input)
      let derivative = try #require(
        expression.differentiated(withRespectTo: parameterID).expression)

      for value in [0.5, 1.25] {
        let binding = try ScalarParameter(id: parameterID, name: "x", value: value)
        let actual = try #require(derivative.evaluate(parameters: [binding]).value)
        let argument = value * value
        let chainRuleValue = expected(argument) * 2 * value
        #expect(abs(actual - chainRuleValue) < 0.000_000_001)
      }
    }
  }

  @Test("A quotient derivative evaluates correctly at multiple parameter values")
  func quotientDerivativeEvaluatesAtMultiplePoints() throws {
    let parameterID = ScalarParameterID()
    let parameter = ScalarExpression.parameter(.identified(parameterID))
    let denominator = ScalarExpression.arithmetic(
      left: parameter,
      operation: .addition,
      right: .constant(1))
    let expression = ScalarExpression.arithmetic(
      left: parameter,
      operation: .division,
      right: denominator)
    let derivative = try #require(
      expression.differentiated(withRespectTo: parameterID).expression)

    for value in [-0.5, 1, 3] {
      let binding = try ScalarParameter(id: parameterID, name: "x", value: value)
      let actual = try #require(derivative.evaluate(parameters: [binding]).value)
      #expect(abs(actual - (1 / pow(value + 1, 2))) < 0.000_000_001)
    }
  }

  @Test("Nondifferentiable and nonconstant-exponent forms are honestly unsupported")
  func unsupportedDerivativeFormsRemainExplicit() {
    let parameterID = ScalarParameterID()
    let parameter = ScalarExpression.parameter(.identified(parameterID))

    #expect(
      ScalarExpression.function(.absoluteValue, argument: parameter)
        .differentiated(withRespectTo: parameterID)
        == .unsupported(
          diagnostic: "Absolute value is not differentiable at every point."))
    #expect(
      ScalarExpression.arithmetic(
        left: .constant(2),
        operation: .power,
        right: parameter
      ).differentiated(withRespectTo: parameterID)
        == .unsupported(diagnostic: "A nonconstant exponent is not supported."))
  }

  @Test("A linear polynomial has an exact symbolic root and an explicit approximation")
  func solvesLinearPolynomialExactly() throws {
    let parameterID = ScalarParameterID()
    let parameter = ScalarExpression.parameter(.identified(parameterID))
    let expression = ScalarExpression.arithmetic(
      left: .arithmetic(left: .constant(2), operation: .multiplication, right: parameter),
      operation: .addition,
      right: .constant(4))

    let solution = expression.solvePolynomial(withRespectTo: parameterID)
    guard case .exact(let degree, let roots) = solution else {
      Issue.record("Expected an exact linear solution, got \(solution)")
      return
    }

    #expect(degree == 1)
    #expect(roots.count == 1)
    #expect(try #require(roots.first?.evaluate().value) == -2)
    #expect(solution.approximated() == .approximate(degree: 1, roots: [-2]))
  }

  @Test("A quadratic polynomial has exact symbolic roots and floating approximations")
  func solvesQuadraticPolynomialExactly() throws {
    let parameterID = ScalarParameterID()
    let parameter = ScalarExpression.parameter(.identified(parameterID))
    let squared = ScalarExpression.arithmetic(
      left: parameter,
      operation: .multiplication,
      right: parameter)
    let linear = ScalarExpression.arithmetic(
      left: .constant(5),
      operation: .multiplication,
      right: parameter)
    let expression = ScalarExpression.arithmetic(
      left: .arithmetic(left: squared, operation: .subtraction, right: linear),
      operation: .addition,
      right: .constant(6))

    let solution = expression.solvePolynomial(withRespectTo: parameterID)
    guard case .exact(let degree, let roots) = solution else {
      Issue.record("Expected an exact quadratic solution, got \(solution)")
      return
    }

    #expect(degree == 2)
    let exactValues = try roots.map { try #require($0.evaluate().value) }.sorted()
    #expect(exactValues == [2, 3])
    guard
      case .approximate(let approximateDegree, let approximations) =
        solution.approximated()
    else {
      Issue.record("Expected finite quadratic approximations")
      return
    }
    #expect(approximateDegree == 2)
    #expect(approximations.sorted() == [2, 3])
  }

  @Test("A quadratic with a negative discriminant reports no real roots")
  func quadraticCanReportNoRealRoots() {
    let parameterID = ScalarParameterID()
    let parameter = ScalarExpression.parameter(.identified(parameterID))
    let expression = ScalarExpression.arithmetic(
      left: .arithmetic(left: parameter, operation: .power, right: .constant(2)),
      operation: .addition,
      right: .constant(1))
    let expected = SymbolicPolynomialSolution.noRealRoots(
      degree: 2,
      diagnostic: "The quadratic discriminant is negative.")

    let solution = expression.solvePolynomial(withRespectTo: parameterID)

    #expect(solution == expected)
    #expect(
      solution.approximated()
        == .noRealRoots(
          degree: 2,
          diagnostic: "The quadratic discriminant is negative."))
  }

  @Test("The bounded polynomial solver reports unsupported and invalid inputs")
  func polynomialBoundaryIsExplicit() {
    let parameterID = ScalarParameterID()
    let parameter = ScalarExpression.parameter(.identified(parameterID))
    let cubic = ScalarExpression.arithmetic(
      left: parameter,
      operation: .power,
      right: .constant(3))

    #expect(
      cubic.solvePolynomial(withRespectTo: parameterID)
        == .unsupported(
          diagnostic: "A polynomial power must be a bounded nonnegative integer constant."))
    #expect(
      ScalarExpression.constant(.infinity).solvePolynomial(withRespectTo: parameterID)
        == .invalid(diagnostic: "A scalar constant must be finite."))
  }
}
