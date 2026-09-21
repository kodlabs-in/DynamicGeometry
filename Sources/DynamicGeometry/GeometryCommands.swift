/// A serializable, app-independent edit to a geometry scene.
public enum GeometryCommand: Codable, Equatable, Sendable {
  /// Inserts a definition with caller-supplied stable identity.
  case insert(id: GeometryID, entity: GeometryEntity)

  /// Replaces a definition while preserving its identity and scene order.
  case replace(id: GeometryID, entity: GeometryEntity)

  /// Moves a free or constrained point in mathematical coordinates.
  case movePoint(id: GeometryID, target: Point2D)

  /// Changes a scene-owned scalar input and updates every dependent entity.
  case setParameter(id: ScalarParameterID, value: Double)

  /// Deletes one or more entities using an explicit relationship policy.
  case delete(ids: [GeometryID], policy: GeometryDeletionPolicy)
}

/// An ordered collection of commands that succeeds or fails as one edit.
public struct GeometryTransaction: Codable, Equatable, Sendable {
  /// Commands applied in order.
  public let commands: [GeometryCommand]

  /// Creates an atomic transaction.
  public init(commands: [GeometryCommand]) {
    self.commands = commands
  }
}

/// The observable result of an atomic geometry transaction.
public struct GeometryTransactionResult: Equatable, Sendable {
  /// Inserted identifiers in stable scene order.
  public let createdEntityIDs: [GeometryID]

  /// Deleted identifiers in their former stable scene order.
  public let deletedEntityIDs: [GeometryID]

  /// Changed scalar input identifiers in stable parameter order.
  public let changedParameterIDs: [ScalarParameterID]

  /// Created or changed surviving identifiers in stable scene order.
  public let affectedEntityIDs: [GeometryID]

  /// Non-fatal information produced while applying the transaction.
  public let diagnostics: [String]
}

extension GeometryScene {
  /// Applies every command to a copy and commits only when the complete transaction is valid.
  @discardableResult
  public mutating func apply(
    _ transaction: GeometryTransaction
  ) throws -> GeometryTransactionResult {
    var updated = self
    var transactionOrder = orderedIDs
    var created: Set<GeometryID> = []
    var deleted: Set<GeometryID> = []
    var changedParameters: Set<ScalarParameterID> = []
    var affected: Set<GeometryID> = []

    for command in transaction.commands {
      switch command {
      case .insert(let id, let entity):
        try updated.insertCommandEntity(entity, id: id)
        if !transactionOrder.contains(id) {
          transactionOrder.append(id)
        }
        created.insert(id)
        affected.insert(id)
      case .replace(let id, let entity):
        let change = try updated.replaceReportingChanges(id, with: entity)
        changedParameters.formUnion(change.changedParameterIDs)
        affected.formUnion(change.affectedEntityIDs)
      case .movePoint(let id, let target):
        let change = try updated.movePointReportingChanges(id, to: target)
        changedParameters.formUnion(change.changedParameterIDs)
        affected.formUnion(change.affectedEntityIDs)
      case .setParameter(let id, let value):
        let change = try updated.setParameter(id, to: value)
        changedParameters.formUnion(change.changedParameterIDs)
        affected.formUnion(change.affectedEntityIDs)
      case .delete(let ids, let policy):
        let result = try updated.deleteEntities(ids, policy: policy)
        deleted.formUnion(result.deletedEntityIDs)
        affected.subtract(result.deletedEntityIDs)
      }
    }

    self = updated
    return GeometryTransactionResult(
      createdEntityIDs: updated.orderedIDs.filter { created.contains($0) },
      deletedEntityIDs: transactionOrder.filter { deleted.contains($0) },
      changedParameterIDs: updated.orderedParameterIDs.filter { changedParameters.contains($0) },
      affectedEntityIDs: updated.orderedIDs.filter { affected.contains($0) },
      diagnostics: [])
  }
}

private extension GeometryScene {
  mutating func insertCommandEntity(_ entity: GeometryEntity, id: GeometryID) throws {
    switch entity {
    case .point(let definition):
      try addPoint(definition, id: id)
    case .circle(let definition):
      try addCircle(center: definition.center, radius: definition.radius, id: id)
    case .ellipse(let definition):
      try addEllipse(
        center: definition.center,
        radiusX: definition.radiusX,
        radiusY: definition.radiusY,
        id: id)
    case .segment(let definition):
      try addSegment(start: definition.start, end: definition.end, id: id)
    case .line(let definition):
      try addLine(first: definition.first, second: definition.second, id: id)
    case .ray(let definition):
      try addRay(origin: definition.origin, through: definition.through, id: id)
    }
  }
}
