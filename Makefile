TESTS = $(wildcard tests/*.js)
LIB_COFFEE = $(wildcard *.coffee)

test: $(TESTS:.js=.result) js2py.js

%.actual: %.py
	@python $? > $@

%.py: %.js js2py.js
	@node js2py $< > $@

%.expected: %.js
	@node $? > $@

%.result: %.actual %.expected
	@diff $?
	@echo "$@ passed"

js2py.js: js2py.coffee
	coffee -c $<

.SECONDARY:
