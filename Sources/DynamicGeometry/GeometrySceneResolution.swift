/// The observable result of a successful scene mutation.
public struct GeometrySceneChange: Equatable, Sendable {
  /// Changed entities in stable scene order, including the mutation root and its dependents.
  public let affectedEntityIDs: [GeometryID]
}

enum ResolvedGeometry: Equatable, Sendable {
  case point(Point2D)
  case circle(Circle2D)
  case ellipse(Ellipse2D)
  case segment(Segment2D)
  case line(Line2D)
  case ray(Ray2D)
}

extension GeometryScene {
  func validateIdentity() throws {
    guard orderedIDs.count == Set(orderedIDs).count else {
      throw GeometryError.inconsistentScene
    }
    guard Set(orderedIDs) == Set(entities.keys) else {
      throw GeometryError.inconsistentScene
    }
  }

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
    let point: Point2D
    switch definition {
    case .free(let freePoint):
      guard freePoint.isFinite else {
        throw GeometryError.nonFiniteValue("Point")
      }
      point = freePoint
    case .onCircle(let circleID, let angleRadians):
      let circle = try resolveCircle(circleID, visiting: &visiting, cache: &cache)
      point = try circle.point(at: angleRadians, coordinateSystem: coordinateSystem)
    case .horizontalProjection(let sourceID, let y):
      guard y.isFinite else {
        throw GeometryError.nonFiniteValue("Horizontal projection")
      }
      let source = try resolvePoint(sourceID, visiting: &visiting, cache: &cache)
      point = Point2D(x: source.x, y: y)
    case .verticalProjection(let sourceID, let x):
      guard x.isFinite else {
        throw GeometryError.nonFiniteValue("Vertical projection")
      }
      let source = try resolvePoint(sourceID, visiting: &visiting, cache: &cache)
      point = Point2D(x: x, y: source.y)
    }
    cache[id] = .point(point)
    return point
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
      radius: definition.radius)
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
      radiusX: definition.radiusX,
      radiusY: definition.radiusY)
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

  mutating func resolveAndCache(_ ids: [GeometryID]) throws {
    var cache = resolvedEntities
    for id in ids {
      cache.removeValue(forKey: id)
    }
    for id in ids {
      try validateEntity(id, cache: &cache)
    }
    resolvedEntities = cache
  }

  mutating func rebuildResolvedEntities() throws {
    try validateIdentity()
    var cache: [GeometryID: ResolvedGeometry] = [:]
    for id in orderedIDs {
      try validateEntity(id, cache: &cache)
    }
    resolvedEntities = cache
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

  func affectedEntityIDs(startingAt rootID: GeometryID) -> [GeometryID] {
    var affected: Set<GeometryID> = [rootID]
    var pending = [rootID]
    while let id = pending.popLast() {
      for dependentID in reverseDependencies[id, default: []]
      where affected.insert(dependentID).inserted {
        pending.append(dependentID)
      }
    }
    return orderedIDs.filter { affected.contains($0) }
  }
}

extension GeometryEntity {
  var dependencyIDs: [GeometryID] {
    switch self {
    case .point(.free):
      []
    case .point(.onCircle(let circleID, _)):
      [circleID]
    case .point(.horizontalProjection(let pointID, _)),
      .point(.verticalProjection(let pointID, _)):
      [pointID]
    case .circle(let definition):
      [definition.center]
    case .ellipse(let definition):
      [definition.center]
    case .segment(let definition):
      [definition.start, definition.end]
    case .line(let definition):
      [definition.first, definition.second]
    case .ray(let definition):
      [definition.origin, definition.through]
    }
  }
}
