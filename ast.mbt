///|
pub(all) struct Diagnostic {
  message : String
} derive(Eq, Debug)

///|
pub(all) enum BinaryOp {
  Add
  Subtract
  Multiply
  Divide
} derive(Eq, Debug)

///|
pub(all) enum Expr {
  IntLiteral(Int)
  BoolLiteral(Bool)
  StringLiteral(String)
  NullLiteral
  Identifier(String)
  ImportExpr(String)
  ObjectLiteral(Array[ObjectMember])
  MemberAccess(Expr, String)
  BinaryExpr(BinaryOp, Expr, Expr)
  UnsupportedExpr
  ErrorExpr(String)
} derive(Eq, Debug)

///|
pub(all) struct ObjectMember {
  name : String
  type_name : String?
  value : Expr
} derive(Eq, Debug)

///|
pub(all) struct ImportDecl {
  uri : String
  import_name : String
} derive(Eq, Debug)

///|
pub(all) struct Binding {
  name : String
  type_name : String?
  value : Expr
  exported : Bool
} derive(Eq, Debug)

///|
pub(all) struct Program {
  module_name : String?
  imports : Array[ImportDecl]
  bindings : Array[Binding]
  body : Expr?
} derive(Eq, Debug)

///|
pub(all) struct ParseResult {
  root : @cst.SyntaxNode
  program : Program
  diagnostics : Array[Diagnostic]
} derive(Eq)
