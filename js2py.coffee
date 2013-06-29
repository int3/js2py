#! /usr/bin/env coffee

esprima = require 'esprima'
estraverse = require 'estraverse'
match = require 'pattern-match'

class LinePrinter
  constructor: ->
    @indent = 0
    @lines = []

  addLine: (content) ->
    @lines.push [@indent, content]
    return

  print: ->
    for line in @lines
      [indent, content] = line
      for i in [0...indent]
        process.stdout.write '    '
      process.stdout.write content + '\n'

estraverse.Syntax.PySlice = 'PySlice'
estraverse.Syntax.PyClass = 'PyClass'
estraverse.VisitorKeys.PySlice = ['arguments']
estraverse.VisitorKeys.PyClass = ['methods']

extractSideEffects = (c) ->
  statements = []
  expr = estraverse.replace c,
    enter: (c, parent) ->
      switch c.type
        when 'AssignmentExpression'
          statements.push c
          return c.left
  return { expr, statements }

transform = (c) ->
  root = c
  RESERVED_IDENTS = [ 'len', 'print', 'list', 'assert' ]

  classes = {}

  # Pattern match for classes, and create PyClass nodes
  estraverse.replace c,
    enter: (c, parent) ->
      switch c.type
        when 'FunctionDeclaration'
          if c.id and /[A-Z]/.test c.id.name[0]
            cls =  {
              type: 'PyClass'
              id: { type: 'Identifier', name: c.id.name }
              methods: [ c ]
            }
            classes[cls.id.name] = cls
            c.id.name = '__init__'
            c.params.unshift({ type: 'Identifier', name: 'self' })
            return cls
        when 'AssignmentExpression'
          if c.left.type is 'MemberExpression' and c.left.property.name is 'prototype'
            clsName = c.left.object.name
            if clsName not of classes
              throw new Error "Could not find class #{clsName}"
            c.right.class = classes[clsName]
            return
        when 'Property'
          if parent.class and c.value.type is 'FunctionExpression'
            parent.class.methods.push c.value
            c.value.type = 'FunctionDeclaration'
            c.value.params.unshift { type: 'Identifier', name: 'self' }
            c.value.id = c.key
          return

    leave: (c, parent) ->
      switch c.type
        when 'AssignmentExpression'
          if c.right.class
            return null

  currentFunction = null
  visibleFunctions = null
  tempNameCount = 0
  getTempName = -> "__temp__#{tempNameCount++}"
  tryGetType = (c) ->
    if not c then return true
    if c.type is 'Literal'
      return typeof c.value
    else if c.type is 'ObjectExpression'
      return 'object'
    return true

  # Find functions that modify globals, because Python needs 'global varname'.
  # Also hoist out function expressions, because Python's lambdas do not support statements.
  estraverse.replace c,
    enter: (c, parent) ->
      switch c.type
        when 'Program'
          currentFunction = c
          currentFunction.vars = {}
          currentFunction.globalVars = {}
          visibleFunctions = [ currentFunction ]
        when 'FunctionDeclaration', 'FunctionExpression'
          currentFunction = c
          visibleFunctions.push currentFunction
          currentFunction.vars = {}
          for param in c.params
            currentFunction.vars[param.name] = true
          currentFunction.globalVars = {}
        when 'VariableDeclarator'
          currentFunction.vars[c.id.name] = tryGetType c.init
      return
    leave: (c, parent) ->
      switch c.type
        when 'Program', 'FunctionDeclaration', 'FunctionExpression'
          visibleFunctions.pop()
          currentFunction = visibleFunctions[visibleFunctions.length - 1]
          if c.type is 'FunctionExpression'
            c.type = 'FunctionDeclaration'
            c.id = { type: 'Identifier', name: getTempName() }
            leavelist = this.__leavelist
            if leavelist[leavelist.length - 2].node.type is 'ObjectExpression' and # TODO handle assignment
               leavelist[leavelist.length - 3].node.type is 'AssignmentExpression'
              c.hoistedName = leavelist[leavelist.length-3].node.left
            body = currentFunction.body
            if body.body? then body = body.body
            body.unshift c
            return c.id

  estraverse.replace c,
    enter: (c, parent) ->
      switch c.type
        when 'Program', 'FunctionDeclaration'
          currentFunction = c
          visibleFunctions.push c
          return
        when 'ThisExpression'
          if currentFunction.hoistedName
            return currentFunction.hoistedName
        when 'Identifier'
          if RESERVED_IDENTS.indexOf(c.name) >= 0 and not c.generated
            c.name += '__py__'
          else if c.name is 'Error'
            c.name = 'RuntimeError'
          else if c.name is 'String'
            c.name = 'str' # TODO make more precise
          c
        when 'CallExpression'
          c = match c, ((when_) ->
            when_({
              callee: {
                property: { type: 'Identifier', name: 'slice' }
              }
            }, (-> {
              type: 'PySlice'
              callee: c.callee.object
              arguments: c.arguments
            }), @)
            when_({
              callee: {
                property: { type: 'Identifier', name: 'substr' }
              }
            }, (-> {
              type: 'PySlice'
              callee: c.callee.object
              arguments: [c.arguments[0], {
                type: 'BinaryExpression'
                operator: '+'
                left: c.arguments[0]
                right: c.arguments[1]
              }]
            }), @)
            when_({
              callee: {
                property: { type: 'Identifier', name: 'charCodeAt' }
              }
            }, (-> {
              type: 'ConditionalExpression'
              test: {
                type: 'BinaryExpression', operator: '<',
                left: c.arguments[0], right: {
                  type: 'CallExpression',
                  callee: { type: 'Identifier', name: 'len', generated: true }
                  arguments: [c.callee.object]
                }
              }
              consequent: {
                type: 'CallExpression'
                callee: { type: 'Identifier', name: 'ord' }
                arguments: [{
                  type: 'MemberExpression'
                  object: c.callee.object
                  property: c.arguments[0]
                  computed: true
                }]
              }
              alternate: { type: 'Identifier', name: 'None' }
            }), @)
            when_({
              callee: {
                property: { type: 'Identifier', name: 'push' }
              }
            }, (->
              c.callee.property.name = 'append'
              c
            ), @)
            when_({
              callee: {
                object: { type: 'Identifier', name: 'push' }
              }
            }, (->
              c.callee.property.name = 'append'
              c
            ), @)
            when_({
              callee: {
                object: { type: 'ArrayExpression' }
                property: { type: 'Identifier', name: 'indexOf' }
              }
            }, (-> {
              type: 'CallExpression'
              callee: { type: 'Identifier', name: 'list_indexOf' }
              arguments: [c.callee.object, c.arguments[0]]
            }), @)
            when_({
              callee: {
                object: {
                  object: {
                      object: { type: 'Identifier', name: 'Object' }
                      property: { type: 'Identifier', name: 'prototype' }
                    }
                  property: { type: 'Identifier', name: 'hasOwnProperty' }
                }
                property: { type: 'Identifier', name: 'call' }
              }
            }, (-> {
              type: 'BinaryExpression'
              operator: 'in'
              left: c.arguments[1]
              right: c.arguments[0]
            }), @)
            when_(match.any, (-> c), @))
          return c
        when 'MemberExpression'
          match c, ((when_) ->
            when_({
              property: {
                type: 'Identifier', name: 'length'
              }
            }, (-> {
              type: 'CallExpression'
              callee: { type: 'Identifier', name: 'len', generated: true }
              arguments: [c.object]
              generated: true
            }), @)
            when_({
              object: { type: 'Identifier', name: 'String' }
              property: { type: 'Identifier', name: 'fromCharCode' }
            }, (-> {
              type: 'Identifier', name: 'unichr'
            }), @)
            when_({
              object: { type: 'Literal', value: match.string }
              property: { type: 'Identifier', name: 'indexOf' }
            }, (-> {
              type: c.type
              object: c.object
              property: { type: 'Identifier', name: 'find' }
            }), @)
            when_({
              property: { type: 'Identifier', name: 'toLowerCase' }
            }, (-> {
              type: c.type
              object: c.object
              property: { type: 'Identifier', name: 'lower' }
            }), @)
            when_(match.any, (->), @))

    leave: (c, parent) ->
      switch c.type
        when 'Program'
          visibleFunctions.pop()
          currentFunction = visibleFunctions[visibleFunctions.length - 1]
          return
        when 'FunctionDeclaration'
          visibleFunctions.pop()
          currentFunction = visibleFunctions[visibleFunctions.length - 1]
          return
        when 'UpdateExpression'
          if c.argument.type is 'Identifier' and c.argument.name not of currentFunction.vars
            currentFunction.globalVars[c.argument.name] = 'number'
          return
        when 'AssignmentExpression'
          if c.left.type is 'Identifier'
            if c.left.name not of currentFunction.vars
              currentFunction.globalVars[c.left.name] = tryGetType c.right
            else
              currentFunction.vars[c.left.name] = tryGetType c.right
            return
          if c.left.type is 'MemberExpression' and c.left.property.name is 'prototype'
            return null
        when 'ForStatement'
          body = ensure_block c.body
          body.body.unshift {
            type: 'IfStatement'
            test: {
              type: 'UnaryExpression', operator: '!', prefix: true, argument: c.test
            }
            consequent: { type: 'BreakStatement' }
          }
          body.body.push c.update
          {
            type: 'WhileStatement'
            test: { type: 'Literal', value: 1 }
            body: body
            prelude: [c.init]
          }
        when 'DoWhileStatement'
          body = ensure_block c.body
          body.body.push {
            type: 'IfStatement'
            test: {
              type: 'UnaryExpression', operator: '!', prefix: true, argument: c.test
            }
            consequent: { type: 'BreakStatement' }
          }
          {
            type: 'WhileStatement'
            test: { type: 'Literal', value: 1 }
            body: body
          }
        when 'WhileStatement'
          c.body = ensure_block c.body
          {expr, statements} = extractSideEffects c.test
          Array::push.apply c.body.body, statements
          c.test = expr
          c.prelude ?= []
          Array::push.apply c.prelude, statements
          return
        when 'SwitchStatement'
          body = []
          firstClause = currentClause = {
            alternate: null
          }
          caseGroup = []
          for cas in c.cases when cas.test
            caseGroup.push cas.test
            if cas.consequent.length == 0
              continue
            currentClause.alternate = {
              type: 'IfStatement'
              test: caseGroup.map((test) -> {
                type: 'BinaryExpression'
                operator: '==='
                left: c.discriminant
                right: test
              }).reduce(((all_cases, cas) ->
                if all_cases is null
                  return cas
                {
                  type: 'BinaryExpression'
                  operator: '||'
                  left: cas
                  right: all_cases
                }
              ), null)
              consequent: {
                type: 'BlockStatement'
                body: cas.consequent
              }
              alternate: null
            }
            currentClause = currentClause.alternate
            caseGroup = []
          lastCase = c.cases[c.cases.length-1]
          if lastCase.test is null
            currentClause.alternate = {
              type: 'BlockStatement'
              body: lastCase.consequent
            }
          body = [
            firstClause.alternate,
            { type: 'BreakStatement', label: null }
          ]
          {
            type: 'WhileStatement'
            test: { type: 'Literal', value: 1 }
            body: { type: 'BlockStatement', body: body }
          }
        when 'BinaryExpression'
          if c.operator is 'instanceof'
            if c.right.type is 'Identifier' and c.right.name is 'String'
              right = { type: 'Identifier', name: 'str' }
            else
              right = c.right
            {
              type: 'CallExpression'
              callee: { type: 'Identifier', name: 'isinstance' }
              arguments: [c.left, right]
            }
  c

ensure_block = (c) ->
  if c.type isnt 'BlockStatement'
    return {
      type: 'BlockStatement'
      body: [c]
    }
  return c

generate = (c) ->
  p = new LinePrinter
  isElse = false

  walk = (c) ->
    return if c is null
    switch c.type
      when 'Program'
        for s in c.body
          walk s
      when 'BlockStatement'
        p.indent++
        for s in c.body
          walk s
        p.indent--
      when 'PyClass'
        p.addLine "class #{c.id.name}(object):"
        p.indent++
        for m in c.methods
          walk m
        p.indent--
      when 'FunctionDeclaration'
        p.addLine "def #{c.id.name}(#{c.params.map((p) -> (walk p) + '=None').join ', '}):"
        p.indent++
        for k, v of c.globalVars
          p.addLine "global #{k}"
        p.indent--
        walk c.body
        p.addLine ''
      when 'IfStatement'
        p.addLine "#{if c.isElse then 'el' else ''}if #{walk c.test}:"
        walk ensure_block c.consequent
        if c.alternate
          if c.alternate.type is 'IfStatement'
            c.alternate.isElse = true
            alternate = c.alternate
          else
            p.addLine "else:"
            alternate = ensure_block c.alternate
          walk alternate
      when 'WhileStatement'
        if c.prelude
          c.prelude.map(walk)
        p.addLine "while (#{walk c.test}):"
        walk c.body
      when 'VariableDeclaration'
        for d in c.declarations
          walk d
      when 'VariableDeclarator'
        if c.init isnt null then p.addLine "#{walk c.id} = #{walk c.init}"
        else p.addLine "#{walk c.id} = None"
      when 'AssignmentExpression'
        left = walk c.left
        p.addLine "#{left} #{c.operator} #{walk c.right}"
        left
      when 'BreakStatement'
        p.addLine 'break'
      when 'ReturnStatement'
        p.addLine "return #{if c.argument isnt null then walk c.argument else ''}"
      when 'ExpressionStatement'
        ex = walk c.expression
        if ex then p.addLine "#{ex}"
      when 'CallExpression', 'NewExpression'
        "#{walk c.callee}(#{c.arguments.map(walk).join ', '})"
      when 'ThrowStatement'
        p.addLine "raise #{walk c.argument}"
      when 'TryStatement'
        p.addLine "try:"
        walk c.block
        walk c.handlers[0]
        if c.finalizer
          p.addLine "finally:"
          walk c.finalizer
      when 'CatchClause'
        p.addLine "except Exception as #{walk c.param}:"
        walk c.body
      when 'PySlice'
        "#{walk c.callee}[(#{walk c.arguments[0]}):(#{walk c.arguments[1]})]"
      when 'ConditionalExpression'
        "#{walk c.consequent} if #{walk c.test} else #{walk c.alternate}"
      when 'MemberExpression'
        if c.computed
          "#{walk c.object}[#{walk c.property}]"
        else
          "#{walk c.object}.#{walk c.property}"
      when 'UpdateExpression'
        # XXX dangerous
        v = walk c.argument
        p.addLine "#{v} #{c.operator[0]}= 1"
        if c.prefix
          v
        else
          "#{v} #{if c.operator[0] is '+' then '-' else '+'} 1"
      when 'BinaryExpression', 'LogicalExpression'
        op = switch c.operator
          when '||' then 'or'
          when '&&' then 'and'
          when '===' then '=='
          when '!==' then '!='
          when '==', '!=' then throw new Error('Unsupported')
          else c.operator
        "(#{walk c.left}) #{op} (#{walk c.right})"
      when 'UnaryExpression'
        if c.operator is '!'
          "not (#{walk c.argument})"
        else if c.operator is 'delete'
          "del (#{walk c.argument})"
        else if c.operator is '-'
          "-(#{walk c.argument})"
        else if c.operator is 'typeof'
          v = walk c.argument
          if c.argument.type is 'Identifier'
            precheck = "'#{v}' in locals()"
          else if c.argument.type is 'MemberExpression' and \
             typeof c.argument.property.value != 'number'
            precheck = "('#{walk c.argument.property}' in #{walk c.argument.object})"
          if precheck
            "'undefined' if not #{precheck} else typeof(#{v})"
          else
            "typeof(#{v})"
        else
          throw 'NYI: ' + c.operator
      when 'ThisExpression'
        return 'self'
      when 'Identifier'
        return c.name
      when 'ArrayExpression'
        "[#{c.elements.map(walk).join ', '}]"
      when 'ObjectExpression'
        rv = 'jsdict({'
        for prop in c.properties
          rv += "\"#{prop.key.name ? prop.key.value}\": (#{walk prop.value}), "
        rv += '})'
      when 'Literal'
        if c.value is null
          'None'
        else if typeof c.value == 'string'
          v = c.value
          out = ''
          hasUniEscape = false
          for i in [0...v.length]
            ch = v.charCodeAt i
            if ch > 256
              uni = ch.toString 16
              out += '\\u' + ('0' for i in [0...4 - uni.length]).join('') + uni
              hasUniEscape = true
            else if ch < 32 or ch > 126
              hex = ch.toString 16
              out += '\\x' + ('0' for i in [0...2 - hex.length]).join('') + hex
              hasUniEscape = true
            else if v[i] is '\\' or v[i] is '"'
              out += '\\' + v[i]
            else
              out += v[i]
          "#{if hasUniEscape then 'u' else ''}\"#{out}\""
        else if typeof c.value is 'boolean'
          stringRep = c.value + ''
          stringRep.charAt(0).toUpperCase() + stringRep.slice(1)
        else if c.value instanceof RegExp
          "RegExp(r'#{c.value.source}')"
        else
          c.value
      else
        console.log JSON.stringify c
        throw "NYI: #{c.type} at #{c.loc.start.line}"

  walk transform c
  path = require 'path'
  console.log(fs.readFileSync(path.join(__dirname, 'prelude.py'), 'utf-8'))
  p.print()

if require.main == module
  fs = require 'fs'
  generate(esprima.parse (fs.readFileSync process.argv[2]))
