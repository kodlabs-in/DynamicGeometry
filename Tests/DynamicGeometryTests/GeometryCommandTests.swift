import Foundation
import Testing

@testable import DynamicGeometry

@Suite("Geometry deletion")
struct GeometryDeletionTests {
  @Test("Deleting a referenced entity reports its dependents and preserves the scene")
  func referencedDeletionIsRejectedAtomically() throws {
    var scene = GeometryScene()
    let center = try scene.addPoint(.free(Point2D(x: 0, y: 0)))
    let circle = try scene.addCircle(center: center, radius: 2)
    let before = scene

    #expect(throws: GeometryDeletionError.referencedEntity(center, dependentIDs: [circle])) {
      try scene.deleteEntities([center], policy: .rejectIfReferenced)
    }
    #expect(scene == before)
  }

  @Test("Cascade deletion removes the transitive branch in stable scene order")
  func cascadeDeletionRemovesDependents() throws {
    var scene = GeometryScene()
    let center = try scene.addPoint(.free(Point2D(x: 0, y: 0)))
    let unrelated = try scene.addPoint(.free(Point2D(x: 8, y: 8)))
    let circle = try scene.addCircle(center: center, radius: 2)
    let point = try scene.addPoint(.onCircle(circle: circle, angleRadians: 0))
    let segment = try scene.addSegment(start: center, end: point)

    let result = try scene.deleteEntities([center], policy: .cascadeDependents)

    #expect(result.deletedEntityIDs == [center, circle, point, segment])
    #expect(scene.orderedIDs == [unrelated])
    try scene.validate()
  }

  @Test("Multi-entity deletion is atomic when any identifier is invalid")
  func multiEntityDeletionIsAtomic() throws {
    var scene = GeometryScene()
    let existing = try scene.addPoint(.free(Point2D(x: 1, y: 2)))
    let missing = GeometryID()
    let before = scene

    #expect(throws: GeometryError.missingEntity(missing)) {
      try scene.deleteEntities([existing, missing], policy: .rejectIfReferenced)
    }
    #expect(scene == before)
  }
}

@Suite("Geometry commands")
struct GeometryCommandTests {
  @Test("A transaction creates explicitly identified entities and reports the change")
  func transactionCreatesEntities() throws {
    var scene = GeometryScene()
    let first = GeometryID()
    let second = GeometryID()
    let segment = GeometryID()
    let transaction = GeometryTransaction(commands: [
      .insert(id: first, entity: .point(.free(Point2D(x: 0, y: 0)))),
      .insert(id: second, entity: .point(.free(Point2D(x: 3, y: 4)))),
      .insert(
        id: segment,
        entity: .segment(SegmentDefinition(start: first, end: second))),
    ])

    let result = try scene.apply(transaction)

    #expect(result.createdEntityIDs == [first, second, segment])
    #expect(result.deletedEntityIDs.isEmpty)
    #expect(result.changedParameterIDs.isEmpty)
    #expect(result.affectedEntityIDs == [first, second, segment])
    #expect(result.diagnostics.isEmpty)
    #expect(try scene.segment(segment).length == 5)
  }

  @Test("A failing command rolls back every earlier command in its transaction")
  func transactionFailureIsAtomic() throws {
    var scene = GeometryScene()
    let before = scene
    let inserted = GeometryID()
    let invalidCircle = GeometryID()
    let missingCenter = GeometryID()
    let transaction = GeometryTransaction(commands: [
      .insert(id: inserted, entity: .point(.free(Point2D(x: 1, y: 2)))),
      .insert(
        id: invalidCircle,
        entity: .circle(CircleDefinition(center: missingCenter, radius: 2))),
    ])

    #expect(throws: GeometryError.missingEntity(missingCenter)) {
      try scene.apply(transaction)
    }
    #expect(scene == before)
  }

  @Test("Commands and transactions round-trip through Codable")
  func transactionIsCodable() throws {
    let transaction = GeometryTransaction(commands: [
      .movePoint(id: GeometryID(), target: Point2D(x: 3, y: 7)),
      .setParameter(id: ScalarParameterID(), value: .pi),
      .delete(ids: [GeometryID(), GeometryID()], policy: .cascadeDependents),
    ])

    let decoded = try JSONDecoder().decode(
      GeometryTransaction.self,
      from: JSONEncoder().encode(transaction))

    #expect(decoded == transaction)
  }

  @Test("Transaction deletion results use stable scene order across commands")
  func transactionDeletionResultIsStable() throws {
    var scene = GeometryScene()
    let first = try scene.addPoint(.free(Point2D(x: 1, y: 1)))
    let second = try scene.addPoint(.free(Point2D(x: 2, y: 2)))
    let third = try scene.addPoint(.free(Point2D(x: 3, y: 3)))

    let result = try scene.apply(
      GeometryTransaction(commands: [
        .delete(ids: [third], policy: .rejectIfReferenced),
        .delete(ids: [first], policy: .rejectIfReferenced),
      ]))

    #expect(result.deletedEntityIDs == [first, third])
    #expect(scene.orderedIDs == [second])
  }

  @Test("A parameter command updates every dependent through the shared command path")
  func parameterCommandPropagates() throws {
    var scene = GeometryScene()
    let theta = try scene.addParameter(name: "theta", value: 0)
    let center = try scene.addPoint(.free(Point2D(x: 0, y: 0)))
    let circle = try scene.addCircle(center: center, radius: 2)
    let first = try scene.addPoint(
      .onCircleExpression(
        circle: circle,
        angleRadians: .parameter(.identified(theta))))
    let second = try scene.addPoint(
      .onCircleExpression(
        circle: circle,
        angleRadians: .parameter(.identified(theta))))

    let result = try scene.apply(
      GeometryTransaction(commands: [
        .setParameter(id: theta, value: .pi / 2)
      ]))

    #expect(result.changedParameterIDs == [theta])
    #expect(result.affectedEntityIDs == [first, second])
    #expect(abs(try scene.point(first).x) < 0.000_000_1)
    #expect(try scene.point(first).y == 2)
    #expect(try scene.point(second) == scene.point(first))
  }
}

@Suite("Geometry history")
struct GeometryHistoryTests {
  @Test("One transaction is one undo and redo step")
  func transactionCreatesOneHistoryStep() throws {
    var scene = GeometryScene()
    let point = try scene.addPoint(.free(Point2D(x: 1, y: 2)))
    var history = GeometryHistory(scene: scene)
    let transaction = GeometryTransaction(commands: [
      .movePoint(id: point, target: Point2D(x: 4, y: 5)),
      .movePoint(id: point, target: Point2D(x: 8, y: 9)),
    ])

    _ = try history.apply(transaction)
    #expect(try history.scene.point(point) == Point2D(x: 8, y: 9))

    let didUndo = history.undo()
    #expect(didUndo)
    #expect(try history.scene.point(point) == Point2D(x: 1, y: 2))
    #expect(!history.canUndo)

    let didRedo = history.redo()
    #expect(didRedo)
    #expect(try history.scene.point(point) == Point2D(x: 8, y: 9))
  }

  @Test("A failed transaction creates no undo entry")
  func failedTransactionDoesNotChangeHistory() throws {
    let missing = GeometryID()
    var history = GeometryHistory()

    #expect(throws: GeometryError.missingEntity(missing)) {
      try history.apply(
        GeometryTransaction(commands: [
          .movePoint(id: missing, target: Point2D(x: 1, y: 2))
        ]))
    }
    #expect(!history.canUndo)
    #expect(!history.canRedo)
    #expect(history.scene == GeometryScene())
  }

  @Test("Repeated drag transactions with one coalescing identifier undo together")
  func coalescedDragIsOneUndoStep() throws {
    var scene = GeometryScene()
    let point = try scene.addPoint(.free(Point2D(x: 0, y: 0)))
    var history = GeometryHistory(scene: scene)

    _ = try history.apply(
      GeometryTransaction(commands: [
        .movePoint(id: point, target: Point2D(x: 2, y: 3))
      ]),
      coalescingID: "drag:\(point)")
    _ = try history.apply(
      GeometryTransaction(commands: [
        .movePoint(id: point, target: Point2D(x: 8, y: 9))
      ]),
      coalescingID: "drag:\(point)")
    _ = try history.apply(
      GeometryTransaction(commands: [
        .movePoint(id: point, target: Point2D(x: 10, y: 11))
      ]),
      coalescingID: "second-drag:\(point)")
    _ = try history.apply(
      GeometryTransaction(commands: [
        .movePoint(id: point, target: Point2D(x: 12, y: 13))
      ]))

    #expect(try history.scene.point(point) == Point2D(x: 12, y: 13))
    let undidStandaloneTransaction = history.undo()
    #expect(undidStandaloneTransaction)
    #expect(try history.scene.point(point) == Point2D(x: 10, y: 11))
    let undidDifferentGroup = history.undo()
    #expect(undidDifferentGroup)
    #expect(try history.scene.point(point) == Point2D(x: 8, y: 9))
    let undidCoalescedGroup = history.undo()
    #expect(undidCoalescedGroup)
    #expect(try history.scene.point(point) == Point2D(x: 0, y: 0))
    #expect(!history.canUndo)
  }
}

@Suite("Geometry capabilities")
struct GeometryCapabilityTests {
  @Test("Capability discovery describes every supported entity and command")
  func discoversSupportedCapabilities() throws {
    let capabilities = GeometryCapabilities.current

    #expect(capabilities.supported == GeometryCapability.allCases)
    #expect(capabilities.supports(.entityCircle))
    #expect(capabilities.supports(.commandDelete))
    #expect(capabilities.supports(.commandSetParameter))
    #expect(capabilities.supports(.atomicTransactions))
    #expect(capabilities.supports(.undoRedoHistory))

    let decoded = try JSONDecoder().decode(
      GeometryCapabilities.self,
      from: JSONEncoder().encode(capabilities))
    #expect(decoded == capabilities)
  }
}
