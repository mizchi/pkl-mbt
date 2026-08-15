///|
/// JavaScript argv starts with the JS runtime and script paths. Drop the
/// runtime so command positions match the native `[executable, command, ...]`
/// contract used by the shared dispatcher.
fn cli_args() -> Array[String] {
  let raw = @env.args()
  let args : Array[String] = []
  for i = 1; i < raw.length(); i = i + 1 {
    args.push(raw[i])
  }
  args
}
