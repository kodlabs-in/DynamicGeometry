import Foundation
import Testing

@testable import DynamicGeometry

@Suite("Scalar expressions")
struct ScalarExpressionTests {
  @Test("A finite literal evaluates as an exact value")
  func finiteLiteralIsExact() {
    let expression = ScalarExpression.constant(42)

    #expect(expression.evaluate() == .exact(value: 42, diagnostic: "Finite literal."))
  }

  @Test("A non-finite literal is undefined instead of leaking invalid arithmetic")
  func nonFiniteLiteralIsUndefined() {
    let expression = ScalarExpression.constant(.infinity)

    #expect(
      expression.evaluate()
        == .undefined(diagnostic: "A scalar constant must be finite."))
  }

  @Test("A parameter can be evaluated through its stable identifier")
  func evaluatesParameterByIdentifier() throws {
    let id = ScalarParameterID(
      rawValue: try #require(UUID(uuidString: "88AFB508-1D4D-4EAF-9908-258D70E104F2")))
    let parameter = try ScalarParameter(id: id, name: "theta", value: .pi / 2)
    let expression = ScalarExpression.parameter(.identified(id))

    #expect(
      expression.evaluate(parameters: [parameter])
        == .exact(value: .pi / 2, diagnostic: "Parameter theta."))
  }

  @Test("A missing named parameter produces an undefined result")
  func missingNamedParameterIsUndefined() {
    let expression = ScalarExpression.parameter(.named("radius"))

    #expect(
      expression.evaluate()
        == .undefined(diagnostic: "No scalar parameter named radius was supplied."))
  }

  @Test("Standard arithmetic operators evaluate to finite approximations")
  func evaluatesArithmeticOperators() {
    let expectations: [(ScalarArithmeticOperator, Double)] = [
      (.addition, 9),
      (.subtraction, 5),
      (.multiplication, 14),
      (.division, 3.5),
      (.power, 49),
    ]

    for (operation, expected) in expectations {
      let expression = ScalarExpression.arithmetic(
        left: .constant(7),
        operation: operation,
        right: .constant(2))

      #expect(expression.evaluate().value == expected)
      #expect(expression.evaluate().isApproximate)
    }
  }

  @Test("Unary negation preserves an exact operand")
  func evaluatesUnaryNegation() {
    let expression = ScalarExpression.negation(.constant(4))

    #expect(expression.evaluate() == .exact(value: -4, diagnostic: "Exact negation."))
  }

  @Test("Common scalar functions evaluate to finite approximations")
  func evaluatesCommonFunctions() throws {
    let expectations: [FunctionExpectation] = [
      FunctionExpectation(function: .sine, argument: .constant(.pi / 2), expected: 1),
      FunctionExpectation(function: .cosine, argument: .constant(0), expected: 1),
      FunctionExpectation(function: .tangent, argument: .constant(.pi / 4), expected: 1),
      FunctionExpectation(function: .absoluteValue, argument: .constant(-3), expected: 3),
      FunctionExpectation(function: .squareRoot, argument: .constant(9), expected: 3),
      FunctionExpectation(
        function: .naturalLogarithm,
        argument: .constant(Foundation.exp(1)),
        expected: 1),
      FunctionExpectation(
        function: .exponential,
        argument: .constant(1),
        expected: Foundation.exp(1)),
    ]

    for expectation in expectations {
      let outcome = ScalarExpression.function(
        expectation.function,
        argument: expectation.argument
      ).evaluate()

      #expect(outcome.isApproximate)
      #expect(abs(try #require(outcome.value) - expectation.expected) < 0.000_000_001)
    }
  }

  @Test("Invalid function domains produce structured undefined results")
  func invalidFunctionDomainsAreUndefined() {
    let expectations: [(ScalarExpression, String)] = [
      (
        .function(.squareRoot, argument: .constant(-1)),
        "Square root requires a nonnegative argument."
      ),
      (
        .function(.naturalLogarithm, argument: .constant(0)),
        "Natural logarithm requires a positive argument."
      ),
      (
        .function(.tangent, argument: .constant(.pi / 2)),
        "Tangent is undefined where cosine is zero."
      ),
    ]

    for (expression, diagnostic) in expectations {
      #expect(expression.evaluate() == .undefined(diagnostic: diagnostic))
    }
  }

  @Test("Decoding cannot bypass finite parameter validation")
  func decodedParametersRemainFinite() throws {
    let id = ScalarParameterID(
      rawValue: try #require(UUID(uuidString: "8DE2427D-945B-49CF-8711-3E1B3AC14B52")))
    let data = Data(
      #"{"id":{"rawValue":"8DE2427D-945B-49CF-8711-3E1B3AC14B52"},"name":"bad","value":"NaN"}"#
        .utf8)
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(
      positiveInfinity: "Infinity",
      negativeInfinity: "-Infinity",
      nan: "NaN")

    #expect(throws: ScalarValidationError.nonFiniteParameterValue(id)) {
      try decoder.decode(ScalarParameter.self, from: data)
    }
  }

  @Test("A duplicate parameter name is reported as ambiguous")
  func duplicateParameterNamesAreUndefined() throws {
    let first = try ScalarParameter(name: "radius", value: 10)
    let second = try ScalarParameter(name: "radius", value: 20)
    let expression = ScalarExpression.parameter(.named("radius"))

    #expect(
      expression.evaluate(parameters: [first, second])
        == .undefined(diagnostic: "Multiple scalar parameters are named radius."))
  }

  @Test("Expression validation rejects a non-finite constant")
  func validatesFiniteConstants() {
    let expression = ScalarExpression.constant(.nan)

    #expect(throws: ScalarValidationError.nonFiniteConstant) {
      try expression.validate()
    }
  }
}

private struct FunctionExpectation {
  let function: ScalarFunction
  let argument: ScalarExpression
  let expected: Double
}
