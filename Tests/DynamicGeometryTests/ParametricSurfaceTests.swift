import Foundation
import Testing

@testable import DynamicGeometry

@Suite("Parametric surfaces")
struct ParametricSurfaceTests {
  @Test("A plane samples into an indexed mesh with consistently oriented normals")
  func samplesPlaneMesh() throws {
    let surface = try ParametricSurfaceDefinition(
      xExpression: .parameter(.named("u")),
      yExpression: .parameter(.named("v")),
      zExpression: .constant(0),
      uDomain: 0...1,
      vDomain: 0...1)

    let mesh = try surface.sample(uSampleCount: 2, vSampleCount: 2)

    #expect(
      mesh.vertices.map(\.point) == [
        try Point3D(x: 0, y: 0, z: 0),
        try Point3D(x: 1, y: 0, z: 0),
        try Point3D(x: 0, y: 1, z: 0),
        try Point3D(x: 1, y: 1, z: 0),
      ])
    #expect(mesh.triangles.count == 2)
    #expect(mesh.triangles.allSatisfy { $0.normal == (try? Vector3D(x: 0, y: 0, z: 1)) })
    #expect(mesh.diagnostics.isEmpty)
  }

  @Test("Undefined coordinate evaluations create diagnosed holes instead of invalid vertices")
  func preservesUndefinedSamples() throws {
    let surface = try ParametricSurfaceDefinition(
      xExpression: .arithmetic(
        left: .constant(1),
        operation: .division,
        right: .arithmetic(
          left: .parameter(.named("u")),
          operation: .subtraction,
          right: .constant(0.5))),
      yExpression: .parameter(.named("v")),
      zExpression: .constant(0),
      uDomain: 0...1,
      vDomain: 0...1)

    let mesh = try surface.sample(uSampleCount: 3, vSampleCount: 2)

    #expect(mesh.vertices.count == 4)
    #expect(mesh.triangles.isEmpty)
    #expect(mesh.diagnostics.count == 2)
    #expect(
      mesh.diagnostics.allSatisfy {
        guard case .coordinate(.x, outcome: .undefined) = $0.issue else {
          return false
        }
        return $0.u == 0.5
      })
  }

  @Test("A persisted unit-sphere patch preserves residuals and outward topology")
  func persistsUnitSpherePatch() throws {
    let uID = ScalarParameterID()
    let vID = ScalarParameterID()
    let uExpression = ScalarExpression.parameter(.identified(uID))
    let vExpression = ScalarExpression.parameter(.identified(vID))
    let cosineV = ScalarExpression.function(.cosine, argument: vExpression)
    let surface = try ParametricSurfaceDefinition(
      uVariableID: uID,
      vVariableID: vID,
      xExpression: .arithmetic(
        left: .function(.cosine, argument: uExpression),
        operation: .multiplication,
        right: cosineV),
      yExpression: .arithmetic(
        left: .function(.sine, argument: uExpression),
        operation: .multiplication,
        right: cosineV),
      zExpression: .function(.sine, argument: vExpression),
      uDomain: (-Double.pi / 4)...(Double.pi / 4),
      vDomain: (-Double.pi / 4)...(Double.pi / 4))
    let persisted = try JSONDecoder().decode(
      ParametricSurfaceDefinition.self,
      from: JSONEncoder().encode(surface))

    let mesh = try persisted.sample(uSampleCount: 3, vSampleCount: 3)

    #expect(persisted == surface)
    #expect(mesh.vertices.count == 9)
    #expect(mesh.triangles.count == 8)
    #expect(mesh.diagnostics.isEmpty)
    #expect(
      mesh.vertices.allSatisfy {
        abs($0.point.x * $0.point.x + $0.point.y * $0.point.y + $0.point.z * $0.point.z - 1)
          < 0.000_000_001
      })
    #expect(
      mesh.triangles.allSatisfy {
        let first = mesh.vertices[$0.firstVertexIndex].point
        let second = mesh.vertices[$0.secondVertexIndex].point
        let third = mesh.vertices[$0.thirdVertexIndex].point
        let centroidX = (first.x + second.x + third.x) / 3
        let centroidY = (first.y + second.y + third.y) / 3
        let centroidZ = (first.z + second.z + third.z) / 3
        return $0.normal.x * centroidX + $0.normal.y * centroidY + $0.normal.z * centroidZ > 0
      })
  }
}
