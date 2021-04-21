pqmarkup-lite in contrast to pqmarkup does not support the following features:
- Text color.
- Pictures/images.
- Tables.
- Ordered lists (unordered lists are partially supported: dot at the beginning of the line is replaced with bullet symbol [•]).
- `#‘code’` and `#(language)‘code’`.
- Horizontal rules.

Also blockquotes support is reduced:
```
>[http://ruscomp.24bb.ru/viewtopic.php?id=20][-1]:‘...’
```
is equivalent to
```
>[http://ruscomp.24bb.ru/viewtopic.php?id=20]:‘...’
```
and
```
>[-1]:‘...’ 
```
is equivalent to
```
>‘...’ 
```
