extension GeometryEntity {
  var dependencyIDs: [GeometryID] {
    switch self {
    case .point(.free), .point(.computed):
      []
    case .point(.onCircle(let circleID, _)),
      .point(.onCircleExpression(let circleID, _)):
      [circleID]
    case .point(.horizontalProjection(let pointID, _)),
      .point(.horizontalProjectionExpression(let pointID, _)),
      .point(.verticalProjection(let pointID, _)),
      .point(.verticalProjectionExpression(let pointID, _)):
      [pointID]
    case .circle(let definition):
      [definition.center]
    case .ellipse(let definition):
      [definition.center]
    case .segment(let definition):
      [definition.start, definition.end]
    case .line(let definition):
      [definition.first, definition.second]
    case .ray(let definition):
      [definition.origin, definition.through]
    }
  }

  var referencedParameterIDs: [ScalarParameterID] {
    switch self {
    case .point(.free), .segment, .line, .ray:
      []
    case .point(.computed(let x, let y)):
      combinedParameterIDs(from: [x, y])
    case .point(.onCircle):
      []
    case .point(.onCircleExpression(_, let angle)):
      angle.referencedParameterIDs
    case .point(.horizontalProjection):
      []
    case .point(.horizontalProjectionExpression(_, let y)):
      y.referencedParameterIDs
    case .point(.verticalProjection):
      []
    case .point(.verticalProjectionExpression(_, let x)):
      x.referencedParameterIDs
    case .circle(let definition):
      definition.radius.referencedParameterIDs
    case .ellipse(let definition):
      combinedParameterIDs(from: [definition.radiusX, definition.radiusY])
    }
  }

  var scalarExpressions: [ScalarExpression] {
    switch self {
    case .point(.free), .point(.onCircle), .point(.horizontalProjection),
      .point(.verticalProjection), .segment, .line, .ray:
      []
    case .point(.computed(let x, let y)):
      [x, y]
    case .point(.onCircleExpression(_, let angle)):
      [angle]
    case .point(.horizontalProjectionExpression(_, let y)):
      [y]
    case .point(.verticalProjectionExpression(_, let x)):
      [x]
    case .circle(let definition):
      [definition.radius]
    case .ellipse(let definition):
      [definition.radiusX, definition.radiusY]
    }
  }

  private func combinedParameterIDs(
    from expressions: [ScalarExpression]
  ) -> [ScalarParameterID] {
    var seen: Set<ScalarParameterID> = []
    return expressions.flatMap(\.referencedParameterIDs).filter { seen.insert($0).inserted }
  }
}
