import Foundation
import Testing

@testable import DynamicGeometry

@Suite("Parametric curves")
struct ParametricCurveTests {
  @Test("A parametric circle samples in order and persists its semantic definition")
  func samplesCircle() throws {
    let horizontal = try ScalarFunction1D(
      independentVariableName: "t",
      expression: .function(.cosine, argument: .parameter(.named("t"))))
    let vertical = try ScalarFunction1D(
      independentVariableName: "t",
      expression: .function(.sine, argument: .parameter(.named("t"))))
    let curve = try ParametricCurveDefinition(
      horizontalFunction: horizontal,
      verticalFunction: vertical,
      parameterDomain: 0...(2 * Double.pi))

    let result = try curve.sample(sampleCount: 5)

    let points = try #require(result.branches.first?.points)
    #expect(result.branches.count == 1)
    #expect(result.diagnostics.isEmpty)
    #expect(points.count == 5)
    #expect(points[0].distance(to: Point2D(x: 1, y: 0)) < 0.000_000_001)
    #expect(points[1].distance(to: Point2D(x: 0, y: 1)) < 0.000_000_001)
    #expect(
      try JSONDecoder().decode(
        ParametricCurveDefinition.self,
        from: JSONEncoder().encode(curve)) == curve)
  }

  @Test("An undefined parametric sample splits branches instead of bridging the gap")
  func splitsUndefinedBranch() throws {
    let horizontal = try ScalarFunction1D(
      independentVariableName: "t",
      expression: .parameter(.named("t")))
    let vertical = try ScalarFunction1D(
      independentVariableName: "t",
      expression: .arithmetic(
        left: .constant(1),
        operation: .division,
        right: .parameter(.named("t"))))
    let curve = try ParametricCurveDefinition(
      horizontalFunction: horizontal,
      verticalFunction: vertical,
      parameterDomain: -1...1)

    let result = try curve.sample(sampleCount: 5)

    #expect(result.branches.count == 2)
    #expect(result.branches[0].points.allSatisfy { $0.x < 0 })
    #expect(result.branches[1].points.allSatisfy { $0.x > 0 })
    #expect(result.diagnostics.contains { $0.input == 0 && $0.outcome.value == nil })
  }

  @Test("Midpoint probing prevents a parametric pole from being bridged")
  func detectsPoleBetweenSamples() throws {
    let horizontal = try ScalarFunction1D(
      independentVariableName: "t",
      expression: .parameter(.named("t")))
    let vertical = try ScalarFunction1D(
      independentVariableName: "t",
      expression: .arithmetic(
        left: .constant(1),
        operation: .division,
        right: .parameter(.named("t"))))
    let curve = try ParametricCurveDefinition(
      horizontalFunction: horizontal,
      verticalFunction: vertical,
      parameterDomain: -1...1)

    let result = try curve.sample(sampleCount: 4)

    #expect(result.branches.count == 2)
    #expect(result.branches[0].points.allSatisfy { $0.x < 0 })
    #expect(result.branches[1].points.allSatisfy { $0.x > 0 })
    #expect(result.diagnostics.contains { abs($0.input) < 0.000_000_000_001 })
  }
}

@Suite("Polar curves")
struct PolarCurveTests {
  @Test("A polar circle converts to the requested coordinate system and persists")
  func samplesCircleInScreenCoordinates() throws {
    let curve = try PolarCurveDefinition(
      radiusFunction: ScalarFunction1D(
        independentVariableName: "theta",
        expression: .constant(2)),
      angleDomain: 0...(2 * Double.pi),
      coordinateSystem: .screenYDown)

    let result = try curve.sample(sampleCount: 5)

    let points = try #require(result.branches.first?.points)
    #expect(result.branches.count == 1)
    #expect(result.diagnostics.isEmpty)
    #expect(points[0].distance(to: Point2D(x: 2, y: 0)) < 0.000_000_001)
    #expect(points[1].distance(to: Point2D(x: 0, y: -2)) < 0.000_000_001)
    #expect(
      try JSONDecoder().decode(
        PolarCurveDefinition.self,
        from: JSONEncoder().encode(curve)) == curve)
  }

  @Test("A polar radius pole creates separate drawable branches")
  func splitsAtRadiusPole() throws {
    let curve = try PolarCurveDefinition(
      radiusFunction: ScalarFunction1D(
        independentVariableName: "theta",
        expression: .arithmetic(
          left: .constant(1),
          operation: .division,
          right: .parameter(.named("theta")))),
      angleDomain: -1...1)

    let result = try curve.sample(sampleCount: 4)

    #expect(result.branches.count == 2)
    #expect(result.diagnostics.contains { abs($0.input) < 0.000_000_000_001 })
  }
}

@Suite("Implicit curves")
struct ImplicitCurveTests {
  @Test("A bounded grid extracts a persistent approximate circle contour")
  func extractsCircleContour() throws {
    let squaredX = ScalarExpression.arithmetic(
      left: .parameter(.named("x")),
      operation: .power,
      right: .constant(2))
    let squaredY = ScalarExpression.arithmetic(
      left: .parameter(.named("y")),
      operation: .power,
      right: .constant(2))
    let function = try ScalarFunction2D(
      expression: .arithmetic(
        left: .arithmetic(
          left: squaredX,
          operation: .addition,
          right: squaredY),
        operation: .subtraction,
        right: .constant(1)))
    let curve = try ImplicitCurveDefinition(
      relation: function,
      horizontalDomain: -1.25...1.25,
      verticalDomain: -1.25...1.25)

    let result = try curve.extractContours(columns: 32, rows: 32)

    #expect(!result.segments.isEmpty)
    #expect(result.diagnostics.isEmpty)
    #expect(result.coverage == .boundedApproximation)
    for point in result.segments.flatMap({ [$0.start, $0.end] }) {
      #expect((-1.25...1.25).contains(point.x))
      #expect((-1.25...1.25).contains(point.y))
      #expect(abs((point.x * point.x) + (point.y * point.y) - 1) < 0.02)
    }
    #expect(
      try JSONDecoder().decode(
        ImplicitCurveDefinition.self,
        from: JSONEncoder().encode(curve)) == curve)
  }

  @Test("A contour hidden inside one grid cell is reported as unresolved")
  func reportsContourHiddenWithinCell() throws {
    let squaredX = ScalarExpression.arithmetic(
      left: .parameter(.named("x")),
      operation: .power,
      right: .constant(2))
    let squaredY = ScalarExpression.arithmetic(
      left: .parameter(.named("y")),
      operation: .power,
      right: .constant(2))
    let relation = try ScalarFunction2D(
      expression: .arithmetic(
        left: .arithmetic(
          left: squaredX,
          operation: .addition,
          right: squaredY),
        operation: .subtraction,
        right: .constant(0.25)))
    let curve = try ImplicitCurveDefinition(
      relation: relation,
      horizontalDomain: -1...1,
      verticalDomain: -1...1)

    let result = try curve.extractContours(columns: 1, rows: 1)

    #expect(result.segments.isEmpty)
    #expect(result.diagnostics.map(\.kind) == [.unresolvedTopology])
  }

  @Test("A checkerboard cell is reported as ambiguous instead of inventing topology")
  func reportsAmbiguousCell() throws {
    let relation = try ScalarFunction2D(
      expression: .arithmetic(
        left: .parameter(.named("x")),
        operation: .multiplication,
        right: .parameter(.named("y"))))
    let curve = try ImplicitCurveDefinition(
      relation: relation,
      horizontalDomain: -1...1,
      verticalDomain: -1...1)

    let result = try curve.extractContours(columns: 1, rows: 1)

    #expect(result.segments.isEmpty)
    let diagnostic = try #require(result.diagnostics.first)
    #expect(diagnostic.kind == .ambiguousTopology)
    #expect(diagnostic.column == 0)
    #expect(diagnostic.row == 0)
    #expect(diagnostic.cornerOutcomes.compactMap(\.value) == [1, -1, 1, -1])
  }
}
