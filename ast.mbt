///|
pub(all) struct Diagnostic {
  message : String
} derive(Eq, Debug)

///|
pub(all) struct UnsupportedSyntax {
  start : Int
  end : Int
  text : String
  kind : String
} derive(Eq, Debug)

///|
pub(all) enum BinaryOp {
  Add
  Subtract
  Multiply
  Divide
  IntDivide
  Modulo
  Power
  Equal
  NotEqual
  LessThan
  LessOrEqual
  GreaterThan
  GreaterOrEqual
  And
  Or
  NullCoalesce
  Is
  As
  Pipe
} derive(Eq, Debug)

///|
pub(all) enum UnaryOp {
  Negate
  Not
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
  ListingLiteral(Array[Expr])
  MappingLiteral(Array[MappingEntry])
  MemberAccess(Expr, String)
  SafeMemberAccess(Expr, String)
  SubscriptAccess(Expr, Expr)
  AmendExpr(Expr, Array[ObjectMember])
  CallExpr(Expr, Array[Expr])
  LambdaExpr(Array[FunctionParameter], Expr, String?)
  NonNullExpr(Expr)
  UnaryExpr(UnaryOp, Expr)
  BinaryExpr(BinaryOp, Expr, Expr)
  ConditionalExpr(Expr, Expr, Expr)
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
pub(all) struct MappingEntry {
  key : Expr
  value : Expr
} derive(Eq, Debug)

///|
pub(all) struct ImportDecl {
  uri : String
  import_name : String
} derive(Eq, Debug)

///|
pub(all) enum ModuleRelationKind {
  ModuleAmends
  ModuleExtends
} derive(Eq, Debug)

///|
pub(all) struct ModuleRelation {
  kind : ModuleRelationKind
  uri : String
} derive(Eq, Debug)

///|
pub(all) struct Binding {
  name : String
  type_name : String?
  value : Expr
  exported : Bool
} derive(Eq, Debug)

///|
pub(all) enum Declaration {
  ClassDeclaration(ClassDecl)
  FunctionDeclaration(FunctionDecl)
  TypeAliasDeclaration(TypeAliasDecl)
} derive(Eq, Debug)

///|
pub(all) struct ClassDecl {
  name : String
  properties : Array[ClassProperty]
} derive(Eq, Debug)

///|
pub(all) struct ClassProperty {
  name : String
  type_name : String?
  value : Expr?
} derive(Eq, Debug)

///|
pub(all) struct FunctionDecl {
  name : String
  parameters : Array[FunctionParameter]
  return_type_name : String?
  body : Expr?
} derive(Eq, Debug)

///|
pub(all) struct FunctionParameter {
  name : String
  type_name : String?
} derive(Eq, Debug)

///|
pub(all) struct TypeAliasDecl {
  name : String
  target : String
} derive(Eq, Debug)

///|
pub(all) struct Program {
  module_name : String?
  module_relation : ModuleRelation?
  imports : Array[ImportDecl]
  declarations : Array[Declaration]
  bindings : Array[Binding]
  body : Expr?
} derive(Eq, Debug)

///|
pub(all) struct ParseResult {
  root : @cst.SyntaxNode
  program : Program
  diagnostics : Array[Diagnostic]
  unsupported_syntax : Array[UnsupportedSyntax]
} derive(Eq)
