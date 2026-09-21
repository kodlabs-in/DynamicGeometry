/// A UI-independent transaction history for one geometry scene.
public struct GeometryHistory: Sendable {
  /// The scene at the current history position.
  public private(set) var scene: GeometryScene

  private var undoScenes: [GeometryScene]
  private var redoScenes: [GeometryScene]
  private var lastCoalescingID: String?

  /// Creates an empty history around an existing or new scene.
  public init(scene: GeometryScene = GeometryScene()) {
    self.scene = scene
    undoScenes = []
    redoScenes = []
    lastCoalescingID = nil
  }

  /// Whether an earlier successful transaction can be restored.
  public var canUndo: Bool {
    !undoScenes.isEmpty
  }

  /// Whether a previously undone transaction can be restored.
  public var canRedo: Bool {
    !redoScenes.isEmpty
  }

  /// Applies a transaction and records its complete before-state as one undo step.
  @discardableResult
  public mutating func apply(
    _ transaction: GeometryTransaction,
    coalescingID: String? = nil
  ) throws -> GeometryTransactionResult {
    let previous = scene
    let result = try scene.apply(transaction)
    if !transaction.commands.isEmpty {
      if coalescingID == nil || coalescingID != lastCoalescingID {
        undoScenes.append(previous)
      }
      redoScenes.removeAll()
      lastCoalescingID = coalescingID
    }
    return result
  }

  /// Restores the scene before the latest successful transaction.
  @discardableResult
  public mutating func undo() -> Bool {
    guard let previous = undoScenes.popLast() else { return false }
    redoScenes.append(scene)
    scene = previous
    lastCoalescingID = nil
    return true
  }

  /// Reapplies the latest undone transaction state.
  @discardableResult
  public mutating func redo() -> Bool {
    guard let next = redoScenes.popLast() else { return false }
    undoScenes.append(scene)
    scene = next
    lastCoalescingID = nil
    return true
  }
}
