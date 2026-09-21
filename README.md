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
- Semantic parametric and polar curves plus bounded implicit-contour extraction
- Semantic left, right, and midpoint Riemann sums with signed rectangles
- Validated 3D points, vectors, affine transforms, and sampled parametric surface meshes
- Structure-preserving symbolic simplification, differentiation, and degree-two polynomial solving
- A bounded local solver for simultaneous scalar equalities
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

Version `0.2.0` adds the advanced curve, 3D geometry, symbolic algebra, simultaneous constraint,
expression, transform, and incremental-evaluation APIs described below. Add:

```swift
dependencies: [
  .package(
    url: "https://github.com/kodlabs-in/DynamicGeometry.git",
    from: "0.2.0"
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

## Advanced curves

Parametric and polar definitions preserve their mathematical meaning while leaving resolution and
rendering to the host. Implicit contours use a bounded grid and return diagnostics for ambiguous,
degenerate, hidden, or undefined cells instead of claiming a complete zero set.

```swift
let theta = ScalarParameterID()
let rose = try PolarCurveDefinition(
  radiusFunction: ScalarFunction1D(
    independentVariableID: theta,
    expression: .function(
      .cosine,
      argument: .arithmetic(
        left: .constant(5),
        operation: .multiplication,
        right: .parameter(.identified(theta))))),
  angleDomain: 0...(2 * .pi))

let roseSamples = try rose.sample(sampleCount: 256)
```

Use `ParametricCurveDefinition` for `(x(t), y(t))` and `ImplicitCurveDefinition` with a
`ScalarFunction2D` for relations such as `x² + y² - r² = 0`. Render curve branches independently
and surface every returned diagnostic in authoring or debugging tools.

## 3D geometry and surfaces

`Point3D`, `Vector3D`, and `CoordinateTransform3D` are renderer-independent. A
`ParametricSurfaceDefinition` samples `(x(u,v), y(u,v), z(u,v))` into indexed triangles with unit
face normals. Undefined coordinates create diagnosed holes rather than invalid vertices.

```swift
let surface = try ParametricSurfaceDefinition(
  xExpression: .parameter(.named("u")),
  yExpression: .parameter(.named("v")),
  zExpression: .constant(0),
  uDomain: -1...1,
  vDomain: -1...1)
let mesh = try surface.sample(uSampleCount: 24, vSampleCount: 24)
```

The package does not provide a camera or renderer. Sampling is a fixed rectangular mesh, normals
are per triangle, and no manifold or adaptive-tessellation guarantee is made.

## Symbolic algebra and simultaneous constraints

Supported symbolic transformations return `.exact`; requests outside the implemented algebra
return typed `.unsupported` or `.invalid` outcomes. Differentiation supports arithmetic and the
documented scalar functions. Polynomial solving is real, numeric-coefficient, univariate, and
bounded to degree two.

```swift
let xID = ScalarParameterID()
let x = ScalarExpression.parameter(.identified(xID))
let square = ScalarExpression.arithmetic(
  left: x,
  operation: .power,
  right: .constant(2))

let derivative = square.differentiated(withRespectTo: xID)
let roots = ScalarExpression.arithmetic(
  left: square,
  operation: .subtraction,
  right: .constant(1))
  .solvePolynomial(withRespectTo: xID)
```

`ScalarConstraintSystem` solves multiple equalities together with bounded damped least squares.
Initial variable values select the local branch. A converged result satisfies the requested
residual tolerance; it is not a proof of existence, uniqueness, or global completeness.

```swift
let yID = ScalarParameterID()
let y = ScalarExpression.parameter(.identified(yID))
let system = try ScalarConstraintSystem(
  variables: [
    ScalarParameter(id: xID, name: "x", value: 0.8),
    ScalarParameter(id: yID, name: "y", value: 0.8),
  ],
  constraints: [
    ScalarEqualityConstraint(
      left: .arithmetic(left: square, operation: .addition, right: .arithmetic(
        left: y, operation: .power, right: .constant(2))),
      right: .constant(1)),
    ScalarEqualityConstraint(left: x, right: y),
  ])
let outcome = system.solve()
```

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
