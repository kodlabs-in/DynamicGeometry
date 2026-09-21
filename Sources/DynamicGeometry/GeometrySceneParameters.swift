/// Scalar parameters and evaluated-state access for geometry scenes.
extension GeometryScene {
  /// Returns a scene-owned scalar parameter.
  public func parameter(_ id: ScalarParameterID) -> ScalarParameter? {
    parameters[id]
  }

  /// Adds an ordered scalar parameter to the scene.
  @discardableResult
  public mutating func addParameter(
    name: String,
    value: Double,
    id: ScalarParameterID = ScalarParameterID()
  ) throws -> ScalarParameterID {
    guard parameters[id] == nil else {
      throw ScalarParameterError.duplicateParameter(id)
    }
    let parameter = try ScalarParameter(id: id, name: name, value: value)
    parameters[id] = parameter
    orderedParameterIDs.append(id)
    return id
  }

  /// Changes a scene-owned scalar parameter and reports affected geometry.
  @discardableResult
  public mutating func setParameter(
    _ id: ScalarParameterID,
    to value: Double
  ) throws -> GeometrySceneChange {
    guard let previous = parameters[id] else {
      throw ScalarParameterError.missingParameter(id)
    }
    parameters[id] = try ScalarParameter(id: id, name: previous.name, value: value)
    let roots = parameterDependents[id, default: []]
    let affectedEntityIDs = affectedEntityIDs(startingAt: roots)
    do {
      try resolveAndCacheRecoverably(affectedEntityIDs)
    } catch {
      parameters[id] = previous
      throw error
    }
    return GeometrySceneChange(
      changedParameterIDs: [id],
      affectedEntityIDs: affectedEntityIDs)
  }

  /// Returns the current evaluated state of a point definition.
  public func pointEvaluation(_ id: GeometryID) -> GeometryEvaluationOutcome<Point2D> {
    evaluatedOutcome(id, expected: Point2D.self) {
      guard case .point(let point) = $0 else { return nil }
      return point
    }
  }

  /// Returns the current evaluated state of a circle definition.
  public func circleEvaluation(_ id: GeometryID) -> GeometryEvaluationOutcome<Circle2D> {
    evaluatedOutcome(id, expected: Circle2D.self) {
      guard case .circle(let circle) = $0 else { return nil }
      return circle
    }
  }

  /// Returns the current evaluated state of an ellipse definition.
  public func ellipseEvaluation(_ id: GeometryID) -> GeometryEvaluationOutcome<Ellipse2D> {
    evaluatedOutcome(id, expected: Ellipse2D.self) {
      guard case .ellipse(let ellipse) = $0 else { return nil }
      return ellipse
    }
  }

  /// Returns the current evaluated state of a segment definition.
  public func segmentEvaluation(_ id: GeometryID) -> GeometryEvaluationOutcome<Segment2D> {
    evaluatedOutcome(id, expected: Segment2D.self) {
      guard case .segment(let segment) = $0 else { return nil }
      return segment
    }
  }

  /// Returns the current evaluated state of a line definition.
  public func lineEvaluation(_ id: GeometryID) -> GeometryEvaluationOutcome<Line2D> {
    evaluatedOutcome(id, expected: Line2D.self) {
      guard case .line(let line) = $0 else { return nil }
      return line
    }
  }

  /// Returns the current evaluated state of a ray definition.
  public func rayEvaluation(_ id: GeometryID) -> GeometryEvaluationOutcome<Ray2D> {
    evaluatedOutcome(id, expected: Ray2D.self) {
      guard case .ray(let ray) = $0 else { return nil }
      return ray
    }
  }

  private func evaluatedOutcome<Value: Equatable & Sendable>(
    _ id: GeometryID,
    expected: Value.Type,
    extract: (ResolvedGeometry) -> Value?
  ) -> GeometryEvaluationOutcome<Value> {
    if let resolved = resolvedEntities[id], let value = extract(resolved) {
      return .approximate(
        value: value,
        diagnostic: "Finite resolved \(String(describing: expected)).")
    }
    if let failure = evaluationFailures[id] {
      return failure.outcome()
    }
    return .undefined(diagnostic: "Entity \(id) is not available as \(expected).")
  }
}
