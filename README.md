js2py
=====

A Javascript-to-Python transpiler. More of a translation assistant, really,
because you'll most likely need to make some changes by hand. But it's much
better than doing everything manually.

I thought it would be nice to be able to `import` some libraries directly into
Python, rather than shelling out to NodeJS. This script is the result of trying
to make that a reality.

I've successfully used it to port [Esprima][1] to Python -- the result is
[PyEsprima][2].

The generated code can be prettified a little using [PythonTidy][3].

Setup & Usage
-------------

    npm install
    ./js2py.coffee file.js > out.py

Transformations and Shims
-------------------------

* Create `global` declarations where necessary
* Transform simple prototype-based classes into corresponding Python classes
  (but no inheritance)
* Remove assignment statements from conditional tests
* Convert switch statements into if-else chains
* Convert pre-/post-increments into assignment statements
* `Array.prototype.slice` and `String.prototype.substr` are converted to
  Python's slice notation
* Function expressions are hoisted out as fully declared functions since
  Python's lambdas are limited
* Shims for RegExp and JS-style dictionaries
* Some support for `typeof`

Limitations
-----------

* No support for modifying non-global nonlocals (but easy enough to add with
  the `nonlocal` keyword in Python 3)
* `a[i]` in JS will return `undefined` if `i >= a.length`, but in Python it
  raises an `IndexError`.
* No support for `call` / `apply`.
* There are probably more; find out for yourself and file bugs!

[1]: https://github.com/ariya/esprima
[2]: https://github.com/int3/pyesprima
[3]: https://pypi.python.org/pypi/PythonTidy
