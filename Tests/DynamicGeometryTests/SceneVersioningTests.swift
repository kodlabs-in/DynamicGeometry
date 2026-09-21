import Foundation
import Testing

@testable import DynamicGeometry

@Suite("Scene schema versioning")
struct SceneVersioningTests {
  @Test("Encoded scenes declare the current schema version")
  func encodedScenesDeclareVersion() throws {
    let data = try JSONEncoder().encode(GeometryScene())
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(object["schemaVersion"] as? Int == GeometryScene.currentSchemaVersion)
  }

  @Test("Unversioned foundation scenes migrate to the current schema")
  func decodesLegacyUnversionedScene() throws {
    var scene = GeometryScene(coordinateSystem: .screenYDown)
    _ = try scene.addPoint(.free(Point2D(x: 4, y: 8)))
    let encoded = try JSONEncoder().encode(scene)
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    object.removeValue(forKey: "schemaVersion")
    let legacyData = try JSONSerialization.data(withJSONObject: object)

    let decoded = try JSONDecoder().decode(GeometryScene.self, from: legacyData)

    #expect(decoded == scene)
  }

  @Test("Future scene schemas fail with an explicit compatibility error")
  func rejectsFutureSchemaVersion() throws {
    let encoded = try JSONEncoder().encode(GeometryScene())
    var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let futureVersion = GeometryScene.currentSchemaVersion + 1
    object["schemaVersion"] = futureVersion
    let futureData = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: GeometryError.unsupportedSchemaVersion(futureVersion)) {
      try JSONDecoder().decode(GeometryScene.self, from: futureData)
    }
  }
}
