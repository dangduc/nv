; Authored for nvALT and the pinned tree-sitter-org grammar. No predicates.
(headline (stars) @punctuation.special (item) @text.title)
(tag) @attribute
(directive name: (expr) @keyword)
(property name: (expr) @attribute (value) @string)
(comment) @comment
(bullet) @punctuation.special
(checkbox) @constant
(timestamp) @string.special
(hr) @punctuation.special
(cell) @text.literal
(block name: (expr) @keyword contents: (contents) @text.literal end_name: (expr) @keyword)
(dynamic_block name: (expr) @keyword contents: (contents) @text.literal)
(drawer name: (expr) @keyword)
(link) @text.uri
(link_desc) @text.uri
(priority) @constant
(inline_code_block) @text.literal
