import Foundation
import Testing

@testable import DynamicGeometry

@Suite("Parameter-driven scenes")
struct ParameterDrivenSceneTests {
  @Test("A scene owns ordered scalar parameters that can be changed")
  func ownsOrderedParameters() throws {
    var scene = GeometryScene()
    let radius = try scene.addParameter(name: "r", value: 2)
    let theta = try scene.addParameter(name: "theta", value: .pi / 4)

    #expect(scene.orderedParameterIDs == [radius, theta])
    #expect(scene.parameter(radius)?.value == 2)

    let change = try scene.setParameter(radius, to: 5)

    #expect(change.changedParameterIDs == [radius])
    #expect(change.affectedEntityIDs.isEmpty)
    #expect(scene.parameter(radius)?.value == 5)
  }

  @Test("An expression reports every stable parameter dependency once")
  func reportsReferencedParameters() {
    let radius = ScalarParameterID()
    let theta = ScalarParameterID()
    let expression = ScalarExpression.arithmetic(
      left: .parameter(.identified(radius)),
      operation: .multiplication,
      right: .arithmetic(
        left: .function(.cosine, argument: .parameter(.identified(theta))),
        operation: .addition,
        right: .parameter(.identified(radius))))

    #expect(expression.referencedParameterIDs == [radius, theta])
  }

  @Test("Shared parameters drive expression-backed geometry incrementally")
  func sharedParametersDriveGeometry() throws {
    var scene = GeometryScene()
    let radius = try scene.addParameter(name: "r", value: 2)
    let theta = try scene.addParameter(name: "theta", value: 0)
    let center = try scene.addPoint(.free(Point2D(x: 0, y: 0)))
    let circle = try scene.addCircle(
      center: center,
      radius: .parameter(.identified(radius)))
    let constrained = try scene.addPoint(
      .onCircleExpression(
        circle: circle,
        angleRadians: .parameter(.identified(theta))))
    let computed = try scene.addPoint(
      .computed(
        x: .arithmetic(
          left: .parameter(.identified(radius)),
          operation: .multiplication,
          right: .function(.cosine, argument: .parameter(.identified(theta)))),
        y: .arithmetic(
          left: .parameter(.identified(radius)),
          operation: .multiplication,
          right: .function(.sine, argument: .parameter(.identified(theta))))))

    let change = try scene.setParameter(theta, to: .pi / 2)

    #expect(change.changedParameterIDs == [theta])
    #expect(change.affectedEntityIDs == [constrained, computed])
    #expect(isClose(try scene.point(constrained).x, 0))
    #expect(isClose(try scene.point(constrained).y, 2))
    #expect(isClose(try scene.point(computed).x, 0))
    #expect(isClose(try scene.point(computed).y, 2))

    let radiusChange = try scene.setParameter(radius, to: 4)
    #expect(radiusChange.affectedEntityIDs == [circle, constrained, computed])
    #expect(isClose(try scene.circle(circle).radius, 4))
  }

  @Test("Numerically undefined geometry stays in the scene and can recover")
  func undefinedGeometryRecovers() throws {
    var scene = GeometryScene()
    let input = try scene.addParameter(name: "a", value: 4)
    let center = try scene.addPoint(.free(Point2D(x: 0, y: 0)))
    let circle = try scene.addCircle(
      center: center,
      radius: .function(
        .squareRoot,
        argument: .parameter(.identified(input))))
    let point = try scene.addPoint(.onCircle(circle: circle, angleRadians: 0))

    let invalidChange = try scene.setParameter(input, to: -1)

    #expect(invalidChange.affectedEntityIDs == [circle, point])
    #expect(scene.parameter(input)?.value == -1)
    #expect(
      scene.circleEvaluation(circle)
        == .undefined(diagnostic: "Square root requires a nonnegative argument."))
    #expect(scene.pointEvaluation(point).value == nil)

    let encoded = try JSONEncoder().encode(scene)
    var decoded = try JSONDecoder().decode(GeometryScene.self, from: encoded)
    #expect(decoded.circleEvaluation(circle).value == nil)

    _ = try decoded.setParameter(input, to: 9)

    #expect(decoded.circleEvaluation(circle).value?.radius == 3)
    #expect(decoded.pointEvaluation(point).value == Point2D(x: 3, y: 0))
  }

  @Test("Dragging a parameter-backed circle point updates every user of its angle")
  func draggingUpdatesSharedAngle() throws {
    var scene = GeometryScene()
    let theta = try scene.addParameter(name: "theta", value: 0)
    let center = try scene.addPoint(.free(Point2D(x: 0, y: 0)))
    let circle = try scene.addCircle(center: center, radius: 10)
    let first = try scene.addPoint(
      .onCircleExpression(
        circle: circle,
        angleRadians: .parameter(.identified(theta))))
    let second = try scene.addPoint(
      .onCircleExpression(
        circle: circle,
        angleRadians: .parameter(.identified(theta))))

    let change = try scene.movePointReportingChanges(first, to: Point2D(x: 0, y: 20))

    #expect(change.changedParameterIDs == [theta])
    #expect(change.affectedEntityIDs == [first, second])
    #expect(isClose(scene.parameter(theta)?.value ?? 0, .pi / 2))
    #expect(isClose(try scene.point(second).x, 0))
    #expect(isClose(try scene.point(second).y, 10))
  }

  @Test("Circle dragging unwraps angles continuously across a full turn")
  func draggingUnwrapsAngles() throws {
    var scene = GeometryScene()
    let theta = try scene.addParameter(name: "theta", value: 2 * .pi - 0.1)
    let center = try scene.addPoint(.free(Point2D(x: 0, y: 0)))
    let circle = try scene.addCircle(center: center, radius: 10)
    let point = try scene.addPoint(
      .onCircleExpression(
        circle: circle,
        angleRadians: .parameter(.identified(theta))))
    let targetAngle = 0.1

    _ = try scene.movePoint(
      point,
      to: Point2D(x: 20 * cos(targetAngle), y: 20 * sin(targetAngle)))

    #expect(isClose(scene.parameter(theta)?.value ?? 0, 2 * .pi + targetAngle))
  }

  @Test("Dragging to the circle centre preserves the previous angle")
  func centerDragPreservesAngle() throws {
    var scene = GeometryScene()
    let theta = try scene.addParameter(name: "theta", value: 1.25)
    let center = try scene.addPoint(.free(Point2D(x: 3, y: 4)))
    let circle = try scene.addCircle(center: center, radius: 10)
    let point = try scene.addPoint(
      .onCircleExpression(
        circle: circle,
        angleRadians: .parameter(.identified(theta))))

    let change = try scene.movePointReportingChanges(point, to: Point2D(x: 3, y: 4))

    #expect(change.changedParameterIDs.isEmpty)
    #expect(change.affectedEntityIDs.isEmpty)
    #expect(scene.parameter(theta)?.value == 1.25)
  }

  @Test("A non-invertible angle expression is read-only")
  func computedAngleIsReadOnly() throws {
    var scene = GeometryScene()
    let theta = try scene.addParameter(name: "theta", value: 0)
    let center = try scene.addPoint(.free(Point2D(x: 0, y: 0)))
    let circle = try scene.addCircle(center: center, radius: 10)
    let point = try scene.addPoint(
      .onCircleExpression(
        circle: circle,
        angleRadians: .arithmetic(
          left: .parameter(.identified(theta)),
          operation: .multiplication,
          right: .constant(2))))

    #expect(throws: GeometryError.readOnlyPoint(point)) {
      try scene.movePoint(point, to: Point2D(x: 0, y: 10))
    }
  }

  @Test("Version two scenes preserve parameters and expression relationships")
  func sceneRoundTripPreservesParameterRelationships() throws {
    var scene = GeometryScene()
    let radius = try scene.addParameter(name: "r", value: 3)
    let center = try scene.addPoint(.free(Point2D(x: 1, y: 2)))
    let circle = try scene.addCircle(
      center: center,
      radius: .parameter(.identified(radius)))

    let data = try JSONEncoder().encode(scene)
    var decoded = try JSONDecoder().decode(GeometryScene.self, from: data)

    #expect(GeometryScene.currentSchemaVersion == 2)
    #expect(decoded == scene)
    _ = try decoded.setParameter(radius, to: 7)
    #expect(try decoded.circle(circle).radius == 7)
  }

  @Test("Version one literal dimensions migrate to constant expressions")
  func legacyLiteralDimensionMigrates() throws {
    let center = GeometryID()
    let encodedCenter = try JSONEncoder().encode(center)
    let centerObject = try JSONSerialization.jsonObject(with: encodedCenter)
    let data = try JSONSerialization.data(withJSONObject: [
      "center": centerObject,
      "radius": 12.0,
    ])

    let definition = try JSONDecoder().decode(CircleDefinition.self, from: data)

    #expect(definition.radius == .constant(12))
  }

  @Test("Ellipse radii and projection coordinates accept expressions")
  func expressionsDriveEllipseAndProjections() throws {
    var scene = GeometryScene()
    let horizontalRadius = try scene.addParameter(name: "rx", value: 6)
    let verticalRadius = try scene.addParameter(name: "ry", value: 3)
    let axis = try scene.addParameter(name: "axis", value: 2)
    let center = try scene.addPoint(.free(Point2D(x: 1, y: 1)))
    let source = try scene.addPoint(.free(Point2D(x: 8, y: 9)))
    let ellipse = try scene.addEllipse(
      center: center,
      radiusX: .parameter(.identified(horizontalRadius)),
      radiusY: .parameter(.identified(verticalRadius)))
    let horizontal = try scene.addPoint(
      .horizontalProjectionExpression(
        of: source,
        ontoY: .parameter(.identified(axis))))
    let vertical = try scene.addPoint(
      .verticalProjectionExpression(
        of: source,
        ontoX: .negation(.parameter(.identified(axis)))))

    #expect(try scene.ellipse(ellipse).radiusX == 6)
    #expect(try scene.ellipse(ellipse).radiusY == 3)
    #expect(try scene.point(horizontal) == Point2D(x: 8, y: 2))
    #expect(try scene.point(vertical) == Point2D(x: -2, y: 9))

    let change = try scene.setParameter(axis, to: 5)
    #expect(change.affectedEntityIDs == [horizontal, vertical])
    #expect(try scene.point(horizontal) == Point2D(x: 8, y: 5))
    #expect(try scene.point(vertical) == Point2D(x: -5, y: 9))
  }

  @Test("A missing scalar dependency rejects insertion atomically")
  func missingParameterRejectsInsertion() throws {
    var scene = GeometryScene()
    let center = try scene.addPoint(.free(Point2D(x: 0, y: 0)))
    let missing = ScalarParameterID()

    #expect(throws: ScalarParameterError.missingParameter(missing)) {
      try scene.addCircle(
        center: center,
        radius: .parameter(.identified(missing)))
    }
    #expect(scene.orderedIDs == [center])
  }
}

private func isClose(_ first: Double, _ second: Double, tolerance: Double = 0.000_000_1) -> Bool {
  abs(first - second) <= tolerance
}
