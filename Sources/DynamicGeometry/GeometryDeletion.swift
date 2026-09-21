import Foundation

/// The relationship policy used when deleting entities from a scene.
public enum GeometryDeletionPolicy: String, Codable, Equatable, Sendable {
  /// Reject deletion when an entity outside the requested set depends on it.
  case rejectIfReferenced

  /// Delete the requested entities and every transitive dependent.
  case cascadeDependents
}

/// A deletion failure that identifies the entity which is still in use.
public enum GeometryDeletionError: Error, Equatable, LocalizedError, Sendable {
  /// The entity cannot be deleted without also deleting the listed dependents.
  case referencedEntity(GeometryID, dependentIDs: [GeometryID])

  /// A human-readable description of the relationship preventing deletion.
  public var errorDescription: String? {
    switch self {
    case .referencedEntity(let id, let dependentIDs):
      "Entity \(id) is used by \(dependentIDs.count) other geometry entities."
    }
  }
}

/// The observable result of deleting one or more entities.
public struct GeometryDeletionResult: Equatable, Sendable {
  /// Deleted identifiers in their former stable scene order.
  public let deletedEntityIDs: [GeometryID]
}

extension GeometryScene {
  /// Atomically deletes entities according to the requested dependency policy.
  @discardableResult
  public mutating func deleteEntities(
    _ ids: [GeometryID],
    policy: GeometryDeletionPolicy = .rejectIfReferenced
  ) throws -> GeometryDeletionResult {
    var updated = self
    let result = try updated.performDeletion(ids, policy: policy)
    self = updated
    return result
  }
}

private extension GeometryScene {
  mutating func performDeletion(
    _ ids: [GeometryID],
    policy: GeometryDeletionPolicy
  ) throws -> GeometryDeletionResult {
    let requested = Set(ids)
    for id in ids where entities[id] == nil {
      throw GeometryError.missingEntity(id)
    }

    let deletionSet: Set<GeometryID>
    switch policy {
    case .rejectIfReferenced:
      for id in orderedIDs where requested.contains(id) {
        let externalDependents = orderedIDs.filter {
          !requested.contains($0) && reverseDependencies[id, default: []].contains($0)
        }
        guard externalDependents.isEmpty else {
          throw GeometryDeletionError.referencedEntity(id, dependentIDs: externalDependents)
        }
      }
      deletionSet = requested
    case .cascadeDependents:
      deletionSet = dependentClosure(of: requested)
    }

    let deletedEntityIDs = orderedIDs.filter { deletionSet.contains($0) }
    var remaining = deletionSet
    while !remaining.isEmpty {
      guard
        let removableID = orderedIDs.reversed().first(where: { id in
          remaining.contains(id) && reverseDependencies[id, default: []].isEmpty
        })
      else {
        throw GeometryError.inconsistentScene
      }
      try remove(removableID)
      remaining.remove(removableID)
    }
    return GeometryDeletionResult(deletedEntityIDs: deletedEntityIDs)
  }

  func dependentClosure(of roots: Set<GeometryID>) -> Set<GeometryID> {
    var result = roots
    var pending = Array(roots)
    while let id = pending.popLast() {
      for dependentID in reverseDependencies[id, default: []]
      where result.insert(dependentID).inserted {
        pending.append(dependentID)
      }
    }
    return result
  }
}
