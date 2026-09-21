import Foundation
import Testing

@testable import DynamicGeometry

@Suite("Scalar functions")
struct ScalarFunction1DTests {
  @Test("An independent variable and additional parameters evaluate through one function")
  func evaluatesIndependentVariableAndParameter() throws {
    let variableID = ScalarParameterID()
    let scale = try ScalarParameter(name: "a", value: 2)
    let function = try ScalarFunction1D(
      independentVariableID: variableID,
      independentVariableName: "x",
      expression: .arithmetic(
        left: .parameter(.named("a")),
        operation: .multiplication,
        right: .arithmetic(
          left: .parameter(.identified(variableID)),
          operation: .power,
          right: .constant(2))))

    let outcome = function.evaluate(at: 3, parameters: [scale])

    #expect(outcome.value == 18)
    #expect(
      try JSONDecoder().decode(
        ScalarFunction1D.self,
        from: JSONEncoder().encode(function)) == function)
  }

  @Test("A non-finite independent input is explicitly undefined")
  func rejectsNonFiniteInput() throws {
    let function = try ScalarFunction1D(expression: .parameter(.named("x")))

    guard case .undefined(let diagnostic) = function.evaluate(at: .infinity) else {
      Issue.record("Expected a structured undefined result")
      return
    }

    #expect(diagnostic.contains("finite"))
  }
}

@Suite("Explicit curves")
struct ExplicitCurveTests {
  @Test("A quadratic samples into one ordered branch and persists its definition")
  func samplesQuadratic() throws {
    let function = try ScalarFunction1D(
      expression: .arithmetic(
        left: .parameter(.named("x")),
        operation: .power,
        right: .constant(2)))
    let curve = try ExplicitCurveDefinition(function: function, domain: -2...2)

    let result = try curve.sample(sampleCount: 5)

    #expect(result.diagnostics.isEmpty)
    #expect(
      result.branches.map(\.points) == [
        [
          Point2D(x: -2, y: 4),
          Point2D(x: -1, y: 1),
          Point2D(x: 0, y: 0),
          Point2D(x: 1, y: 1),
          Point2D(x: 2, y: 4),
        ]
      ])
    #expect(
      try JSONDecoder().decode(
        ExplicitCurveDefinition.self,
        from: JSONEncoder().encode(curve)) == curve)
  }

  @Test("A reciprocal curve never connects samples across its pole")
  func splitsReciprocalAtZero() throws {
    let function = try ScalarFunction1D(
      expression: .arithmetic(
        left: .constant(1),
        operation: .division,
        right: .parameter(.named("x"))))
    let curve = try ExplicitCurveDefinition(function: function, domain: -1...1)

    let result = try curve.sample(sampleCount: 4)

    #expect(result.branches.count == 2)
    #expect(result.branches[0].points.allSatisfy { $0.x < 0 })
    #expect(result.branches[1].points.allSatisfy { $0.x > 0 })
    #expect(
      result.diagnostics.contains {
        abs($0.input) < 0.000_000_000_001 && $0.outcome.value == nil
      })
  }

  @Test("Curve domains and sample counts reject unusable values")
  func validatesCurveInputs() throws {
    let function = try ScalarFunction1D(expression: .constant(1))

    #expect(throws: FunctionConstructionError.nonFiniteBounds) {
      _ = try ExplicitCurveDefinition(function: function, domain: 0...Double.infinity)
    }
    #expect(throws: FunctionConstructionError.invalidBounds) {
      _ = try ExplicitCurveDefinition(function: function, domain: 1...1)
    }
    let curve = try ExplicitCurveDefinition(function: function, domain: 0...1)
    #expect(throws: FunctionConstructionError.invalidSampleCount(minimum: 2)) {
      _ = try curve.sample(sampleCount: 1)
    }
  }
}

@Suite("Riemann sums")
struct RiemannSumTests {
  @Test("Left, right, and midpoint rules derive the expected x-squared rectangles")
  func derivesQuadraticRectangles() throws {
    let function = try ScalarFunction1D(
      expression: .arithmetic(
        left: .parameter(.named("x")),
        operation: .power,
        right: .constant(2)))
    let expectations = [
      RiemannExpectation(rule: .left, sampleInputs: [0, 0.5, 1, 1.5], sum: 1.75),
      RiemannExpectation(rule: .right, sampleInputs: [0.5, 1, 1.5, 2], sum: 3.75),
      RiemannExpectation(
        rule: .midpoint,
        sampleInputs: [0.25, 0.75, 1.25, 1.75],
        sum: 2.625),
    ]

    for expectation in expectations {
      let definition = try RiemannSumDefinition(
        function: function,
        interval: 0...2,
        rectangleCount: 4,
        samplingRule: expectation.rule)
      let result = definition.evaluate()

      #expect(result.rectangles.map(\.sampleInput) == expectation.sampleInputs)
      #expect(isClose(try #require(result.signedSum.value), expectation.sum))
      #expect(
        try JSONDecoder().decode(
          RiemannSumDefinition.self,
          from: JSONEncoder().encode(definition)) == definition)
    }
  }

  @Test("Rectangles below the axis contribute negative signed area")
  func preservesNegativeSignedArea() throws {
    let definition = try RiemannSumDefinition(
      function: ScalarFunction1D(expression: .constant(-2)),
      interval: 0...3,
      rectangleCount: 3,
      samplingRule: .midpoint)

    let result = definition.evaluate()

    #expect(result.rectangles.map(\.height) == [-2, -2, -2])
    #expect(result.rectangles.map(\.signedArea) == [-2, -2, -2])
    #expect(result.signedSum.value == -6)
  }

  @Test("An undefined sample never becomes a zero-height rectangle")
  func reportsUndefinedSample() throws {
    let function = try ScalarFunction1D(
      expression: .arithmetic(
        left: .constant(1),
        operation: .division,
        right: .parameter(.named("x"))))
    let definition = try RiemannSumDefinition(
      function: function,
      interval: -1...1,
      rectangleCount: 1,
      samplingRule: .midpoint)

    let result = definition.evaluate()

    #expect(result.rectangles.isEmpty)
    guard case .undefined(let diagnostic) = result.signedSum else {
      Issue.record("Expected an undefined signed sum")
      return
    }
    #expect(diagnostic.contains("zero"))
  }

  @Test("Stored definitions exclude derived rectangles and reject invalid counts")
  func storesOnlySemanticDefinition() throws {
    let function = try ScalarFunction1D(expression: .constant(1))
    #expect(throws: FunctionConstructionError.invalidSampleCount(minimum: 1)) {
      _ = try RiemannSumDefinition(
        function: function,
        interval: 0...1,
        rectangleCount: 0,
        samplingRule: .left)
    }
    let definition = try RiemannSumDefinition(
      function: function,
      interval: 0...1,
      rectangleCount: 2,
      samplingRule: .left)

    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(definition)) as? [String: Any])

    #expect(object["rectangles"] == nil)
    #expect(object["signedSum"] == nil)
  }
}

private struct RiemannExpectation {
  let rule: RiemannSamplingRule
  let sampleInputs: [Double]
  let sum: Double
}

private func isClose(_ left: Double, _ right: Double, tolerance: Double = 0.000_000_001) -> Bool {
  abs(left - right) <= tolerance
}
