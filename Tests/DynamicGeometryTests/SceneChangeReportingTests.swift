import Foundation
import Testing

@testable import DynamicGeometry

@Suite("Scene change reporting")
struct SceneChangeReportingTests {
  @Test("Moving one dependency root reports only its branch in scene order")
  func movingIndependentCircleBranchReportsAffectedEntities() throws {
    var scene = GeometryScene()
    let firstCenter = try scene.addPoint(.free(Point2D(x: 0, y: 0)))
    let secondCenter = try scene.addPoint(.free(Point2D(x: 100, y: 100)))
    let firstCircle = try scene.addCircle(center: firstCenter, radius: 10)
    let secondCircle = try scene.addCircle(center: secondCenter, radius: 20)
    let firstPoint = try scene.addPoint(.onCircle(circle: firstCircle, angleRadians: 0))
    let secondPoint = try scene.addPoint(.onCircle(circle: secondCircle, angleRadians: .pi))
    let firstRadius = try scene.addSegment(start: firstCenter, end: firstPoint)
    let secondRadius = try scene.addSegment(start: secondCenter, end: secondPoint)

    let change = try scene.movePointReportingChanges(
      firstCenter,
      to: Point2D(x: 5, y: 7)
    )

    #expect(change.affectedEntityIDs == [firstCenter, firstCircle, firstPoint, firstRadius])
    #expect(try scene.circle(firstCircle) == Circle2D(center: Point2D(x: 5, y: 7), radius: 10))
    #expect(try scene.point(firstPoint) == Point2D(x: 15, y: 7))
    #expect(
      try scene.circle(secondCircle)
        == Circle2D(center: Point2D(x: 100, y: 100), radius: 20)
    )
    #expect(try scene.point(secondPoint) == Point2D(x: 80, y: 100))
    #expect(try scene.segment(secondRadius).length == 20)
  }

  @Test("A failed reporting replacement restores geometry and later change reporting")
  func failedReplacementRollsBackSceneAndDependencyIndex() throws {
    var scene = GeometryScene()
    let source = try scene.addPoint(.free(Point2D(x: 2, y: 3)))
    let projection = try scene.addPoint(.horizontalProjection(of: source, ontoY: 0))

    #expect(throws: GeometryError.cyclicDependency(source)) {
      try scene.replaceReportingChanges(
        source,
        with: .point(.verticalProjection(of: projection, ontoX: 0))
      )
    }

    #expect(try scene.point(source) == Point2D(x: 2, y: 3))
    #expect(try scene.point(projection) == Point2D(x: 2, y: 0))

    let change = try scene.movePointReportingChanges(source, to: Point2D(x: 8, y: 9))

    #expect(change.affectedEntityIDs == [source, projection])
    #expect(try scene.point(projection) == Point2D(x: 8, y: 0))
  }

  @Test("Decoding rejects semantic entities omitted from scene order")
  func decodingRejectsUnorderedEntity() throws {
    var scene = GeometryScene()
    _ = try scene.addPoint(.free(Point2D(x: 1, y: 2)))
    let data = try JSONEncoder().encode(scene)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var entities = try #require(object["entities"] as? [Any])
    let encodedEntity = try #require(entities.last)
    let encodedID = try JSONSerialization.jsonObject(with: JSONEncoder().encode(GeometryID()))
    entities.append(encodedID)
    entities.append(encodedEntity)
    object["entities"] = entities
    let malformedData = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: GeometryError.inconsistentScene) {
      try JSONDecoder().decode(GeometryScene.self, from: malformedData)
    }
  }
}
