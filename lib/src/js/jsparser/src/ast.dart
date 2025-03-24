// ignore_for_file: avoid_renaming_method_parameters

library;

part 'ast_visitor.dart';

// AST structure mostly designed after the Mozilla Parser API:
//  https://developer.mozilla.org/en-US/docs/Mozilla/Projects/SpiderMonkey/Parser_API

/// A node in the abstract syntax tree of a JavaScript program.
abstract class Node {
  /// The parent of this node, or null if this is the [Program] node.
  ///
  /// If you transform the AST in any way, it is your own responsibility to update parent pointers accordingly.
  Node? parent;

  /// Source-code offset.
  int? start, end;

  /// 1-based line number.
  int? line;

  /// Retrieves the filename from the enclosing [Program]. Returns null if the node is orphaned.
  String? get filename {
    Program? program = enclosingProgram;
    if (program != null) return program.filename;
    return null;
  }

  /// A string with filename and line number.
  String get location => "$filename:$line";

  /// Returns the [Program] node enclosing this node, possibly the node itself, or null if not enclosed in any program.
  Program? get enclosingProgram {
    Node? node = this;
    while (node != null) {
      if (node is Program) return node;
      node = node.parent;
    }
    return null;
  }

  /// Returns the [FunctionNode] enclosing this node, possibly the node itself, or null if not enclosed in any function.
  FunctionNode? get enclosingFunction {
    Node? node = this;
    while (node != null) {
      if (node is FunctionNode) return node;
      node = node.parent;
    }
    return null;
  }

  /// Visits the immediate children of this node.
  void forEach(void Function(Node node) callback);

  /// Calls the relevant `visit` method on the visitor.
  T visitBy<T>(Visitor<T> visitor);

  /// Calls the relevant `visit` method on the visitor.
  T visitBy1<T, A>(Visitor1<T, A> visitor, A arg);
}

/// Superclass for [Program], [FunctionNode], and [CatchClause], which are the three types of node that
/// can host local variables.
abstract class Scope extends Node {
  /// Variables declared in this scope, including the implicitly declared "arguments" variable.
  Set<String?>? environment;
}

/// A collection of [Program] nodes.
///
/// This node is not generated by the parser, but is a convenient way to cluster multiple ASTs into a single AST,
/// should you wish to do so.
class Programs extends Node {
  List<Program> programs = <Program>[];

  Programs(this.programs);

  @override
  void forEach(callback) => programs.forEach(callback);

  @override
  String toString() => 'Programs';

  @override
  visitBy<T>(Visitor<T> v) => v.visitPrograms(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitPrograms(this, arg);
}

/// The root node of a JavaScript AST, representing the top-level scope.
class Program extends Scope {
  /// Indicates where the program was parsed from.
  /// In principle, this can be anything, it is just a string passed to the parser for convenience.
  @override
  String? filename;

  List<Statement> body;

  Program(this.body);

  @override
  void forEach(callback) => body.forEach(callback);

  @override
  String toString() => 'Program';

  @override
  visitBy<T>(Visitor<T> v) => v.visitProgram(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitProgram(this, arg);
}

/// A function, which may occur as a function expression, function declaration, or property accessor in an object literal.
class FunctionNode extends Scope {
  Name? name;
  List<Name> params;
  Statement body;

  FunctionNode(this.name, this.params, this.body);

  bool get isExpression => parent is FunctionExpression;

  bool get isDeclaration => parent is FunctionDeclaration;

  bool get isAccessor => parent is Property && (parent as Property).isAccessor;

  @override
  forEach(callback) {
    if (name != null) callback(name!);
    params.forEach(callback);
    callback(body);
  }

  @override
  String toString() => 'FunctionNode';

  @override
  visitBy<T>(Visitor<T> v) => v.visitFunctionNode(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitFunctionNode(this, arg);
}

class ArrowFunctionNode extends Scope {
  final List<Name> params;
  final Statement body;

  ArrowFunctionNode(this.params, this.body);

  bool get isExpression => true; // Arrow functions are always expressions
  bool get isDeclaration => false; // Arrow functions are not declarations
  bool get isAccessor => false; // Arrow functions are not accessors

  @override
  forEach(callback) {
    params.forEach(callback);
    callback(body);
  }

  @override
  String toString() => 'ArrowFunctionNode';

  @override
  visitBy<T>(Visitor<T> v) => v.visitArrowFunctionNode(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) =>
      v.visitArrowFunctionNode(this, arg);
}

/// Mention of a variable, property, or label.
class Name extends Node {
  /// Name being referenced.
  ///
  /// Unicode values have been resolved.
  String value;

  /// Link to the enclosing [FunctionExpression], [Program], or [CatchClause] where this variable is declared
  /// (defaults to [Program] if undeclared), or `null` if this is not a variable.
  Scope? scope;

  /// True if this refers to a variable name.
  bool get isVariable =>
      parent is NameExpression ||
      parent is FunctionNode ||
      parent is VariableDeclarator ||
      parent is CatchClause;

  /// True if this refers to a property name.
  bool get isProperty =>
      (parent is MemberExpression &&
          (parent as MemberExpression).property == this) ||
      (parent is Property && (parent as Property).key == this);

  /// True if this refers to a label name.
  bool get isLabel =>
      parent is BreakStatement ||
      parent is ContinueStatement ||
      parent is LabeledStatement;

  Name(this.value);

  @override
  void forEach(callback) {}

  @override
  String toString() => value;

  @override
  visitBy<T>(Visitor<T> v) => v.visitName(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitName(this, arg);
}

/// Superclass for all nodes that are statements.
abstract class Statement extends Node {}

/// Statement of form: `;`
class EmptyStatement extends Statement {
  @override
  void forEach(callback) {}

  @override
  String toString() => 'EmptyStatement';

  @override
  visitBy<T>(Visitor<T> v) => v.visitEmptyStatement(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitEmptyStatement(this, arg);
}

/// Statement of form: `{ [body] }`
class BlockStatement extends Statement {
  List<Statement> body;

  BlockStatement(this.body);

  @override
  void forEach(callback) => body.forEach(callback);

  @override
  String toString() => 'BlockStatement';

  @override
  visitBy<T>(Visitor<T> v) => v.visitBlock(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitBlock(this, arg);
}

/// Statement of form: `[expression];`
class ExpressionStatement extends Statement {
  Expression expression;

  ExpressionStatement(this.expression);

  @override
  forEach(callback) => callback(expression);

  @override
  String toString() => 'ExpressionStatement';

  @override
  visitBy<T>(Visitor<T> v) => v.visitExpressionStatement(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) =>
      v.visitExpressionStatement(this, arg);
}

/// Statement of form: `if ([condition]) then [then] else [otherwise]`.
class IfStatement extends Statement {
  Expression condition;
  Statement then;
  Statement? otherwise; // May be null.

  IfStatement(this.condition, this.then, [this.otherwise]);

  @override
  forEach(callback) {
    callback(condition);
    callback(then);
    if (otherwise != null) callback(otherwise!);
  }

  @override
  String toString() => 'IfStatement';

  @override
  visitBy<T>(Visitor<T> v) => v.visitIf(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitIf(this, arg);
}

/// Statement of form: `[label]: [body]`
class LabeledStatement extends Statement {
  Name label;
  Statement body;

  LabeledStatement(this.label, this.body);

  @override
  forEach(callback) {
    callback(label);
    callback(body);
  }

  @override
  String toString() => 'LabeledStatement';

  @override
  visitBy<T>(Visitor<T> v) => v.visitLabeledStatement(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitLabeledStatement(this, arg);
}

/// Statement of form: `break;` or `break [label];`
class BreakStatement extends Statement {
  Name? label; // May be null.

  BreakStatement(this.label);

  @override
  forEach(callback) {
    if (label != null) callback(label!);
  }

  @override
  String toString() => 'BreakStatement';

  @override
  visitBy<T>(Visitor<T> v) => v.visitBreak(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitBreak(this, arg);
}

/// Statement of form: `continue;` or `continue [label];`
class ContinueStatement extends Statement {
  Name? label; // May be null.

  ContinueStatement(this.label);

  @override
  forEach(callback) {
    if (label != null) callback(label!);
  }

  @override
  String toString() => 'ContinueStatement';

  @override
  visitBy<T>(Visitor<T> v) => v.visitContinue(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitContinue(this, arg);
}

/// Statement of form: `with ([object]) { [body] }`
class WithStatement extends Statement {
  Expression object;
  Statement body;

  WithStatement(this.object, this.body);

  @override
  forEach(callback) {
    callback(object);
    callback(body);
  }

  @override
  String toString() => 'WithStatement';

  @override
  visitBy<T>(Visitor<T> v) => v.visitWith(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitWith(this, arg);
}

/// Statement of form: `switch ([argument]) { [cases] }`
class SwitchStatement extends Statement {
  Expression argument;
  List<SwitchCase> cases;

  SwitchStatement(this.argument, this.cases);

  @override
  forEach(callback) {
    callback(argument);
    cases.forEach(callback);
  }

  @override
  String toString() => 'SwitchStatement';

  @override
  visitBy<T>(Visitor<T> v) => v.visitSwitch(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitSwitch(this, arg);
}

/// Clause in a switch: `case [expression]: [body]` or `default: [body]` if [expression] is null.
class SwitchCase extends Node {
  Expression? expression; // May be null (for default clause)
  List<Statement> body;

  SwitchCase(this.expression, this.body);

  SwitchCase.defaultCase(this.body);

  /// True if this is a default clause, and not a case clause.
  bool get isDefault => expression == null;

  @override
  forEach(callback) {
    if (expression != null) callback(expression!);
    body.forEach(callback);
  }

  @override
  String toString() => 'SwitchCase';

  @override
  visitBy<T>(Visitor<T> v) => v.visitSwitchCase(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitSwitchCase(this, arg);
}

/// Statement of form: `return [argument];` or `return;`
class ReturnStatement extends Statement {
  Expression? argument;

  ReturnStatement(this.argument);

  @override
  forEach(callback) => argument != null ? callback(argument!) : null;

  @override
  String toString() => 'ReturnStatement';

  @override
  visitBy<T>(Visitor<T> v) => v.visitReturn(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitReturn(this, arg);
}

/// Statement of form: `throw [argument];`
class ThrowStatement extends Statement {
  Expression argument;

  ThrowStatement(this.argument);

  @override
  forEach(callback) => callback(argument);

  @override
  String toString() => 'ThrowStatement';

  @override
  visitBy<T>(Visitor<T> v) => v.visitThrow(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitThrow(this, arg);
}

/// Statement of form: `try [block] catch [handler] finally [finalizer]`.
class TryStatement extends Statement {
  BlockStatement block;
  CatchClause? handler; // May be null
  BlockStatement? finalizer; // May be null (but not if handler is null)

  TryStatement(this.block, this.handler, this.finalizer);

  @override
  forEach(callback) {
    callback(block);
    if (handler != null) callback(handler!);
    if (finalizer != null) callback(finalizer!);
  }

  @override
  String toString() => 'TryStatement';

  @override
  visitBy<T>(Visitor<T> v) => v.visitTry(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitTry(this, arg);
}

/// A catch clause: `catch ([param]) [body]`
class CatchClause extends Scope {
  Name param;
  BlockStatement body;

  CatchClause(this.param, this.body);

  @override
  forEach(callback) {
    callback(param);
    callback(body);
  }

  @override
  String toString() => 'CatchClause';

  @override
  visitBy<T>(Visitor<T> v) => v.visitCatchClause(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitCatchClause(this, arg);
}

/// Statement of form: `while ([condition]) [body]`
class WhileStatement extends Statement {
  Expression condition;
  Statement body;

  WhileStatement(this.condition, this.body);

  @override
  forEach(callback) {
    callback(condition);
    callback(body);
  }

  @override
  String toString() => 'WhileStatement';

  @override
  visitBy<T>(Visitor<T> v) => v.visitWhile(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitWhile(this, arg);
}

/// Statement of form: `do [body] while ([condition]);`
class DoWhileStatement extends Statement {
  Statement body;
  Expression condition;

  DoWhileStatement(this.body, this.condition);

  @override
  forEach(callback) {
    callback(body);
    callback(condition);
  }

  @override
  String toString() => 'DoWhileStatement';

  @override
  visitBy<T>(Visitor<T> v) => v.visitDoWhile(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitDoWhile(this, arg);
}

/// Statement of form: `for ([init]; [condition]; [update]) [body]`
class ForStatement extends Statement {
  /// May be VariableDeclaration, Expression, or null.
  Node? init;
  Expression? condition; // May be null.
  Expression? update; // May be null.
  Statement body;

  ForStatement(this.init, this.condition, this.update, this.body);

  @override
  forEach(callback) {
    if (init != null) callback(init!);
    if (condition != null) callback(condition!);
    if (update != null) callback(update!);
    callback(body);
  }

  @override
  String toString() => 'ForStatement';

  @override
  visitBy<T>(Visitor<T> v) => v.visitFor(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitFor(this, arg);
}

/// Statement of form: `for ([left] in [right]) [body]`
class ForInStatement extends Statement {
  /// May be VariableDeclaration or Expression.
  Node left;
  Expression right;
  Statement body;

  ForInStatement(this.left, this.right, this.body);

  @override
  forEach(callback) {
    callback(left);
    callback(right);
    callback(body);
  }

  @override
  String toString() => 'ForInStatement';

  @override
  visitBy<T>(Visitor<T> v) => v.visitForIn(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitForIn(this, arg);
}

/// Statement of form: `function [function.name])([function.params]) { [function.body] }`.
class FunctionDeclaration extends Statement {
  FunctionNode function;

  FunctionDeclaration(this.function);

  @override
  forEach(callback) => callback(function);

  @override
  String toString() => 'FunctionDeclaration';

  @override
  visitBy<T>(Visitor<T> v) => v.visitFunctionDeclaration(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) =>
      v.visitFunctionDeclaration(this, arg);
}

/// Statement of form: `var [declarations];`
class VariableDeclaration extends Statement {
  List<VariableDeclarator> declarations;

  VariableDeclaration(this.declarations);

  @override
  forEach(callback) => declarations.forEach(callback);

  @override
  String toString() => 'VariableDeclaration';

  @override
  visitBy<T>(Visitor<T> v) => v.visitVariableDeclaration(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) =>
      v.visitVariableDeclaration(this, arg);
}

/// Variable declaration: `[name]` or `[name] = [init]`.
class VariableDeclarator extends Node {
  Name name;
  Expression? init; // May be null.

  VariableDeclarator(this.name, this.init);

  @override
  forEach(callback) {
    callback(name);
    if (init != null) callback(init!);
  }

  @override
  String toString() => 'VariableDeclarator';

  @override
  visitBy<T>(Visitor<T> v) => v.visitVariableDeclarator(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) =>
      v.visitVariableDeclarator(this, arg);
}

/// Statement of form: `debugger;`
class DebuggerStatement extends Statement {
  @override
  forEach(callback) {}

  @override
  String toString() => 'DebuggerStatement';

  @override
  visitBy<T>(Visitor<T> v) => v.visitDebugger(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitDebugger(this, arg);
}

///////

/// Superclass of all nodes that are expressions.
abstract class Expression extends Node {}

/// Expression of form: `this`
class ThisExpression extends Expression {
  @override
  forEach(callback) {}

  @override
  String toString() => 'ThisExpression';

  @override
  visitBy<T>(Visitor<T> v) => v.visitThis(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitThis(this, arg);
}

/// Expression of form: `[ [expressions] ]`
class ArrayExpression extends Expression {
  List<Expression?>
      expressions; // May CONTAIN nulls for omitted elements: e.g. [1,2,,,]

  ArrayExpression(this.expressions);

  @override
  forEach(callback) {
    for (Expression? exp in expressions) {
      if (exp != null) {
        callback(exp);
      }
    }
  }

  @override
  String toString() => 'ArrayExpression';

  @override
  visitBy<T>(Visitor<T> v) => v.visitArray(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitArray(this, arg);
}

/// Expression of form: `{ [properties] }`
class ObjectExpression extends Expression {
  List<Property> properties;

  ObjectExpression(this.properties);

  @override
  forEach(callback) => properties.forEach(callback);

  @override
  String toString() => 'ObjectExpression';

  @override
  visitBy<T>(Visitor<T> v) => v.visitObject(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitObject(this, arg);
}

/// Property initializer `[key]: [value]`, or getter `get [key] [value]`, or setter `set [key] [value]`.
///
/// For getters and setters, [value] is a [FunctionNode], otherwise it is an [Expression].
class Property extends Node {
  /// Literal or Name indicating the name of the property. Use [nameString] to get the name as a string.
  Node key;

  /// A [FunctionNode] (for getters and setters) or an [Expression] (for ordinary properties).
  Node value;

  /// May be "init", "get", or "set".
  String kind;

  Property(this.key, this.value, [this.kind = 'init']);

//  Property.getter(this.key, FunctionExpression this.value) : kind = 'get';
//  Property.setter(this.key, FunctionExpression this.value) : kind = 'set';

  bool get isInit => kind == 'init';

  bool get isGetter => kind == 'get';

  bool get isSetter => kind == 'set';

  bool get isAccessor => isGetter || isSetter;

  String? get nameString => key is Name
      ? (key as Name).value
      : (key as LiteralExpression).value.toString();

  /// Returns the value as a FunctionNode. Useful for getters/setters.
  FunctionNode get function => value as FunctionNode;

  /// Returns the value as an Expression. Useful for non-getter/setters.
  Expression get expression => value as Expression;

  @override
  forEach(callback) {
    callback(key);
    callback(value);
  }

  @override
  String toString() => 'Property';

  @override
  visitBy<T>(Visitor<T> v) => v.visitProperty(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitProperty(this, arg);
}

/// Expression of form: `function [function.name]([function.params]) { [function.body] }`.
class FunctionExpression extends Expression {
  FunctionNode function;

  FunctionExpression(this.function);

  @override
  forEach(callback) => callback(function);

  @override
  String toString() => 'FunctionExpression';

  @override
  visitBy<T>(Visitor<T> v) => v.visitFunctionExpression(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) =>
      v.visitFunctionExpression(this, arg);
}

/// Comma-seperated expressions.
class SequenceExpression extends Expression {
  List<Expression> expressions;

  SequenceExpression(this.expressions);

  @override
  forEach(callback) => expressions.forEach(callback);

  @override
  String toString() => 'SequenceExpression';

  @override
  visitBy<T>(Visitor<T> v) => v.visitSequence(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitSequence(this, arg);
}

/// Expression of form: `+[argument]`, or using any of the unary operators:
/// `+, -, !, ~, typeof, void, delete`
class UnaryExpression extends Expression {
  String? operator; // May be: +, -, !, ~, typeof, void, delete
  Expression argument;

  UnaryExpression(this.operator, this.argument);

  @override
  forEach(callback) => callback(argument);

  @override
  String toString() => 'UnaryExpression';

  @override
  visitBy<T>(Visitor<T> v) => v.visitUnary(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitUnary(this, arg);
}

/// Expression of form: `[left] + [right]`, or using any of the binary operators:
/// `==, !=, ===, !==, <, <=, >, >=, <<, >>, >>>, +, -, *, /, %, |, ^, &, &&, ||, in, instanceof`
class BinaryExpression extends Expression {
  Expression left;
  String?
      operator; // May be: ==, !=, ===, !==, <, <=, >, >=, <<, >>, >>>, +, -, *, /, %, |, ^, &, &&, ||, in, instanceof
  Expression right;

  BinaryExpression(this.left, this.operator, this.right);

  @override
  forEach(callback) {
    callback(left);
    callback(right);
  }

  @override
  String toString() => 'BinaryExpression("$left" $operator "$right")';

  @override
  visitBy<T>(Visitor<T> v) => v.visitBinary(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitBinary(this, arg);
}

/// Expression of form: `[left] = [right]` or `[left] += [right]` or using any of the assignment operators:
/// `=, +=, -=, *=, /=, %=, <<=, >>=, >>>=, |=, ^=, &=`
class AssignmentExpression extends Expression {
  Expression left;
  String? operator; // May be: =, +=, -=, *=, /=, %=, <<=, >>=, >>>=, |=, ^=, &=
  Expression right;

  AssignmentExpression(this.left, this.operator, this.right);

  bool get isCompound => operator!.length > 1;

  @override
  forEach(callback) {
    callback(left);
    callback(right);
  }

  @override
  String toString() => 'AssignmentExpression';

  @override
  visitBy<T>(Visitor<T> v) => v.visitAssignment(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitAssignment(this, arg);
}

/// Expression of form: `++[argument]`, `--[argument]`, `[argument]++`, `[argument]--`.
class UpdateExpression extends Expression {
  String? operator; // May be: ++, --
  Expression argument;
  bool isPrefix;

  UpdateExpression(this.operator, this.argument, this.isPrefix);

  UpdateExpression.prefix(this.operator, this.argument) : isPrefix = true;

  UpdateExpression.postfix(this.operator, this.argument) : isPrefix = false;

  @override
  forEach(callback) => callback(argument);

  @override
  String toString() => 'UpdateExpression';

  @override
  visitBy<T>(Visitor<T> v) => v.visitUpdateExpression(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitUpdateExpression(this, arg);
}

/// Expression of form: `[condition] ? [then] : [otherwise]`.
class ConditionalExpression extends Expression {
  Expression condition;
  Expression then;
  Expression otherwise;

  ConditionalExpression(this.condition, this.then, this.otherwise);

  @override
  forEach(callback) {
    callback(condition);
    callback(then);
    callback(otherwise);
  }

  @override
  String toString() => 'ConditionalExpression';

  @override
  visitBy<T>(Visitor<T> v) => v.visitConditional(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitConditional(this, arg);
}

/// Expression of form: `[callee](..[arguments]..)` or `new [callee](..[arguments]..)`.
class CallExpression extends Expression {
  bool isNew;
  Expression callee;
  List<Expression> arguments;

  CallExpression(this.callee, this.arguments, {this.isNew = false});

  CallExpression.newCall(this.callee, this.arguments) : isNew = true;

  @override
  forEach(callback) {
    callback(callee);
    arguments.forEach(callback);
  }

  @override
  String toString() => 'CallExpression';

  @override
  visitBy<T>(Visitor<T> v) => v.visitCall(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitCall(this, arg);
}

/// Expression of form: `[object].[property].`
class MemberExpression extends Expression {
  Expression object;
  Name property;

  MemberExpression(this.object, this.property);

  @override
  forEach(callback) {
    callback(object);
    callback(property);
  }

  @override
  String toString() => 'Member($object.$property)';

  @override
  visitBy<T>(Visitor<T> v) => v.visitMember(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitMember(this, arg);
}

/// Expression of form: `[object][[property]]`.
class IndexExpression extends Expression {
  Expression object;
  Expression property;

  IndexExpression(this.object, this.property);

  @override
  forEach(callback) {
    callback(object);
    callback(property);
  }

  @override
  String toString() => 'IndexExpression($object[$property])';

  @override
  visitBy<T>(Visitor<T> v) => v.visitIndex(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitIndex(this, arg);
}

/// A [Name] that is used as an expression.
///
/// Note that "undefined", "NaN", and "Infinity" are name expressions, and not literals and one might expect.
class NameExpression extends Expression {
  Name name;

  NameExpression(this.name);

  @override
  forEach(callback) => callback(name);

  @override
  String toString() => 'NameExpression(${name.value})';

  @override
  visitBy<T>(Visitor<T> v) => v.visitNameExpression(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitNameExpression(this, arg);
}

/// A literal string, number, boolean or null.
///
/// Note that "undefined", "NaN", and "Infinity" are [NameExpression]s, and not literals and one might expect.
class LiteralExpression extends Expression {
  /// A string, number, boolean, or null value, indicating the value of the literal.
  dynamic value;

  /// The verbatim source-code representation of the literal.
  String? raw;

  LiteralExpression(this.value, [this.raw]);

  bool get isString => value is String;

  bool get isNumber => value is num;

  bool get isBool => value is bool;

  bool get isNull => value == null;

  String? get stringValue => value as String?;

  num? get numberValue => value as num?;

  bool? get boolValue => value as bool?;

  /// Converts the value to a string
  String get toName => value.toString();

  @override
  forEach(callback) {}

  @override
  String toString() => 'Lit($value)';

  @override
  visitBy<T>(Visitor<T> v) => v.visitLiteral(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitLiteral(this, arg);
}

/// A regular expression literal.
class RegexpExpression extends Expression {
  /// The entire literal, including slashes and flags.
  String? regexp;

  RegexpExpression(this.regexp);

  @override
  forEach(callback) {}

  @override
  String toString() => 'RegexpExpression';

  @override
  visitBy<T>(Visitor<T> v) => v.visitRegexp(this);

  @override
  visitBy1<T, A>(Visitor1<T, A> v, A arg) => v.visitRegexp(this, arg);
}
