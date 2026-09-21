import Foundation
import Testing

@testable import DynamicGeometry

@Suite("Reference constructions")
struct ReferenceConstructionTests {
  @Test("A reusable unit circle survives reopening and remains interactive")
  func unitCircleRoundTripsAndContinuesEditing() throws {
    var scene = GeometryScene()
    let construction = try UnitCircleConstruction.insert(
      into: &scene,
      radius: 2,
      angleRadians: .pi / 4)

    let initial = try construction.snapshot(in: scene)
    #expect(isClose(initial.cosine, sqrt(0.5)))
    #expect(isClose(initial.sine, sqrt(0.5)))
    #expect(initial.radius == 2)

    let document = UnitCircleTestDocument(scene: scene, construction: construction)
    let reopened = try JSONDecoder().decode(
      UnitCircleTestDocument.self,
      from: JSONEncoder().encode(document))
    var reopenedScene = reopened.scene

    let change = try reopened.construction.movePoint(
      in: &reopenedScene,
      to: Point2D(x: -20, y: 0))
    let moved = try reopened.construction.snapshot(in: reopenedScene)

    #expect(change.changedParameterIDs == [construction.angleParameterID])
    #expect(isClose(moved.angleRadians, .pi))
    #expect(isClose(moved.cosine, -1))
    #expect(isClose(moved.sine, 0))
  }
}

private struct UnitCircleTestDocument: Codable {
  let scene: GeometryScene
  let construction: UnitCircleConstruction
}

private func isClose(_ first: Double, _ second: Double, tolerance: Double = 0.000_000_1) -> Bool {
  abs(first - second) <= tolerance
}
