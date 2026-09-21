# DynamicGeometry

DynamicGeometry is a UI-independent Swift engine for building interactive mathematical
constructions from reusable geometry, scalar expressions, and explicit dependencies.

The engine stores relationships instead of frozen drawing coordinates. Move a free point or a
point constrained to a circle, and every dependent projection or segment resolves from the new
geometry. A host app remains responsible for rendering, gestures, selection, and persistence UI.

## What it provides

- Finite, Codable two-dimensional geometry values
- Distinct circle, segment, line, and ray semantics
- Free points and points constrained to a circle
- Horizontal and vertical projected points
- A dependency-aware scene with missing-reference and cycle detection
- Shared, scene-owned scalar parameters and expression-backed geometry
- Incremental affected-branch evaluation with deterministic change reports
- Recoverable exact, approximate, undefined, unsupported, nonconvergent, and pending states
- Versioned scene encoding with migration from foundation scenes to schema version 2
- Branch-safe explicit-curve sampling that does not draw through undefined discontinuities
- Semantic left, right, and midpoint Riemann sums with signed rectangles
- Atomic command transactions, cascade-aware deletion, and framework-independent undo/redo
- Capability discovery and a reusable, persisted unit-circle reference construction
- Framework-independent affine coordinate transforms
- Drag projection for both Cartesian and screen-y-down coordinate systems
- No UI framework, storage, analytics, or application-specific dependency

## Requirements

- Swift 6.0 or newer
- iOS or iPadOS 17+
- macOS 14+

## Installation

In Xcode, choose **File → Add Package Dependencies** and enter:

```text
https://github.com/kodlabs-in/DynamicGeometry.git
```

Version `0.1.0` is the published foundation release. The enhanced expression, transform, and
incremental-evaluation APIs are currently unreleased. For the foundation, add:

```swift
dependencies: [
  .package(
    url: "https://github.com/kodlabs-in/DynamicGeometry.git",
    from: "0.1.0"
  )
]
```

Then add `DynamicGeometry` to the target that owns the construction model.

## Minimal construction

```swift
import DynamicGeometry

var scene = GeometryScene()
let center = try scene.addPoint(.free(Point2D(x: 0, y: 0)))
let circle = try scene.addCircle(center: center, radius: 1)
let movingPoint = try scene.addPoint(.onCircle(circle: circle, angleRadians: .pi / 4))
let radius = try scene.addSegment(start: center, end: movingPoint)

let point = try scene.point(movingPoint)
let segment = try scene.segment(radius)
```

For a touch-driven canvas whose y-axis points down, create the scene with
`GeometryScene(coordinateSystem: .screenYDown)`, then project a drag onto the circle with:

```swift
try scene.movePoint(movingPoint, to: dragLocation)
```

Hosts that need targeted redraw or undo information can use the reporting mutation:

```swift
let change = try scene.movePointReportingChanges(movingPoint, to: dragLocation)
redraw(ids: change.affectedEntityIDs)
```

## Scalar expressions

Scalar expressions are data, not executable scripts. They are Codable and return explicit states
for approximate, undefined, unsupported, nonconvergent, and pending results.

```swift
let theta = try ScalarParameter(name: "theta", value: .pi / 4)
let sine = ScalarExpression.function(
  .sine,
  argument: .parameter(.identified(theta.id)))

let result = sine.evaluate(parameters: [theta])
```

Expressions can drive geometry through scene-owned parameters. Updating one parameter returns the
stable identifiers of only the affected branch:

```swift
var scene = GeometryScene()
let radius = try scene.addParameter(name: "radius", value: 2)
let center = try scene.addPoint(.free(Point2D(x: 0, y: 0)))
let circle = try scene.addCircle(
  center: center,
  radius: .parameter(.identified(radius)))

let change = try scene.setParameter(radius, to: 3)
let resolvedCircle = try scene.circle(circle)
redraw(ids: change.affectedEntityIDs)
```

## Curves and Riemann sums

Explicit functions and Riemann sums are Codable semantic definitions. Sampled branches and
rectangles are derived results, so hosts can choose their own rendering resolution without
persisting thousands of generated entities.

```swift
let x = ScalarParameterID()
let square = try ScalarFunction1D(
  independentVariableID: x,
  expression: .arithmetic(
    left: .parameter(.identified(x)),
    operation: .power,
    right: .constant(2)))

let curve = try ExplicitCurveDefinition(function: square, domain: -2...2)
let samples = try curve.sample(sampleCount: 129)

let sum = try RiemannSumDefinition(
  function: square,
  interval: 0...1,
  rectangleCount: 32,
  samplingRule: .midpoint)
  .evaluate()
```

Render each entry in `samples.branches` independently. Never connect the end of one branch to the
start of another. `sum.rectangles` preserves negative heights and `sum.signedSum` reports a
structured numerical outcome.

## Commands, deletion, and history

Use `GeometryTransaction` when an interaction must commit atomically. `GeometryHistory` stores one
undo step per transaction and can coalesce a drag or animation under a shared identifier. Deletion
can either reject referenced entities or cascade through all transitive dependents.

```swift
var history = GeometryHistory(scene: scene)
try history.apply(
  GeometryTransaction(commands: [
    .delete(ids: [center], policy: .cascadeDependents)
  ]))

_ = history.undo()
```

`GeometryCapabilities.current` lets reusable hosts discover supported features before presenting a
tool. `UnitCircleConstruction.insert(into:)` provides a package-owned reference recipe with shared
radius and angle parameters, drag projection, snapshots, and Codable stable identifiers.

Use `CoordinateTransform2D` to move between mathematical, page, and viewport coordinates without
introducing a Core Graphics or SwiftUI dependency into the engine.

See [DynamicGeometrySandbox](https://github.com/kodlabs-in/DynamicGeometrySandbox) for a runnable
unit-circle construction.

## Development

```bash
make format
make check SWIFT_TEST_FLAGS=--disable-sandbox
make release-check SWIFT_TEST_FLAGS=--disable-sandbox
```

## License

DynamicGeometry is available under the [MIT License](LICENSE).
