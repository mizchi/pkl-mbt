///|
/// Mutable state of one property thunk. The state transition is monotonic:
/// Pending -> Evaluating -> Resolved/Rejected. Re-entering Evaluating is the
/// structural cycle check; both successful values and failures are memoized.
pub enum EvalThunkState {
  PendingThunk
  EvaluatingThunk
  ResolvedThunk(Value)
  RejectedThunk(String)
}

///|
priv enum EvalThunkResult {
  ThunkOk(Value)
  ThunkError(String)
}

///|

///|
/// Opaque runtime handle for a memoized property computation. `Value` is a
/// public enum, so the payload type is public as well; its fields remain
/// private and cells can only be created and forced by the evaluator API.
pub struct EvalThunkCell {
  priv id : Int
  priv name : String
  priv state : Ref[EvalThunkState]
  priv computation : Ref[(() -> Value)?]
  priv force_count : Ref[Int]
}

///|
pub impl Eq for EvalThunkCell with fn equal(self, other) {
  self.id == other.id
}

///|
pub impl Debug for EvalThunkCell with fn to_repr(self) {
  Repr::literal("EvalThunkCell(\{self.id})")
}

///|
// Only identity allocation is process-global. Unlike the old registry, this
// counter retains no cell, computation closure, module cache, or Value graph.
let next_eval_thunk_id : Ref[Int] = { val: 0 }

///|
/// Force one runtime value when it is a property thunk. Ordinary values are
/// returned unchanged. `eval_path` already materializes its visible result;
/// this API is for consumers of `eval_path_with_runtime_metadata` and for
/// runtime integrations that inspect `ValueMember.value` directly.
pub fn force_value(value : Value) -> Value {
  force_eval_thunk(value)
}

///|
fn reserve_eval_thunk(name : String) -> EvalThunkCell {
  let id = next_eval_thunk_id.val
  next_eval_thunk_id.val = id + 1
  {
    id,
    name,
    state: { val: PendingThunk },
    computation: { val: None },
    force_count: { val: 0 },
  }
}

///|
fn initialize_eval_thunk(
  cell : EvalThunkCell,
  computation : () -> EvalThunkResult,
) -> Unit {
  cell.computation.val = Some(fn() {
    match computation() {
      ThunkOk(value) => value
      ThunkError(message) => deferred_error_value(message)
    }
  })
}

///|
fn force_eval_thunk(value : Value) -> Value {
  match value {
    ThunkValue(cell) => force_eval_thunk_cell(cell)
    _ => value
  }
}

///|
fn force_eval_thunk_cell(cell : EvalThunkCell) -> Value {
  match cell.state.val {
    ResolvedThunk(value) => value
    RejectedThunk(message) => deferred_error_value(message)
    EvaluatingThunk =>
      deferred_error_value("cyclic property reference \{cell.name}")
    PendingThunk => {
      cell.state.val = EvaluatingThunk
      cell.force_count.val = cell.force_count.val + 1
      match cell.computation.val {
        Some(computation) => {
          let value = computation()
          match direct_eval_thunk_error_message(value) {
            None => {
              cell.state.val = ResolvedThunk(value)
              // A resolved cell no longer needs its lexical environment.
              // Dropping the closure here breaks the common
              // cell -> computation -> object members -> cell retention cycle
              // immediately instead of waiting for a tracing-GC cycle pass.
              cell.computation.val = None
              value
            }
            Some(message) => {
              cell.state.val = RejectedThunk(message)
              cell.computation.val = None
              value
            }
          }
        }
        None => {
          let message = "Property thunk `\{cell.name}` was not initialized."
          cell.state.val = RejectedThunk(message)
          deferred_error_value(message)
        }
      }
    }
  }
}

///|
// `deferred_error_message` intentionally forces thunk values. A freshly run
// computation must be classified without triggering another cell, so inspect
// only the reserved deferred-error marker here.
fn direct_eval_thunk_error_message(value : Value) -> String? {
  match value {
    ObjectValue(members) =>
      match lookup_member(members, error_member_name("@deferred")) {
        Some(StringValue(message)) => Some(message)
        _ => None
      }
    _ => None
  }
}
