import Foundation
import Testing

@testable import DynamicGeometry

@Suite("Three-dimensional primitives")
struct Geometry3DPrimitiveTests {
  @Test("Points derive finite displacements and vectors expose geometric products")
  func vectorOperations() throws {
    let origin = try Point3D(x: 1, y: 2, z: 3)
    let target = try Point3D(x: 4, y: 6, z: 3)
    let displacement = try origin.displacement(to: target)
    let axisVector = try Vector3D(x: 0, y: 0, z: 1)

    #expect(displacement == (try Vector3D(x: 3, y: 4, z: 0)))
    #expect(try displacement.length() == 5)
    #expect(try displacement.dot(axisVector) == 0)
    #expect(try displacement.cross(axisVector) == (try Vector3D(x: 4, y: -3, z: 0)))
  }

  @Test("Vector normalization preserves direction and rejects the zero vector")
  func normalization() throws {
    let vector = try Vector3D(x: 0, y: 3, z: 4)
    let normalized = try vector.normalized()

    #expect(try normalized.length() == 1)
    #expect(normalized == (try Vector3D(x: 0, y: 0.6, z: 0.8)))
    #expect(throws: Geometry3DError.zeroLengthVector) {
      try Vector3D(x: 0, y: 0, z: 0).normalized()
    }
  }

  @Test("Non-finite primitives fail with typed validation errors")
  func rejectsNonFiniteValues() {
    #expect(throws: Geometry3DError.nonFinitePoint) {
      try Point3D(x: .nan, y: 0, z: 0)
    }
    #expect(throws: Geometry3DError.nonFiniteVector) {
      try Vector3D(x: 0, y: .infinity, z: 0)
    }
  }
}

@Suite("Three-dimensional coordinate transforms")
struct CoordinateTransform3DTests {
  @Test("Translation moves points while leaving vectors unchanged")
  func translationHasPointAndVectorSemantics() throws {
    let transform = try CoordinateTransform3D.translation(x: 10, y: -4, z: 7)
    let point = try Point3D(x: 1, y: 2, z: 3)
    let vector = try Vector3D(x: 1, y: 2, z: 3)

    #expect(try transform.transform(point) == Point3D(x: 11, y: -2, z: 10))
    #expect(try transform.transform(vector) == vector)
  }

  @Test("An invertible persisted transform round-trips points")
  func inverseAndPersistence() throws {
    let scale = try CoordinateTransform3D.scale(x: 2, y: 3, z: 4)
    let translation = try CoordinateTransform3D.translation(x: 5, y: -7, z: 11)
    let transform = try scale.followed(by: translation)
    let persisted = try JSONDecoder().decode(
      CoordinateTransform3D.self,
      from: JSONEncoder().encode(transform))
    let point = try Point3D(x: 2, y: -3, z: 5)

    #expect(persisted == transform)
    #expect(try transform.inverted().transform(transform.transform(point)) == point)
    #expect(throws: Geometry3DError.singularTransform) {
      try CoordinateTransform3D.scale(x: 1, y: 0, z: 1).inverted()
    }
  }
}
