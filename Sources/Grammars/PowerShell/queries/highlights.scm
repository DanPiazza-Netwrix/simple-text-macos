"param" @keyword
"dynamicparam" @keyword
"begin" @keyword
"process" @keyword
"end" @keyword
"if" @keyword
"elseif" @keyword
"else" @keyword
"switch" @keyword
"foreach" @keyword
"for" @keyword
"while" @keyword
"do" @keyword
"until" @keyword
"function" @keyword
"filter" @keyword
"workflow" @keyword
"break" @keyword
"continue" @keyword
"throw" @keyword
"return" @keyword
"exit" @keyword
"trap" @keyword
"try" @keyword
"catch" @keyword
"finally" @keyword
"data" @keyword
"inlinescript" @keyword
"parallel" @keyword
"sequence" @keyword
"class" @keyword
"enum" @keyword
"hidden" @keyword
"static" @keyword
"in" @keyword

"-eq" @operator
"-ne" @operator
"-gt" @operator
"-ge" @operator
"-lt" @operator
"-le" @operator
"-like" @operator
"-notlike" @operator
"-match" @operator
"-notmatch" @operator
"-contains" @operator
"-notcontains" @operator
"-in" @operator
"-notin" @operator
"-replace" @operator
"-is" @operator
"-isnot" @operator
"-as" @operator
"-shl" @operator
"-shr" @operator
"-split" @operator
"-and" @operator
"-or" @operator
"-xor" @operator
"-band" @operator
"-bor" @operator
"-bxor" @operator
"+" @operator
"-" @operator
"/" @operator
"\\" @operator
"%" @operator
"*" @operator
".." @operator
"-not" @operator

";" @punctuation.delimiter

(string_literal) @string
(expandable_string_literal) @string
(verbatim_string_characters) @string

(integer_literal) @number
(real_literal) @number

(command (command_name) @function)

(function_statement (function_name) @function)

(command_invokation_operator) @operator

(type_spec) @type

(variable) @variable

(comment) @comment
