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
  FloatLiteral(Double)
  BoolLiteral(Bool)
  StringLiteral(String)
  NullLiteral
  Identifier(String)
  ImportExpr(String)
  ObjectLiteral(Array[ObjectMember])
  TypedObjectLiteral(String, Array[ObjectMember])
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
  ForGenerator(String, String?, Expr, Array[ObjectMember])
  // PKL-136: synthetic wrapper emitted by the parser when a `when (cond)` block
  // appears inside a Listing or Mapping body. The wrapped expression is a
  // `ConditionalExpr` whose branches are `ListingLiteral` (for Listing bodies)
  // or `MappingLiteral` (for Mapping bodies). The listing / mapping evaluator
  // recognises this variant and spreads the resulting collection's contents
  // into the parent body instead of attaching it as a single element / entry.
  WhenSpread(Expr)
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
  // PKL-089: optional list of type parameter names (`class Box<T, U>` →
  // `["T", "U"]`). Empty for non-generic classes. The names introduce
  // scope-local pseudo-types inside the class body that the typechecker
  // treats as `UnknownType` until instantiation-time binding (PKL-090)
  // lands; until then the field is purely a parser-side acknowledgement.
  type_parameters : Array[String]
  // PKL-116: parallel list of optional bounds (`class Box<T : Number>` →
  // `[Some("Number")]`). Length matches `type_parameters`; entries are
  // `None` when no bound was declared. The typechecker enforces
  // `type_accepts(bound, concrete)` when call-site substitution binds T.
  type_parameter_bounds : Array[String?]
  parent_name : String?
  properties : Array[ClassProperty]
  methods : Array[FunctionDecl]
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
  // PKL-090: optional list of type parameter names (`function id<T>(...)` →
  // `["T"]`). Empty for non-generic functions. Names bind to UnknownType
  // inside the function body via the same scope-injection pattern PKL-089
  // uses for class declarations; call-site inference is deferred.
  type_parameters : Array[String]
  // PKL-116: parallel list of optional bounds (same shape as ClassDecl).
  type_parameter_bounds : Array[String?]
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
  // PKL-115: optional list of type parameter names (`typealias Box<T> = ...` →
  // `["T"]`). Empty for non-generic aliases. The names introduce free type
  // variables in `target`; the typechecker substitutes them when an
  // instantiation site like `Box<Int>` is resolved.
  type_parameters : Array[String]
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
