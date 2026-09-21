import Foundation

/// A Codable collection of geometric entities whose relationships resolve on demand.
public struct GeometryScene: Codable, Equatable, Sendable {
  /// The schema version written by this release.
  public static let currentSchemaVersion = 2

  /// The coordinate orientation shared by angular entities in this scene.
  public let coordinateSystem: CoordinateSystem2D

  /// Entity identifiers in stable display and serialization order.
  public private(set) var orderedIDs: [GeometryID]

  /// Scalar parameter identifiers in stable serialization order.
  public internal(set) var orderedParameterIDs: [ScalarParameterID]

  var entities: [GeometryID: GeometryEntity]
  var parameters: [ScalarParameterID: ScalarParameter]
  var reverseDependencies: [GeometryID: Set<GeometryID>]
  var parameterDependents: [ScalarParameterID: Set<GeometryID>]
  var resolvedEntities: [GeometryID: ResolvedGeometry]
  var evaluationFailures: [GeometryID: GeometryResolutionFailure]

  /// Creates an empty scene using Cartesian coordinates by default.
  public init(coordinateSystem: CoordinateSystem2D = .cartesian) {
    self.coordinateSystem = coordinateSystem
    orderedIDs = []
    orderedParameterIDs = []
    entities = [:]
    parameters = [:]
    reverseDependencies = [:]
    parameterDependents = [:]
    resolvedEntities = [:]
    evaluationFailures = [:]
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

  /// Adds a circle with an expression-backed radius.
  @discardableResult
  public mutating func addCircle(
    center: GeometryID,
    radius: ScalarExpression,
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

  /// Adds an ellipse with expression-backed radii.
  @discardableResult
  public mutating func addEllipse(
    center: GeometryID,
    radiusX: ScalarExpression,
    radiusY: ScalarExpression,
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
    _ = try replaceReportingChanges(id, with: entity)
  }

  /// Replaces one entity and reports the mutation root and all transitive dependents.
  @discardableResult
  public mutating func replaceReportingChanges(
    _ id: GeometryID,
    with entity: GeometryEntity
  ) throws -> GeometrySceneChange {
    guard let previous = entities[id] else {
      throw GeometryError.missingEntity(id)
    }
    try validateLiteralInputs(entity)
    entities[id] = entity
    updateReverseDependencies(for: id, from: previous.dependencyIDs, to: entity.dependencyIDs)
    updateParameterDependents(
      for: id,
      from: previous.referencedParameterIDs,
      to: entity.referencedParameterIDs)
    let affectedEntityIDs = affectedEntityIDs(startingAt: id)
    do {
      try resolveAndCacheRecoverably(affectedEntityIDs)
    } catch {
      entities[id] = previous
      updateReverseDependencies(for: id, from: entity.dependencyIDs, to: previous.dependencyIDs)
      updateParameterDependents(
        for: id,
        from: entity.referencedParameterIDs,
        to: previous.referencedParameterIDs)
      throw error
    }
    return GeometrySceneChange(affectedEntityIDs: affectedEntityIDs)
  }

  /// Removes an entity when no remaining entity depends on it.
  public mutating func remove(_ id: GeometryID) throws {
    guard let previous = entities[id] else {
      throw GeometryError.missingEntity(id)
    }
    guard reverseDependencies[id, default: []].isEmpty else {
      throw GeometryError.missingEntity(id)
    }
    guard let previousIndex = orderedIDs.firstIndex(of: id) else {
      throw GeometryError.inconsistentScene
    }
    entities.removeValue(forKey: id)
    orderedIDs.remove(at: previousIndex)
    resolvedEntities.removeValue(forKey: id)
    evaluationFailures.removeValue(forKey: id)
    updateReverseDependencies(for: id, from: previous.dependencyIDs, to: [])
    updateParameterDependents(for: id, from: previous.referencedParameterIDs, to: [])
  }

  /// Resolves a point and all of its dependencies.
  public func point(_ id: GeometryID) throws -> Point2D {
    if case .point(let point) = resolvedEntities[id] { return point }
    var cache = resolvedEntities
    var visiting: Set<GeometryID> = []
    return try resolvePoint(id, visiting: &visiting, cache: &cache)
  }

  /// Resolves a circle and its centre point.
  public func circle(_ id: GeometryID) throws -> Circle2D {
    if case .circle(let circle) = resolvedEntities[id] { return circle }
    var cache = resolvedEntities
    var visiting: Set<GeometryID> = []
    return try resolveCircle(id, visiting: &visiting, cache: &cache)
  }

  /// Resolves an ellipse and its centre point.
  public func ellipse(_ id: GeometryID) throws -> Ellipse2D {
    if case .ellipse(let ellipse) = resolvedEntities[id] { return ellipse }
    var cache = resolvedEntities
    var visiting: Set<GeometryID> = []
    return try resolveEllipse(id, visiting: &visiting, cache: &cache)
  }

  /// Resolves a segment and both endpoints.
  public func segment(_ id: GeometryID) throws -> Segment2D {
    if case .segment(let segment) = resolvedEntities[id] { return segment }
    var cache = resolvedEntities
    var visiting: Set<GeometryID> = []
    return try resolveSegment(id, visiting: &visiting, cache: &cache)
  }

  /// Resolves an infinite line and its two defining points.
  public func line(_ id: GeometryID) throws -> Line2D {
    if case .line(let line) = resolvedEntities[id] { return line }
    var cache = resolvedEntities
    var visiting: Set<GeometryID> = []
    return try resolveLine(id, visiting: &visiting, cache: &cache)
  }

  /// Resolves a ray and its two defining points.
  public func ray(_ id: GeometryID) throws -> Ray2D {
    if case .ray(let ray) = resolvedEntities[id] { return ray }
    var cache = resolvedEntities
    var visiting: Set<GeometryID> = []
    return try resolveRay(id, visiting: &visiting, cache: &cache)
  }

}

private extension GeometryScene {
  @discardableResult
  mutating func insert(_ entity: GeometryEntity, id: GeometryID) throws -> GeometryID {
    guard entities[id] == nil else {
      throw GeometryError.duplicateEntity(id)
    }
    try validateLiteralInputs(entity)
    entities[id] = entity
    orderedIDs.append(id)
    updateReverseDependencies(for: id, from: [], to: entity.dependencyIDs)
    updateParameterDependents(for: id, from: [], to: entity.referencedParameterIDs)
    do {
      try resolveAndCacheRecoverably([id])
      return id
    } catch {
      updateReverseDependencies(for: id, from: entity.dependencyIDs, to: [])
      updateParameterDependents(for: id, from: entity.referencedParameterIDs, to: [])
      entities.removeValue(forKey: id)
      orderedIDs.removeAll { $0 == id }
      throw error
    }
  }
}

extension GeometryScene {
  private enum CodingKeys: CodingKey {
    case schemaVersion
    case coordinateSystem
    case orderedParameterIDs
    case parameters
    case orderedIDs
    case entities
  }

  /// Decodes and validates a complete geometry scene.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
    guard (0...Self.currentSchemaVersion).contains(schemaVersion) else {
      throw GeometryError.unsupportedSchemaVersion(schemaVersion)
    }
    coordinateSystem = try container.decode(CoordinateSystem2D.self, forKey: .coordinateSystem)
    orderedParameterIDs =
      try container.decodeIfPresent([ScalarParameterID].self, forKey: .orderedParameterIDs) ?? []
    parameters =
      try container.decodeIfPresent(
        [ScalarParameterID: ScalarParameter].self,
        forKey: .parameters) ?? [:]
    orderedIDs = try container.decode([GeometryID].self, forKey: .orderedIDs)
    entities = try container.decode([GeometryID: GeometryEntity].self, forKey: .entities)
    reverseDependencies = Self.makeReverseDependencies(from: entities)
    parameterDependents = Self.makeParameterDependents(from: entities)
    resolvedEntities = [:]
    evaluationFailures = [:]
    try rebuildResolvedEntities()
  }

  /// Encodes the scene after validating every dependency and numeric value.
  public func encode(to encoder: Encoder) throws {
    try validate()
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
    try container.encode(coordinateSystem, forKey: .coordinateSystem)
    try container.encode(orderedParameterIDs, forKey: .orderedParameterIDs)
    try container.encode(parameters, forKey: .parameters)
    try container.encode(orderedIDs, forKey: .orderedIDs)
    try container.encode(entities, forKey: .entities)
  }

  /// Compares only semantic scene state; derived dependency indexes are excluded.
  public static func == (lhs: GeometryScene, rhs: GeometryScene) -> Bool {
    lhs.coordinateSystem == rhs.coordinateSystem
      && lhs.orderedParameterIDs == rhs.orderedParameterIDs
      && lhs.parameters == rhs.parameters
      && lhs.orderedIDs == rhs.orderedIDs
      && lhs.entities == rhs.entities
  }
}
