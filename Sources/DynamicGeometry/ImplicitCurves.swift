import Foundation

/// A finite rectangular definition of the implicit relation `F(x, y) = 0`.
public struct ImplicitCurveDefinition: Codable, Equatable, Sendable {
  /// The two-variable function whose zero set is approximated.
  public let relation: ScalarFunction2D

  /// The finite horizontal extraction bounds.
  public let horizontalDomain: ClosedRange<Double>

  /// The finite vertical extraction bounds.
  public let verticalDomain: ClosedRange<Double>

  /// Creates a validated implicit-curve definition.
  public init(
    relation: ScalarFunction2D,
    horizontalDomain: ClosedRange<Double>,
    verticalDomain: ClosedRange<Double>
  ) throws {
    try validateImplicitDomain(horizontalDomain)
    try validateImplicitDomain(verticalDomain)
    self.relation = relation
    self.horizontalDomain = horizontalDomain
    self.verticalDomain = verticalDomain
  }

  /// Extracts bounded approximate contour segments with a marching-squares-style grid.
  ///
  /// The result never claims mathematical completeness. Cells with undefined corner
  /// values, coincident zero-valued edges, or ambiguous topology are omitted and
  /// reported as structured diagnostics instead of being connected speculatively.
  public func extractContours(
    columns: Int,
    rows: Int,
    parameters: [ScalarParameter] = []
  ) throws -> ImplicitContourResult {
    guard columns >= 1, rows >= 1 else {
      throw FunctionConstructionError.invalidSampleCount(minimum: 1)
    }
    let samples = makeImplicitGrid(columns: columns, rows: rows, parameters: parameters)
    var segments: [ImplicitContourSegment] = []
    var diagnostics: [ImplicitContourDiagnostic] = []
    for row in 0..<rows {
      for column in 0..<columns {
        let corners = implicitCellCorners(
          samples: samples,
          column: column,
          row: row,
          columns: columns)
        let center = implicitCellCenter(
          corners: corners,
          parameters: parameters)
        switch extractImplicitCell(corners, center: center) {
        case .empty:
          break
        case .segment(let segment):
          segments.append(segment)
        case .unresolved(let kind):
          diagnostics.append(
            ImplicitContourDiagnostic(
              column: column,
              row: row,
              kind: kind,
              cornerOutcomes: corners.map(\.outcome),
              interiorProbeOutcome: center.outcome))
        }
      }
    }
    return ImplicitContourResult(
      segments: segments,
      diagnostics: diagnostics,
      coverage: .boundedApproximation)
  }

  private func makeImplicitGrid(
    columns: Int,
    rows: Int,
    parameters: [ScalarParameter]
  ) -> [ImplicitGridSample] {
    let horizontalStep = horizontalDomain.width / Double(columns)
    let verticalStep = verticalDomain.width / Double(rows)
    return (0...rows).flatMap { row in
      (0...columns).map { column in
        let point = Point2D(
          x: horizontalDomain.lowerBound + Double(column) * horizontalStep,
          y: verticalDomain.lowerBound + Double(row) * verticalStep)
        return ImplicitGridSample(
          point: point,
          outcome: relation.evaluate(at: point, parameters: parameters))
      }
    }
  }

  private func implicitCellCenter(
    corners: [ImplicitGridSample],
    parameters: [ScalarParameter]
  ) -> ImplicitGridSample {
    let point = Point2D(
      x: (corners[0].point.x + corners[2].point.x) / 2,
      y: (corners[0].point.y + corners[2].point.y) / 2)
    return ImplicitGridSample(
      point: point,
      outcome: relation.evaluate(at: point, parameters: parameters))
  }

  private enum CodingKeys: CodingKey {
    case relation
    case horizontalDomain
    case verticalDomain
  }

  /// Decodes and validates a stored implicit-curve definition.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      relation: container.decode(ScalarFunction2D.self, forKey: .relation),
      horizontalDomain: container.decode(
        ClosedRange<Double>.self,
        forKey: .horizontalDomain),
      verticalDomain: container.decode(
        ClosedRange<Double>.self,
        forKey: .verticalDomain))
  }
}

/// The deliberately limited coverage statement for an implicit contour extraction.
public enum ImplicitContourCoverage: String, Equatable, Sendable {
  /// Segments approximate only the requested finite bounds at the requested grid resolution.
  case boundedApproximation
}

/// A finite line segment produced inside one resolved grid cell.
public struct ImplicitContourSegment: Equatable, Sendable {
  /// The first interpolated zero crossing.
  public let start: Point2D

  /// The second interpolated zero crossing.
  public let end: Point2D

  /// Creates an approximate contour segment.
  public init(start: Point2D, end: Point2D) {
    self.start = start
    self.end = end
  }
}

/// Why a bounded implicit-grid cell could not be resolved honestly.
public enum ImplicitContourDiagnosticKind: String, Equatable, Sendable {
  /// At least one corner did not have a finite value.
  case undefinedCorner

  /// The cell-center safety probe did not have a finite value.
  case undefinedInteriorProbe

  /// Four edge crossings admit more than one topology.
  case ambiguousTopology

  /// A zero-valued edge or degenerate crossing cannot produce one unique segment.
  case unresolvedTopology
}

/// A structured record of an implicit-grid cell omitted from the contour result.
public struct ImplicitContourDiagnostic: Equatable, Sendable {
  /// The zero-based horizontal cell index.
  public let column: Int

  /// The zero-based vertical cell index.
  public let row: Int

  /// The reason this cell was omitted.
  public let kind: ImplicitContourDiagnosticKind

  /// The four corner evaluations in bottom-left clockwise order.
  public let cornerOutcomes: [ScalarEvaluationOutcome]

  /// The cell-center evaluation used to detect contours hidden between corners.
  public let interiorProbeOutcome: ScalarEvaluationOutcome

  /// Creates a diagnostic for an unresolved cell.
  public init(
    column: Int,
    row: Int,
    kind: ImplicitContourDiagnosticKind,
    cornerOutcomes: [ScalarEvaluationOutcome],
    interiorProbeOutcome: ScalarEvaluationOutcome
  ) {
    self.column = column
    self.row = row
    self.kind = kind
    self.cornerOutcomes = cornerOutcomes
    self.interiorProbeOutcome = interiorProbeOutcome
  }
}

/// Approximate contour segments and every cell the extractor declined to resolve.
public struct ImplicitContourResult: Equatable, Sendable {
  /// Independent segments that a renderer may draw without inventing connections.
  public let segments: [ImplicitContourSegment]

  /// Undefined, ambiguous, or degenerate cells omitted from the segments.
  public let diagnostics: [ImplicitContourDiagnostic]

  /// The extraction's explicit non-completeness guarantee.
  public let coverage: ImplicitContourCoverage

  /// Creates an implicit contour result.
  public init(
    segments: [ImplicitContourSegment],
    diagnostics: [ImplicitContourDiagnostic],
    coverage: ImplicitContourCoverage
  ) {
    self.segments = segments
    self.diagnostics = diagnostics
    self.coverage = coverage
  }
}

private struct ImplicitGridSample {
  let point: Point2D
  let outcome: ScalarEvaluationOutcome
}

private enum ImplicitCellExtraction {
  case empty
  case segment(ImplicitContourSegment)
  case unresolved(ImplicitContourDiagnosticKind)
}

private enum ImplicitEdgeIntersection {
  case none
  case point(Point2D)
  case coincident
}

private enum ImplicitIntersectionCollection {
  case points([Point2D])
  case unresolved
}

private func implicitCellCorners(
  samples: [ImplicitGridSample],
  column: Int,
  row: Int,
  columns: Int
) -> [ImplicitGridSample] {
  let rowWidth = columns + 1
  let bottomLeft = row * rowWidth + column
  let bottomRight = bottomLeft + 1
  let topLeft = bottomLeft + rowWidth
  let topRight = topLeft + 1
  return [
    samples[bottomLeft],
    samples[bottomRight],
    samples[topRight],
    samples[topLeft],
  ]
}

private func extractImplicitCell(
  _ corners: [ImplicitGridSample],
  center: ImplicitGridSample
) -> ImplicitCellExtraction {
  guard corners.allSatisfy({ $0.outcome.value != nil }) else {
    return .unresolved(.undefinedCorner)
  }
  guard let centerValue = center.outcome.value else {
    return .unresolved(.undefinedInteriorProbe)
  }
  switch collectImplicitIntersections(corners) {
  case .unresolved:
    return .unresolved(.unresolvedTopology)
  case .points(let intersections):
    return classifyImplicitIntersections(
      intersections,
      corners: corners,
      centerValue: centerValue)
  }
}

private func collectImplicitIntersections(
  _ corners: [ImplicitGridSample]
) -> ImplicitIntersectionCollection {
  var intersections: [Point2D] = []
  for edgeIndex in 0..<corners.count {
    let nextIndex = (edgeIndex + 1) % corners.count
    switch implicitEdgeIntersection(corners[edgeIndex], corners[nextIndex]) {
    case .none:
      break
    case .coincident:
      return .unresolved
    case .point(let point):
      if !intersections.contains(point) {
        intersections.append(point)
      }
    }
  }
  return .points(intersections)
}

private func classifyImplicitIntersections(
  _ intersections: [Point2D],
  corners: [ImplicitGridSample],
  centerValue: Double
) -> ImplicitCellExtraction {
  switch intersections.count {
  case 0:
    guard let cornerValue = corners[0].outcome.value else {
      return .unresolved(.undefinedCorner)
    }
    if centerValue == 0 || (centerValue < 0) != (cornerValue < 0) {
      return .unresolved(.unresolvedTopology)
    }
    return .empty
  case 2:
    return .segment(ImplicitContourSegment(start: intersections[0], end: intersections[1]))
  case 4:
    return .unresolved(.ambiguousTopology)
  default:
    return .unresolved(.unresolvedTopology)
  }
}

private func implicitEdgeIntersection(
  _ first: ImplicitGridSample,
  _ second: ImplicitGridSample
) -> ImplicitEdgeIntersection {
  guard let firstValue = first.outcome.value, let secondValue = second.outcome.value else {
    return .none
  }
  if firstValue == 0, secondValue == 0 {
    return .coincident
  }
  if firstValue == 0 {
    return .point(first.point)
  }
  if secondValue == 0 {
    return .point(second.point)
  }
  guard (firstValue < 0) != (secondValue < 0) else {
    return .none
  }
  let amount = firstValue / (firstValue - secondValue)
  return .point(
    Point2D(
      x: first.point.x + amount * (second.point.x - first.point.x),
      y: first.point.y + amount * (second.point.y - first.point.y)))
}

private func validateImplicitDomain(_ domain: ClosedRange<Double>) throws {
  guard domain.lowerBound.isFinite, domain.upperBound.isFinite else {
    throw FunctionConstructionError.nonFiniteBounds
  }
  guard domain.lowerBound < domain.upperBound else {
    throw FunctionConstructionError.invalidBounds
  }
}

extension ClosedRange where Bound == Double {
  fileprivate var width: Double {
    upperBound - lowerBound
  }
}
