import Foundation

extension ParametricSurfaceDefinition {
  /// Samples the bounded parameter rectangle into a finite indexed triangle mesh.
  ///
  /// Undefined coordinate evaluations create holes rather than placeholder vertices. Diagnostics
  /// identify every omitted point and degenerate triangle.
  public func sample(
    uSampleCount: Int,
    vSampleCount: Int,
    parameters: [ScalarParameter] = []
  ) throws -> ParametricSurfaceMesh {
    guard uSampleCount >= 2, vSampleCount >= 2 else {
      throw ParametricSurfaceError.invalidSampleCount(minimum: 2)
    }

    let uStep = (uDomain.upperBound - uDomain.lowerBound) / Double(uSampleCount - 1)
    let vStep = (vDomain.upperBound - vDomain.lowerBound) / Double(vSampleCount - 1)
    var meshBuilder = SurfaceMeshBuilder(uSampleCount: uSampleCount)

    for vIndex in 0..<vSampleCount {
      let vValue = vDomain.lowerBound + Double(vIndex) * vStep
      for uIndex in 0..<uSampleCount {
        let uValue = uDomain.lowerBound + Double(uIndex) * uStep
        let gridIndex = vIndex * uSampleCount + uIndex
        switch evaluatePoint(uValue: uValue, vValue: vValue, parameters: parameters) {
        case .point(let point):
          meshBuilder.append(point: point, uValue: uValue, vValue: vValue, at: gridIndex)
        case .diagnostics(let pointDiagnostics):
          meshBuilder.append(diagnostics: pointDiagnostics)
        }
      }
    }

    for vIndex in 0..<(vSampleCount - 1) {
      for uIndex in 0..<(uSampleCount - 1) {
        meshBuilder.appendCellTriangles(uIndex: uIndex, vIndex: vIndex)
      }
    }
    return meshBuilder.mesh
  }

  private func evaluatePoint(
    uValue: Double,
    vValue: Double,
    parameters: [ScalarParameter]
  ) -> SurfacePointEvaluation {
    let independentParameters: [ScalarParameter]
    do {
      independentParameters = [
        try ScalarParameter(id: uVariableID, name: uVariableName, value: uValue),
        try ScalarParameter(id: vVariableID, name: vVariableName, value: vValue),
      ]
    } catch {
      let outcome = ScalarEvaluationOutcome.undefined(diagnostic: error.localizedDescription)
      return .diagnostics([
        makeDiagnostic(uValue: uValue, vValue: vValue, coordinate: .x, outcome: outcome),
        makeDiagnostic(uValue: uValue, vValue: vValue, coordinate: .y, outcome: outcome),
        makeDiagnostic(uValue: uValue, vValue: vValue, coordinate: .z, outcome: outcome),
      ])
    }

    let bindings = independentParameters + parameters
    let evaluations = [
      SurfaceCoordinateEvaluation(
        coordinate: .x, outcome: xExpression.evaluate(parameters: bindings)),
      SurfaceCoordinateEvaluation(
        coordinate: .y, outcome: yExpression.evaluate(parameters: bindings)),
      SurfaceCoordinateEvaluation(
        coordinate: .z, outcome: zExpression.evaluate(parameters: bindings)),
    ]
    let failed = evaluations.filter { $0.outcome.value == nil }
    guard failed.isEmpty else {
      return .diagnostics(
        failed.map {
          makeDiagnostic(
            uValue: uValue,
            vValue: vValue,
            coordinate: $0.coordinate,
            outcome: $0.outcome)
        })
    }

    do {
      return .point(
        try Point3D(
          x: evaluations[0].outcome.value ?? .nan,
          y: evaluations[1].outcome.value ?? .nan,
          z: evaluations[2].outcome.value ?? .nan))
    } catch {
      return .diagnostics([
        makeDiagnostic(
          uValue: uValue,
          vValue: vValue,
          coordinate: .x,
          outcome: .undefined(diagnostic: error.localizedDescription))
      ])
    }
  }

  private func makeDiagnostic(
    uValue: Double,
    vValue: Double,
    coordinate: ParametricSurfaceCoordinate,
    outcome: ScalarEvaluationOutcome
  ) -> ParametricSurfaceSamplingDiagnostic {
    ParametricSurfaceSamplingDiagnostic(
      u: uValue,
      v: vValue,
      issue: .coordinate(coordinate, outcome: outcome))
  }
}

private struct SurfaceMeshBuilder {
  let uSampleCount: Int
  var vertices: [ParametricSurfaceVertex] = []
  var vertexIndices: [Int: Int] = [:]
  var triangles: [ParametricSurfaceTriangle] = []
  var diagnostics: [ParametricSurfaceSamplingDiagnostic] = []

  var mesh: ParametricSurfaceMesh {
    ParametricSurfaceMesh(
      vertices: vertices,
      triangles: triangles,
      diagnostics: diagnostics)
  }

  mutating func append(point: Point3D, uValue: Double, vValue: Double, at gridIndex: Int) {
    vertexIndices[gridIndex] = vertices.count
    vertices.append(ParametricSurfaceVertex(point: point, u: uValue, v: vValue))
  }

  mutating func append(diagnostics newDiagnostics: [ParametricSurfaceSamplingDiagnostic]) {
    diagnostics.append(contentsOf: newDiagnostics)
  }

  mutating func appendCellTriangles(uIndex: Int, vIndex: Int) {
    let lowerLeftGridIndex = vIndex * uSampleCount + uIndex
    let lowerRightGridIndex = lowerLeftGridIndex + 1
    let upperLeftGridIndex = lowerLeftGridIndex + uSampleCount
    let upperRightGridIndex = upperLeftGridIndex + 1
    guard
      let lowerLeft = vertexIndices[lowerLeftGridIndex],
      let lowerRight = vertexIndices[lowerRightGridIndex],
      let upperLeft = vertexIndices[upperLeftGridIndex],
      let upperRight = vertexIndices[upperRightGridIndex]
    else {
      return
    }

    let location = vertices[lowerLeft]
    appendTriangle(
      SurfaceTriangleIndices(first: lowerLeft, second: lowerRight, third: upperLeft),
      at: location)
    appendTriangle(
      SurfaceTriangleIndices(first: lowerRight, second: upperRight, third: upperLeft),
      at: location)
  }

  private mutating func appendTriangle(
    _ indices: SurfaceTriangleIndices,
    at location: ParametricSurfaceVertex
  ) {
    do {
      let first = vertices[indices.first].point
      let firstEdge = try first.displacement(to: vertices[indices.second].point)
      let secondEdge = try first.displacement(to: vertices[indices.third].point)
      let normal = try firstEdge.cross(secondEdge).normalized()
      triangles.append(
        ParametricSurfaceTriangle(
          firstVertexIndex: indices.first,
          secondVertexIndex: indices.second,
          thirdVertexIndex: indices.third,
          normal: normal))
    } catch {
      diagnostics.append(
        ParametricSurfaceSamplingDiagnostic(
          u: location.u,
          v: location.v,
          issue: .degenerateTriangle(diagnostic: error.localizedDescription)))
    }
  }
}

private struct SurfaceTriangleIndices {
  let first: Int
  let second: Int
  let third: Int
}

private struct SurfaceCoordinateEvaluation {
  let coordinate: ParametricSurfaceCoordinate
  let outcome: ScalarEvaluationOutcome
}

private enum SurfacePointEvaluation {
  case point(Point3D)
  case diagnostics([ParametricSurfaceSamplingDiagnostic])
}
