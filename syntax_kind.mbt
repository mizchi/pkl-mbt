///|
pub fn eof() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(0)
}

///|
pub fn error_kind() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(1)
}

///|
pub fn whitespace() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(2)
}

///|
pub fn newline() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(3)
}

///|
pub fn comment() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(4)
}

///|
pub fn identifier() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(10)
}

///|
pub fn int_token() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(11)
}

///|
pub fn string_token() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(12)
}

///|
pub fn let_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(20)
}

///|
pub fn true_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(21)
}

///|
pub fn false_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(22)
}

///|
pub fn null_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(23)
}

///|
pub fn module_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(24)
}

///|
pub fn new_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(25)
}

///|
pub fn import_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(26)
}

///|
pub fn as_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(27)
}

///|
pub fn local_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(28)
}

///|
pub fn if_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(29)
}

///|
pub fn eq() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(30)
}

///|
pub fn plus() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(31)
}

///|
pub fn minus() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(32)
}

///|
pub fn star() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(33)
}

///|
pub fn slash() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(34)
}

///|
pub fn else_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(35)
}

///|
pub fn is_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(36)
}

///|
pub fn when_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(37)
}

///|
pub fn lparen() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(40)
}

///|
pub fn rparen() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(41)
}

///|
pub fn semicolon() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(42)
}

///|
pub fn lbrace() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(43)
}

///|
pub fn rbrace() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(44)
}

///|
pub fn dot() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(45)
}

///|
pub fn colon() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(46)
}

///|
pub fn lbracket() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(47)
}

///|
pub fn rbracket() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(48)
}

///|
pub fn comma() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(49)
}

///|
pub fn at_sign() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(50)
}

///|
pub fn question() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(51)
}

///|
pub fn bang() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(52)
}

///|
pub fn lt() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(53)
}

///|
pub fn gt() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(54)
}

///|
pub fn pipe() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(55)
}

///|
pub fn percent() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(56)
}

///|
pub fn equal_equal() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(57)
}

///|
pub fn not_equal() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(58)
}

///|
pub fn lte() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(59)
}

///|
pub fn gte() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(60)
}

///|
pub fn and_and() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(61)
}

///|
pub fn or_or() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(62)
}

///|
pub fn coalesce() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(63)
}

///|
pub fn arrow() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(64)
}

///|
pub fn qdot() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(65)
}

///|
pub fn non_null() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(66)
}

///|
pub fn pipe_forward() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(67)
}

///|
pub fn int_div() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(68)
}

///|
pub fn pow() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(69)
}

///|
pub fn module_node() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(100)
}

///|
pub fn module_decl() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(101)
}

///|
pub fn import_decl() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(102)
}

///|
pub fn let_decl() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(103)
}

///|
pub fn property_decl() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(104)
}

///|
pub fn binary_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(105)
}

///|
pub fn literal_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(106)
}

///|
pub fn name_ref() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(107)
}

///|
pub fn paren_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(108)
}

///|
pub fn object_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(109)
}

///|
pub fn object_member() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(110)
}

///|
pub fn member_access() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(111)
}

///|
pub fn import_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(112)
}

///|
pub fn unsupported_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(113)
}

///|
pub fn listing_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(114)
}

///|
pub fn mapping_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(115)
}

///|
pub fn mapping_entry() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(116)
}

///|
pub fn subscript_access() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(117)
}

///|
pub fn class_decl() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(118)
}

///|
pub fn function_decl() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(119)
}

///|
pub fn typealias_decl() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(120)
}

///|
pub fn call_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(121)
}

///|
pub fn lambda_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(122)
}

///|
pub fn unary_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(123)
}

///|
pub fn conditional_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(124)
}

///|
pub fn amend_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(125)
}

///|
pub fn is_trivia(kind : @cst.SyntaxKind) -> Bool {
  match kind.raw() {
    2 | 3 | 4 => true
    _ => false
  }
}

///|
pub fn is_separator(kind : @cst.SyntaxKind) -> Bool {
  match kind.raw() {
    3 | 42 => true
    _ => false
  }
}

///|
pub fn kind_name(kind : @cst.SyntaxKind) -> String {
  match kind.raw() {
    0 => "eof"
    1 => "error"
    2 => "whitespace"
    3 => "newline"
    4 => "comment"
    10 => "identifier"
    11 => "int"
    12 => "string"
    20 => "let"
    21 => "true"
    22 => "false"
    23 => "null"
    24 => "module"
    25 => "new"
    26 => "import"
    27 => "as"
    28 => "local"
    29 => "if"
    30 => "eq"
    31 => "plus"
    32 => "minus"
    33 => "star"
    34 => "slash"
    35 => "else"
    36 => "is"
    37 => "when"
    40 => "lparen"
    41 => "rparen"
    42 => "semicolon"
    43 => "lbrace"
    44 => "rbrace"
    45 => "dot"
    46 => "colon"
    47 => "lbracket"
    48 => "rbracket"
    49 => "comma"
    50 => "at"
    51 => "question"
    52 => "bang"
    53 => "lt"
    54 => "gt"
    55 => "pipe"
    56 => "percent"
    57 => "equal_equal"
    58 => "not_equal"
    59 => "lte"
    60 => "gte"
    61 => "and_and"
    62 => "or_or"
    63 => "coalesce"
    64 => "arrow"
    65 => "qdot"
    66 => "non_null"
    67 => "pipe_forward"
    68 => "int_div"
    69 => "pow"
    100 => "module"
    101 => "module_decl"
    102 => "import_decl"
    103 => "let_decl"
    104 => "property_decl"
    105 => "binary_expr"
    106 => "literal_expr"
    107 => "name_ref"
    108 => "paren_expr"
    109 => "object_expr"
    110 => "object_member"
    111 => "member_access"
    112 => "import_expr"
    113 => "unsupported_expr"
    114 => "listing_expr"
    115 => "mapping_expr"
    116 => "mapping_entry"
    117 => "subscript_access"
    118 => "class_decl"
    119 => "function_decl"
    120 => "typealias_decl"
    121 => "call_expr"
    122 => "lambda_expr"
    123 => "unary_expr"
    124 => "conditional_expr"
    125 => "amend_expr"
    _ => "unknown"
  }
}
