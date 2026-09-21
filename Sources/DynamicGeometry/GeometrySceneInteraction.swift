/// Point interaction and scene validation.
extension GeometryScene {
  /// Moves a free point directly or projects a circle-constrained point onto its circle.
  public mutating func movePoint(_ id: GeometryID, to target: Point2D) throws {
    _ = try movePointReportingChanges(id, to: target)
  }

  /// Moves a point and reports the point and every transitive dependent in scene order.
  @discardableResult
  public mutating func movePointReportingChanges(
    _ id: GeometryID,
    to target: Point2D
  ) throws -> GeometrySceneChange {
    guard target.isFinite else {
      throw GeometryError.nonFiniteValue("Drag location")
    }
    guard case .point(let definition) = entities[id] else {
      throw try typeError(for: id, expected: "point")
    }
    switch definition {
    case .free:
      return try replaceReportingChanges(id, with: .point(.free(target)))
    case .onCircle(let circleID, let previousAngle):
      return try moveLiteralCirclePoint(
        id,
        circleID: circleID,
        previousAngle: previousAngle,
        target: target)
    case .onCircleExpression(let circleID, let angleExpression):
      return try moveExpressionCirclePoint(
        id,
        circleID: circleID,
        expression: angleExpression,
        target: target)
    default:
      throw GeometryError.readOnlyPoint(id)
    }
  }

  /// Validates scene identity and dependency structure without rejecting undefined values.
  public func validate() throws {
    try validateIdentity()
    for entity in entities.values {
      try validateLiteralInputs(entity)
    }
    var cache: [GeometryID: ResolvedGeometry] = [:]
    for id in orderedIDs {
      do {
        try validateEntity(id, cache: &cache)
      } catch is GeometryResolutionFailure {
        continue
      } catch let error as GeometryError where error.isRecoverableEvaluationFailure {
        continue
      }
    }
  }

  private mutating func moveLiteralCirclePoint(
    _ id: GeometryID,
    circleID: GeometryID,
    previousAngle: Double,
    target: Point2D
  ) throws -> GeometrySceneChange {
    guard
      let angle = try continuousDragAngle(
        on: circleID,
        toward: target,
        previousAngle: previousAngle)
    else {
      return GeometrySceneChange(affectedEntityIDs: [])
    }
    return try replaceReportingChanges(
      id,
      with: .point(.onCircle(circle: circleID, angleRadians: angle)))
  }

  private mutating func moveExpressionCirclePoint(
    _ id: GeometryID,
    circleID: GeometryID,
    expression: ScalarExpression,
    target: Point2D
  ) throws -> GeometrySceneChange {
    let previousAngle = try scalarValue(expression)
    guard
      let angle = try continuousDragAngle(
        on: circleID,
        toward: target,
        previousAngle: previousAngle)
    else {
      return GeometrySceneChange(affectedEntityIDs: [])
    }
    switch expression {
    case .parameter(.identified(let parameterID)):
      return try setParameter(parameterID, to: angle)
    case .constant:
      return try replaceReportingChanges(
        id,
        with: .point(
          .onCircleExpression(circle: circleID, angleRadians: .constant(angle))))
    default:
      throw GeometryError.readOnlyPoint(id)
    }
  }

  private func continuousDragAngle(
    on circleID: GeometryID,
    toward target: Point2D,
    previousAngle: Double
  ) throws -> Double? {
    let resolvedCircle = try circle(circleID)
    guard target != resolvedCircle.center else {
      return nil
    }
    let normalized = try resolvedCircle.angle(
      toward: target,
      coordinateSystem: coordinateSystem)
    let fullTurn = 2 * Double.pi
    let turnOffset = ((previousAngle - normalized) / fullTurn).rounded()
    return normalized + turnOffset * fullTurn
  }
}

extension GeometryError {
  var isRecoverableEvaluationFailure: Bool {
    switch self {
    case .nonFiniteValue, .nonPositiveDimension, .undefinedDirection:
      true
    default:
      false
    }
  }
}
