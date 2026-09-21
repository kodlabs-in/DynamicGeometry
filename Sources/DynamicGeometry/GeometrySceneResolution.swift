import Foundation

extension GeometryScene {
  func validateEntity(
    _ id: GeometryID,
    cache: inout [GeometryID: ResolvedGeometry]
  ) throws {
    guard let entity = entities[id] else {
      throw GeometryError.missingEntity(id)
    }
    var visiting: Set<GeometryID> = []
    switch entity {
    case .point:
      _ = try resolvePoint(id, visiting: &visiting, cache: &cache)
    case .circle:
      _ = try resolveCircle(id, visiting: &visiting, cache: &cache)
    case .ellipse:
      _ = try resolveEllipse(id, visiting: &visiting, cache: &cache)
    case .segment:
      _ = try resolveSegment(id, visiting: &visiting, cache: &cache)
    case .line:
      _ = try resolveLine(id, visiting: &visiting, cache: &cache)
    case .ray:
      _ = try resolveRay(id, visiting: &visiting, cache: &cache)
    }
  }

  func resolvePoint(
    _ id: GeometryID,
    visiting: inout Set<GeometryID>,
    cache: inout [GeometryID: ResolvedGeometry]
  ) throws -> Point2D {
    if case .point(let point) = cache[id] {
      return point
    }
    try beginResolving(id, visiting: &visiting)
    defer { visiting.remove(id) }
    guard case .point(let definition) = entities[id] else {
      throw try typeError(for: id, expected: "point")
    }
    let point = try resolvePointDefinition(definition, visiting: &visiting, cache: &cache)
    cache[id] = .point(point)
    return point
  }

  private func resolvePointDefinition(
    _ definition: PointDefinition,
    visiting: inout Set<GeometryID>,
    cache: inout [GeometryID: ResolvedGeometry]
  ) throws -> Point2D {
    switch definition {
    case .free(let freePoint):
      return freePoint
    case .computed(let x, let y):
      return Point2D(x: try scalarValue(x), y: try scalarValue(y))
    case .onCircle(let circleID, let angleRadians):
      let circle = try resolveCircle(circleID, visiting: &visiting, cache: &cache)
      return try circle.point(at: angleRadians, coordinateSystem: coordinateSystem)
    case .onCircleExpression(let circleID, let angleRadians):
      let circle = try resolveCircle(circleID, visiting: &visiting, cache: &cache)
      return try circle.point(
        at: scalarValue(angleRadians),
        coordinateSystem: coordinateSystem)
    case .horizontalProjection(let sourceID, let y):
      let source = try resolvePoint(sourceID, visiting: &visiting, cache: &cache)
      return Point2D(x: source.x, y: y)
    case .horizontalProjectionExpression(let sourceID, let y):
      let source = try resolvePoint(sourceID, visiting: &visiting, cache: &cache)
      return Point2D(x: source.x, y: try scalarValue(y))
    case .verticalProjection(let sourceID, let x):
      let source = try resolvePoint(sourceID, visiting: &visiting, cache: &cache)
      return Point2D(x: x, y: source.y)
    case .verticalProjectionExpression(let sourceID, let x):
      let source = try resolvePoint(sourceID, visiting: &visiting, cache: &cache)
      return Point2D(x: try scalarValue(x), y: source.y)
    }
  }

  func resolveCircle(
    _ id: GeometryID,
    visiting: inout Set<GeometryID>,
    cache: inout [GeometryID: ResolvedGeometry]
  ) throws -> Circle2D {
    if case .circle(let circle) = cache[id] {
      return circle
    }
    try beginResolving(id, visiting: &visiting)
    defer { visiting.remove(id) }
    guard case .circle(let definition) = entities[id] else {
      throw try typeError(for: id, expected: "circle")
    }
    let circle = try Circle2D(
      center: resolvePoint(definition.center, visiting: &visiting, cache: &cache),
      radius: scalarValue(definition.radius))
    cache[id] = .circle(circle)
    return circle
  }

  func resolveEllipse(
    _ id: GeometryID,
    visiting: inout Set<GeometryID>,
    cache: inout [GeometryID: ResolvedGeometry]
  ) throws -> Ellipse2D {
    if case .ellipse(let ellipse) = cache[id] {
      return ellipse
    }
    try beginResolving(id, visiting: &visiting)
    defer { visiting.remove(id) }
    guard case .ellipse(let definition) = entities[id] else {
      throw try typeError(for: id, expected: "ellipse")
    }
    let ellipse = try Ellipse2D(
      center: resolvePoint(definition.center, visiting: &visiting, cache: &cache),
      radiusX: scalarValue(definition.radiusX),
      radiusY: scalarValue(definition.radiusY))
    cache[id] = .ellipse(ellipse)
    return ellipse
  }

  func resolveSegment(
    _ id: GeometryID,
    visiting: inout Set<GeometryID>,
    cache: inout [GeometryID: ResolvedGeometry]
  ) throws -> Segment2D {
    if case .segment(let segment) = cache[id] {
      return segment
    }
    try beginResolving(id, visiting: &visiting)
    defer { visiting.remove(id) }
    guard case .segment(let definition) = entities[id] else {
      throw try typeError(for: id, expected: "segment")
    }
    let segment = try Segment2D(
      start: resolvePoint(definition.start, visiting: &visiting, cache: &cache),
      end: resolvePoint(definition.end, visiting: &visiting, cache: &cache))
    cache[id] = .segment(segment)
    return segment
  }

  func resolveLine(
    _ id: GeometryID,
    visiting: inout Set<GeometryID>,
    cache: inout [GeometryID: ResolvedGeometry]
  ) throws -> Line2D {
    if case .line(let line) = cache[id] {
      return line
    }
    try beginResolving(id, visiting: &visiting)
    defer { visiting.remove(id) }
    guard case .line(let definition) = entities[id] else {
      throw try typeError(for: id, expected: "line")
    }
    let line = try Line2D(
      first: resolvePoint(definition.first, visiting: &visiting, cache: &cache),
      second: resolvePoint(definition.second, visiting: &visiting, cache: &cache))
    cache[id] = .line(line)
    return line
  }

  func resolveRay(
    _ id: GeometryID,
    visiting: inout Set<GeometryID>,
    cache: inout [GeometryID: ResolvedGeometry]
  ) throws -> Ray2D {
    if case .ray(let ray) = cache[id] {
      return ray
    }
    try beginResolving(id, visiting: &visiting)
    defer { visiting.remove(id) }
    guard case .ray(let definition) = entities[id] else {
      throw try typeError(for: id, expected: "ray")
    }
    let ray = try Ray2D(
      origin: resolvePoint(definition.origin, visiting: &visiting, cache: &cache),
      through: resolvePoint(definition.through, visiting: &visiting, cache: &cache))
    cache[id] = .ray(ray)
    return ray
  }

  func beginResolving(
    _ id: GeometryID,
    visiting: inout Set<GeometryID>
  ) throws {
    guard entities[id] != nil else {
      throw GeometryError.missingEntity(id)
    }
    guard visiting.insert(id).inserted else {
      throw GeometryError.cyclicDependency(id)
    }
  }

  func typeError(for id: GeometryID, expected: String) throws -> GeometryError {
    guard entities[id] != nil else {
      throw GeometryError.missingEntity(id)
    }
    return GeometryError.unexpectedEntity(id, expected: expected)
  }

  func scalarValue(_ expression: ScalarExpression) throws -> Double {
    for id in expression.referencedParameterIDs where parameters[id] == nil {
      throw ScalarParameterError.missingParameter(id)
    }
    let bindings = orderedParameterIDs.compactMap { parameters[$0] }
    switch expression.evaluate(parameters: bindings) {
    case .exact(let value, _), .approximate(let value, _):
      return value
    case .undefined(let diagnostic):
      throw GeometryResolutionFailure.undefined(diagnostic)
    case .unsupported(let diagnostic):
      throw GeometryResolutionFailure.unsupported(diagnostic)
    case .nonconvergent(let diagnostic):
      throw GeometryResolutionFailure.nonconvergent(diagnostic)
    case .pending(let diagnostic):
      throw GeometryResolutionFailure.pending(diagnostic)
    }
  }

  mutating func resolveAndCache(_ ids: [GeometryID]) throws {
    var cache = resolvedEntities
    for id in ids {
      cache.removeValue(forKey: id)
    }
    for id in ids {
      try validateEntity(id, cache: &cache)
    }
    resolvedEntities = cache
    for id in ids {
      evaluationFailures.removeValue(forKey: id)
    }
  }

  mutating func resolveAndCacheRecoverably(_ ids: [GeometryID]) throws {
    var cache = resolvedEntities
    var failures = evaluationFailures
    for id in ids {
      cache.removeValue(forKey: id)
      failures.removeValue(forKey: id)
    }
    for id in ids {
      do {
        try validateEntity(id, cache: &cache)
      } catch let failure as GeometryResolutionFailure {
        failures[id] = failure
      } catch let error as GeometryError {
        guard let failure = evaluationFailure(for: error) else {
          throw error
        }
        failures[id] = failure
      }
    }
    resolvedEntities = cache
    evaluationFailures = failures
  }

  mutating func rebuildResolvedEntities() throws {
    try validateIdentity()
    for entity in entities.values {
      try validateLiteralInputs(entity)
    }
    resolvedEntities = [:]
    evaluationFailures = [:]
    try resolveAndCacheRecoverably(orderedIDs)
  }

  mutating func updateReverseDependencies(
    for id: GeometryID,
    from oldDependencies: [GeometryID],
    to newDependencies: [GeometryID]
  ) {
    let oldDependencySet = Set(oldDependencies)
    let newDependencySet = Set(newDependencies)
    for dependencyID in oldDependencySet.subtracting(newDependencySet) {
      reverseDependencies[dependencyID]?.remove(id)
      if reverseDependencies[dependencyID]?.isEmpty == true {
        reverseDependencies.removeValue(forKey: dependencyID)
      }
    }
    for dependencyID in newDependencySet.subtracting(oldDependencySet) {
      reverseDependencies[dependencyID, default: []].insert(id)
    }
  }

  mutating func updateParameterDependents(
    for id: GeometryID,
    from oldDependencies: [ScalarParameterID],
    to newDependencies: [ScalarParameterID]
  ) {
    let oldDependencySet = Set(oldDependencies)
    let newDependencySet = Set(newDependencies)
    for parameterID in oldDependencySet.subtracting(newDependencySet) {
      parameterDependents[parameterID]?.remove(id)
      if parameterDependents[parameterID]?.isEmpty == true {
        parameterDependents.removeValue(forKey: parameterID)
      }
    }
    for parameterID in newDependencySet.subtracting(oldDependencySet) {
      parameterDependents[parameterID, default: []].insert(id)
    }
  }

  static func makeReverseDependencies(
    from entities: [GeometryID: GeometryEntity]
  ) -> [GeometryID: Set<GeometryID>] {
    var result: [GeometryID: Set<GeometryID>] = [:]
    for (id, entity) in entities {
      for dependencyID in entity.dependencyIDs {
        result[dependencyID, default: []].insert(id)
      }
    }
    return result
  }

  static func makeParameterDependents(
    from entities: [GeometryID: GeometryEntity]
  ) -> [ScalarParameterID: Set<GeometryID>] {
    var result: [ScalarParameterID: Set<GeometryID>] = [:]
    for (id, entity) in entities {
      for parameterID in entity.referencedParameterIDs {
        result[parameterID, default: []].insert(id)
      }
    }
    return result
  }

  func affectedEntityIDs(startingAt rootID: GeometryID) -> [GeometryID] {
    affectedEntityIDs(startingAt: [rootID])
  }

  func affectedEntityIDs(startingAt rootIDs: Set<GeometryID>) -> [GeometryID] {
    var affected = rootIDs
    var pending = Array(rootIDs)
    while let id = pending.popLast() {
      for dependentID in reverseDependencies[id, default: []]
      where affected.insert(dependentID).inserted {
        pending.append(dependentID)
      }
    }
    return orderedIDs.filter { affected.contains($0) }
  }

  private func evaluationFailure(for error: GeometryError) -> GeometryResolutionFailure? {
    switch error {
    case .nonFiniteValue, .nonPositiveDimension, .undefinedDirection:
      return .undefined(error.localizedDescription)
    default:
      return nil
    }
  }
}
