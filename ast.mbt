///|
pub(all) struct Diagnostic {
  message : String
  // PKL-107: optional source position. `start` / `end` are absolute
  // byte offsets into the originating source; -1 means "unknown"
  // (synthetic diagnostic, post-eval rewrite, or a site that hasn't
  // been wired through yet). The CLI projects `start` onto a
  // `line:column` pair by walking the source.
  start : Int
  end : Int
} derive(Eq, Debug)

///|
/// Helper for the common path: a diagnostic with no recorded position.
/// Sites that have a CST node in hand should construct
/// `Diagnostic::{ message, start, end }` directly instead.
fn diag(message : String) -> Diagnostic {
  { message, start: -1, end: -1 }
}

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
  IntLiteral(Int64)
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
  // PKL-128: string interpolation. The parser splits a `"... \(expr) ..."`
  // literal into alternating literal segments and embedded expressions;
  // the evaluator concatenates each part's rendered string form into the
  // final value. An interpolated string with zero `\(...)` segments
  // collapses back to a plain `StringLiteral` at parse time so the hot
  // path stays untouched.
  InterpolatedString(Array[Expr])
  // PKL-103: Apple Pkl's `f?(...)` null-safe call form. Today only
  // `read?(uri)` is wired (returns `null` instead of a diagnostic when
  // the URI resolves to nothing); the AST node generalises so future
  // null-safe intrinsics can reuse the dispatch.
  NullSafeCallExpr(Expr, Array[Expr])
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
  // PKL-140: True when the property was declared without a default
  // (`foo: Int?` / `external minInt: Int`). The evaluator skips
  // these — Apple Pkl's stdlib uses the form for host-bound slots
  // and abstract templates whose subclasses fill in the value.
  abstract_slot : Bool
} derive(Eq, Debug)

///|
pub(all) enum Declaration {
  ClassDeclaration(ClassDecl)
  FunctionDeclaration(FunctionDecl)
  TypeAliasDeclaration(TypeAliasDecl)
} derive(Eq, Debug)

///|
/// PKL-128d: structured capture of a single annotation that precedes
/// a declaration. `class_name` holds the identifier after `@` (e.g.
/// `"Deprecated"`, `"ModuleInfo"`, `"my.pkg.Custom"`). `body_text`
/// is the verbatim source between the surrounding delimiters; the
/// `body_kind` field identifies which delimiters were used so a
/// downstream tool (pkldoc / codegen) can re-parse the body in the
/// matching mode without scanning back to the open token.
///
/// Forms recognised:
///   - `@Name`                    → body_kind = NoBody,    body_text = ""
///   - `@Name(arg, ...)`          → body_kind = ParenBody, body_text = inside parens
///   - `@Name { field = expr }`   → body_kind = BraceBody, body_text = inside braces
///
/// Capturing only the raw text keeps the slice tight: the
/// downstream consumer can lex/parse the body when needed, and the
/// AST avoids carrying a second Expr-tree shape for arguments that
/// the evaluator never sees.
pub(all) struct Annotation {
  class_name : String
  body_kind : AnnotationBodyKind
  body_text : String
} derive(Eq, Debug)

///|
pub(all) enum AnnotationBodyKind {
  NoBody
  ParenBody
  BraceBody
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
  // PKL-128d: annotations attached to this `class` declaration in
  // source order. Empty when no annotation precedes the keyword.
  annotations : Array[Annotation]
  // PKL-117: true when `abstract` preceded the `class` keyword. The
  // class itself cannot be instantiated and may host abstract methods
  // that concrete subclasses must override.
  is_abstract : Bool
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
  // PKL-128d: annotations attached to this `function` declaration in
  // source order. Empty when no annotation precedes the keyword.
  annotations : Array[Annotation]
  // PKL-117: true when `abstract` preceded the `function` keyword. An
  // abstract method has no body (`body = None`); the modifier is the
  // explicit marker, since a body-less function inside an abstract
  // class declaration would otherwise be ambiguous with a partial
  // declaration the parser had failed to consume.
  is_abstract : Bool
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
  // PKL-128d: annotations attached to this `typealias` declaration in
  // source order. Empty when no annotation precedes the keyword.
  annotations : Array[Annotation]
} derive(Eq, Debug)

///|
pub(all) struct Program {
  module_name : String?
  module_relation : ModuleRelation?
  imports : Array[ImportDecl]
  declarations : Array[Declaration]
  bindings : Array[Binding]
  body : Expr?
  // PKL-128d: annotations attached to the `module` declaration in
  // source order. Empty when no annotation precedes the keyword (or
  // no explicit `module` header is present at all).
  module_annotations : Array[Annotation]
} derive(Eq, Debug)

///|
pub(all) struct ParseResult {
  root : @cst.SyntaxNode
  program : Program
  diagnostics : Array[Diagnostic]
  unsupported_syntax : Array[UnsupportedSyntax]
} derive(Eq)
