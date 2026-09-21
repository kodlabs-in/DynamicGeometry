extension GeometryScene {
  func validateLiteralInputs(_ entity: GeometryEntity) throws {
    for expression in entity.scalarExpressions {
      try expression.validate()
    }
    switch entity {
    case .point(.free(let point)):
      try requireFinite(point, name: "Point")
    case .point(.onCircle(_, let angle)):
      try requireFinite(angle, name: "Angle")
    case .point(.horizontalProjection(_, let y)):
      try requireFinite(y, name: "Horizontal projection")
    case .point(.verticalProjection(_, let x)):
      try requireFinite(x, name: "Vertical projection")
    case .circle(let definition):
      try validateLiteralDimension(definition.radius, name: "Circle radius")
    case .ellipse(let definition):
      try validateLiteralDimension(definition.radiusX, name: "Ellipse radius")
      try validateLiteralDimension(definition.radiusY, name: "Ellipse radius")
    default:
      break
    }
  }

  func validateIdentity() throws {
    guard orderedParameterIDs.count == Set(orderedParameterIDs).count,
      Set(orderedParameterIDs) == Set(parameters.keys),
      orderedIDs.count == Set(orderedIDs).count,
      Set(orderedIDs) == Set(entities.keys)
    else {
      throw GeometryError.inconsistentScene
    }
  }

  private func validateLiteralDimension(
    _ expression: ScalarExpression,
    name: String
  ) throws {
    guard case .constant(let value) = expression else {
      return
    }
    try requireFinite(value, name: name)
    guard value > 0 else {
      throw GeometryError.nonPositiveDimension(name)
    }
  }

  private func requireFinite(_ value: Double, name: String) throws {
    guard value.isFinite else {
      throw GeometryError.nonFiniteValue(name)
    }
  }

  private func requireFinite(_ point: Point2D, name: String) throws {
    guard point.isFinite else {
      throw GeometryError.nonFiniteValue(name)
    }
  }
}
