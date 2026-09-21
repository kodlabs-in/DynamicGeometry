import Foundation

/// A Codable collection of geometric entities whose relationships resolve on demand.
public struct GeometryScene: Codable, Equatable, Sendable {
  /// The coordinate orientation shared by angular entities in this scene.
  public let coordinateSystem: CoordinateSystem2D

  /// Entity identifiers in stable display and serialization order.
  public private(set) var orderedIDs: [GeometryID]

  private var entities: [GeometryID: GeometryEntity]

  /// Creates an empty scene using Cartesian coordinates by default.
  public init(coordinateSystem: CoordinateSystem2D = .cartesian) {
    self.coordinateSystem = coordinateSystem
    orderedIDs = []
    entities = [:]
  }

  /// Returns the stored definition for an entity without resolving its dependencies.
  public func entity(_ id: GeometryID) -> GeometryEntity? {
    entities[id]
  }

  /// Adds a free, constrained, or derived point.
  @discardableResult
  public mutating func addPoint(
    _ definition: PointDefinition,
    id: GeometryID = GeometryID()
  ) throws -> GeometryID {
    try insert(.point(definition), id: id)
  }

  /// Adds a circle whose centre is an existing point.
  @discardableResult
  public mutating func addCircle(
    center: GeometryID,
    radius: Double,
    id: GeometryID = GeometryID()
  ) throws -> GeometryID {
    try insert(.circle(CircleDefinition(center: center, radius: radius)), id: id)
  }

  /// Adds an ellipse whose centre is an existing point.
  @discardableResult
  public mutating func addEllipse(
    center: GeometryID,
    radiusX: Double,
    radiusY: Double,
    id: GeometryID = GeometryID()
  ) throws -> GeometryID {
    try insert(
      .ellipse(EllipseDefinition(center: center, radiusX: radiusX, radiusY: radiusY)),
      id: id)
  }

  /// Adds a finite segment between two existing points.
  @discardableResult
  public mutating func addSegment(
    start: GeometryID,
    end: GeometryID,
    id: GeometryID = GeometryID()
  ) throws -> GeometryID {
    try insert(.segment(SegmentDefinition(start: start, end: end)), id: id)
  }

  /// Adds an infinite line passing through two existing, distinct points.
  @discardableResult
  public mutating func addLine(
    first: GeometryID,
    second: GeometryID,
    id: GeometryID = GeometryID()
  ) throws -> GeometryID {
    try insert(.line(LineDefinition(first: first, second: second)), id: id)
  }

  /// Adds a ray from an origin through another existing, distinct point.
  @discardableResult
  public mutating func addRay(
    origin: GeometryID,
    through: GeometryID,
    id: GeometryID = GeometryID()
  ) throws -> GeometryID {
    try insert(.ray(RayDefinition(origin: origin, through: through)), id: id)
  }

  /// Replaces one entity while preserving its identifier and scene order.
  public mutating func replace(_ id: GeometryID, with entity: GeometryEntity) throws {
    guard let previous = entities[id] else {
      throw GeometryError.missingEntity(id)
    }
    entities[id] = entity
    do {
      try validate()
    } catch {
      entities[id] = previous
      throw error
    }
  }

  /// Removes an entity when no remaining entity depends on it.
  public mutating func remove(_ id: GeometryID) throws {
    guard let previous = entities.removeValue(forKey: id) else {
      throw GeometryError.missingEntity(id)
    }
    guard let previousIndex = orderedIDs.firstIndex(of: id) else {
      entities[id] = previous
      throw GeometryError.inconsistentScene
    }
    orderedIDs.remove(at: previousIndex)
    do {
      try validate()
    } catch {
      orderedIDs.insert(id, at: previousIndex)
      entities[id] = previous
      throw error
    }
  }

  /// Resolves a point and all of its dependencies.
  public func point(_ id: GeometryID) throws -> Point2D {
    var visiting: Set<GeometryID> = []
    return try resolvePoint(id, visiting: &visiting)
  }

  /// Resolves a circle and its centre point.
  public func circle(_ id: GeometryID) throws -> Circle2D {
    var visiting: Set<GeometryID> = []
    return try resolveCircle(id, visiting: &visiting)
  }

  /// Resolves an ellipse and its centre point.
  public func ellipse(_ id: GeometryID) throws -> Ellipse2D {
    var visiting: Set<GeometryID> = []
    return try resolveEllipse(id, visiting: &visiting)
  }

  /// Resolves a segment and both endpoints.
  public func segment(_ id: GeometryID) throws -> Segment2D {
    var visiting: Set<GeometryID> = []
    return try resolveSegment(id, visiting: &visiting)
  }

  /// Resolves an infinite line and its two defining points.
  public func line(_ id: GeometryID) throws -> Line2D {
    var visiting: Set<GeometryID> = []
    return try resolveLine(id, visiting: &visiting)
  }

  /// Resolves a ray and its two defining points.
  public func ray(_ id: GeometryID) throws -> Ray2D {
    var visiting: Set<GeometryID> = []
    return try resolveRay(id, visiting: &visiting)
  }

  /// Moves a free point directly or projects a circle-constrained point onto its circle.
  public mutating func movePoint(_ id: GeometryID, to target: Point2D) throws {
    guard target.isFinite else {
      throw GeometryError.nonFiniteValue("Drag location")
    }
    guard case .point(let definition) = entities[id] else {
      throw try typeError(for: id, expected: "point")
    }

    let replacement: PointDefinition
    switch definition {
    case .free:
      replacement = .free(target)
    case .onCircle(let circleID, _):
      let angle = try circle(circleID).angle(toward: target, coordinateSystem: coordinateSystem)
      replacement = .onCircle(circle: circleID, angleRadians: angle)
    case .horizontalProjection, .verticalProjection:
      throw GeometryError.readOnlyPoint(id)
    }
    try replace(id, with: .point(replacement))
  }

  /// Validates scene identity, every dependency, and every resolved numeric value.
  public func validate() throws {
    guard orderedIDs.count == Set(orderedIDs).count else {
      throw GeometryError.inconsistentScene
    }
    guard Set(orderedIDs) == Set(entities.keys) else {
      throw GeometryError.inconsistentScene
    }
    for id in orderedIDs {
      try validateEntity(id)
    }
  }
}

private extension GeometryScene {
  @discardableResult
  private mutating func insert(_ entity: GeometryEntity, id: GeometryID) throws -> GeometryID {
    guard entities[id] == nil else {
      throw GeometryError.duplicateEntity(id)
    }
    entities[id] = entity
    orderedIDs.append(id)
    do {
      try validate()
      return id
    } catch {
      entities.removeValue(forKey: id)
      orderedIDs.removeAll { $0 == id }
      throw error
    }
  }

  private func validateEntity(_ id: GeometryID) throws {
    guard let entity = entities[id] else {
      throw GeometryError.missingEntity(id)
    }
    switch entity {
    case .point:
      _ = try point(id)
    case .circle:
      _ = try circle(id)
    case .ellipse:
      _ = try ellipse(id)
    case .segment:
      _ = try segment(id)
    case .line:
      _ = try line(id)
    case .ray:
      _ = try ray(id)
    }
  }

  private func resolvePoint(
    _ id: GeometryID,
    visiting: inout Set<GeometryID>
  ) throws -> Point2D {
    try beginResolving(id, visiting: &visiting)
    defer { visiting.remove(id) }
    guard case .point(let definition) = entities[id] else {
      throw try typeError(for: id, expected: "point")
    }
    switch definition {
    case .free(let point):
      guard point.isFinite else {
        throw GeometryError.nonFiniteValue("Point")
      }
      return point
    case .onCircle(let circleID, let angleRadians):
      let circle = try resolveCircle(circleID, visiting: &visiting)
      return try circle.point(at: angleRadians, coordinateSystem: coordinateSystem)
    case .horizontalProjection(let sourceID, let y):
      guard y.isFinite else {
        throw GeometryError.nonFiniteValue("Horizontal projection")
      }
      let source = try resolvePoint(sourceID, visiting: &visiting)
      return Point2D(x: source.x, y: y)
    case .verticalProjection(let sourceID, let x):
      guard x.isFinite else {
        throw GeometryError.nonFiniteValue("Vertical projection")
      }
      let source = try resolvePoint(sourceID, visiting: &visiting)
      return Point2D(x: x, y: source.y)
    }
  }

  private func resolveCircle(
    _ id: GeometryID,
    visiting: inout Set<GeometryID>
  ) throws -> Circle2D {
    try beginResolving(id, visiting: &visiting)
    defer { visiting.remove(id) }
    guard case .circle(let definition) = entities[id] else {
      throw try typeError(for: id, expected: "circle")
    }
    return try Circle2D(
      center: resolvePoint(definition.center, visiting: &visiting),
      radius: definition.radius)
  }

  private func resolveEllipse(
    _ id: GeometryID,
    visiting: inout Set<GeometryID>
  ) throws -> Ellipse2D {
    try beginResolving(id, visiting: &visiting)
    defer { visiting.remove(id) }
    guard case .ellipse(let definition) = entities[id] else {
      throw try typeError(for: id, expected: "ellipse")
    }
    return try Ellipse2D(
      center: resolvePoint(definition.center, visiting: &visiting),
      radiusX: definition.radiusX,
      radiusY: definition.radiusY)
  }

  private func resolveSegment(
    _ id: GeometryID,
    visiting: inout Set<GeometryID>
  ) throws -> Segment2D {
    try beginResolving(id, visiting: &visiting)
    defer { visiting.remove(id) }
    guard case .segment(let definition) = entities[id] else {
      throw try typeError(for: id, expected: "segment")
    }
    return try Segment2D(
      start: resolvePoint(definition.start, visiting: &visiting),
      end: resolvePoint(definition.end, visiting: &visiting))
  }

  private func resolveLine(
    _ id: GeometryID,
    visiting: inout Set<GeometryID>
  ) throws -> Line2D {
    try beginResolving(id, visiting: &visiting)
    defer { visiting.remove(id) }
    guard case .line(let definition) = entities[id] else {
      throw try typeError(for: id, expected: "line")
    }
    return try Line2D(
      first: resolvePoint(definition.first, visiting: &visiting),
      second: resolvePoint(definition.second, visiting: &visiting))
  }

  private func resolveRay(
    _ id: GeometryID,
    visiting: inout Set<GeometryID>
  ) throws -> Ray2D {
    try beginResolving(id, visiting: &visiting)
    defer { visiting.remove(id) }
    guard case .ray(let definition) = entities[id] else {
      throw try typeError(for: id, expected: "ray")
    }
    return try Ray2D(
      origin: resolvePoint(definition.origin, visiting: &visiting),
      through: resolvePoint(definition.through, visiting: &visiting))
  }

  private func beginResolving(
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

  private func typeError(for id: GeometryID, expected: String) throws -> GeometryError {
    guard entities[id] != nil else {
      throw GeometryError.missingEntity(id)
    }
    return GeometryError.unexpectedEntity(id, expected: expected)
  }
}

extension GeometryScene {
  private enum CodingKeys: CodingKey {
    case coordinateSystem
    case orderedIDs
    case entities
  }

  /// Decodes and validates a complete geometry scene.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    coordinateSystem = try container.decode(CoordinateSystem2D.self, forKey: .coordinateSystem)
    orderedIDs = try container.decode([GeometryID].self, forKey: .orderedIDs)
    entities = try container.decode([GeometryID: GeometryEntity].self, forKey: .entities)
    try validate()
  }

  /// Encodes the scene after validating every dependency and numeric value.
  public func encode(to encoder: Encoder) throws {
    try validate()
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(coordinateSystem, forKey: .coordinateSystem)
    try container.encode(orderedIDs, forKey: .orderedIDs)
    try container.encode(entities, forKey: .entities)
  }
}
