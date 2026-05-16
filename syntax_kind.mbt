///|
fn eof() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(0)
}

///|
fn error_kind() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(1)
}

///|
fn whitespace() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(2)
}

///|
fn newline() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(3)
}

///|
fn comment() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(4)
}

///|
fn identifier() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(10)
}

///|
fn int_token() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(11)
}

///|
fn float_token() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(126)
}

///|
fn string_token() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(12)
}

///|
fn let_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(20)
}

///|
fn true_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(21)
}

///|
fn false_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(22)
}

///|
fn null_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(23)
}

///|
fn module_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(24)
}

///|
fn new_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(25)
}

///|
fn import_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(26)
}

///|
fn as_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(27)
}

///|
fn local_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(28)
}

///|
fn if_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(29)
}

///|
fn eq() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(30)
}

///|
fn plus() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(31)
}

///|
fn minus() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(32)
}

///|
fn star() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(33)
}

///|
fn slash() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(34)
}

///|
fn else_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(35)
}

///|
fn is_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(36)
}

///|
fn when_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(37)
}

///|
fn for_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(38)
}

///|
fn in_kw() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(39)
}

///|
fn lparen() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(40)
}

///|
fn rparen() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(41)
}

///|
fn semicolon() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(42)
}

///|
fn lbrace() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(43)
}

///|
fn rbrace() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(44)
}

///|
fn dot() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(45)
}

///|
fn colon() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(46)
}

///|
fn lbracket() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(47)
}

///|
fn rbracket() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(48)
}

///|
fn comma() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(49)
}

///|
fn at_sign() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(50)
}

///|
fn question() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(51)
}

///|
fn bang() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(52)
}

///|
fn lt() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(53)
}

///|
fn gt() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(54)
}

///|
fn pipe() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(55)
}

///|
fn percent() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(56)
}

///|
fn equal_equal() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(57)
}

///|
fn not_equal() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(58)
}

///|
fn lte() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(59)
}

///|
fn gte() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(60)
}

///|
fn and_and() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(61)
}

///|
fn or_or() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(62)
}

///|
fn coalesce() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(63)
}

///|
fn arrow() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(64)
}

///|
fn qdot() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(65)
}

///|
fn non_null() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(66)
}

///|
fn pipe_forward() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(67)
}

///|
fn int_div() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(68)
}

///|
fn pow() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(69)
}

///|
fn module_node() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(100)
}

///|
fn module_decl() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(101)
}

///|
fn import_decl() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(102)
}

///|
fn let_decl() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(103)
}

///|
fn property_decl() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(104)
}

///|
fn binary_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(105)
}

///|
fn literal_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(106)
}

///|
fn name_ref() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(107)
}

///|
fn paren_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(108)
}

///|
fn object_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(109)
}

///|
fn object_member() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(110)
}

///|
fn member_access() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(111)
}

///|
fn import_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(112)
}

///|
fn unsupported_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(113)
}

///|
fn listing_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(114)
}

///|
fn mapping_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(115)
}

///|
fn mapping_entry() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(116)
}

///|
fn subscript_access() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(117)
}

///|
fn class_decl() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(118)
}

///|
fn function_decl() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(119)
}

///|
fn typealias_decl() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(120)
}

///|
fn call_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(121)
}

///|
fn lambda_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(122)
}

///|
fn unary_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(123)
}

///|
fn conditional_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(124)
}

///|
fn amend_expr() -> @cst.SyntaxKind {
  @cst.SyntaxKind::new(125)
}

///|
fn is_trivia(kind : @cst.SyntaxKind) -> Bool {
  match kind.raw() {
    2 | 3 | 4 => true
    _ => false
  }
}

///|
fn is_separator(kind : @cst.SyntaxKind) -> Bool {
  match kind.raw() {
    3 | 42 => true
    _ => false
  }
}

///|
fn kind_name(kind : @cst.SyntaxKind) -> String {
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
    38 => "for"
    39 => "in"
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
