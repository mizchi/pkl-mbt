///|
/// Native argv already starts with the mpkl executable path.
fn cli_args() -> Array[String] {
  @env.args()
}
