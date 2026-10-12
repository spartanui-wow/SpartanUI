"""Token lint for Modules/Nameplates (plan 6.3, Decisions 3 and 6). Rules live in lint_rules.json.

Usage (from the SpartanUI folder):
  python Tests/Nameplates/lint.py                 lint every file in scope; exit code 1 on findings
  python Tests/Nameplates/lint.py FILE...         lint only these files (paths relative to the SpartanUI folder)
  python Tests/Nameplates/lint.py --self-test     check the rules against Tests/Nameplates/fixtures/lint/*.txt

Rule kinds
  text          regex over the raw line (code, strings and comments)
  identifier    a name token from a list
  call          a call to a name from a list (print)
  keyword       name tokens Lua 5.1 must not see (goto, continue)
  operator      operator tokens Lua 5.1 does not have (::, //, &, |, ~, <<, >>)
  global-ref    global names only one file may use (Unit*, C_UnitAuras, C_NamePlate.GetNamePlateForUnit)
  secret        the *Secret convention, see below
  index-key     a table key that ends in a forbidden name (t[aura.auraInstanceID])
  named-create  a literal global name passed to CreateFrame and friends
  xml-name      a fixed name="..." in core XML

The secret rule is a heuristic over tokens, not a type checker. A value is "secret-named" when it is
the result of a call to a function or method whose name ends in "Secret", or a variable or field whose
name ends in "Secret". Such a value fails the rule when the token before it is one of
  == ~= < > <= >= and or not if elseif while until + - * / % ^ # [
or the token after it is one of
  == ~= < > <= >= and or + - * / % ^ [ . :
or it is assigned to a name that does not end in "Secret", or passed to a function that is not in
the rule's sink list (type() is a sink, so `type(xSecret) == 'nil'` passes), or stored in a table
constructor. Concatenation and `return` are allowed. Names matching ignorePattern (the C_Secrets
predicates such as ShouldAurasBeSecret, which return plain booleans) are skipped.

Suppress one finding with `-- np-lint: allow <rule-id> <reason>` on the same line or the line
above. Rules with "suppressible": false cannot be suppressed; a suppression without a reason is
itself an error.
"""
import argparse
import fnmatch
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
RULES_FILE = os.path.join(HERE, 'lint_rules.json')
FIXTURES = os.path.join(HERE, 'fixtures', 'lint')

KEYWORDS = {'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while'}
OPERATORS = ['...', '..', '==', '~=', '<=', '>=', '<<', '>>', '//', '::', '+', '-', '*', '/', '%', '^', '#', '&', '~', '|', '<', '>', '=', '(', ')', '{', '}', '[', ']', ';', ':', ',', '.']


class Token:
    __slots__ = ('kind', 'value', 'line')

    def __init__(self, kind, value, line):
        self.kind, self.value, self.line = kind, value, line

    def __repr__(self):
        return '%s(%r)@%d' % (self.kind, self.value, self.line)


def tokenize(text):
    """Lua tokens: name, keyword, number, string, op, comment. Strings keep their quotes."""
    tokens = []
    i, n, line = 0, len(text), 1
    while i < n:
        c = text[i]
        if c == '\n':
            line += 1
            i += 1
            continue
        if c in ' \t\r\f\v':
            i += 1
            continue
        start_line = line
        if text.startswith('--', i):
            m = re.match(r'--\[(=*)\[', text[i:])
            if m:
                close = ']' + m.group(1) + ']'
                end = text.find(close, i + len(m.group(0)))
                end = n if end < 0 else end + len(close)
            else:
                end = text.find('\n', i)
                end = n if end < 0 else end
            value = text[i:end]
            tokens.append(Token('comment', value, start_line))
            line += value.count('\n')
            i = end
            continue
        m = re.match(r'\[(=*)\[', text[i:])
        if m:
            close = ']' + m.group(1) + ']'
            end = text.find(close, i + len(m.group(0)))
            end = n if end < 0 else end + len(close)
            value = text[i:end]
            tokens.append(Token('string', value, start_line))
            line += value.count('\n')
            i = end
            continue
        if c in '"\'':
            j = i + 1
            while j < n and text[j] != c:
                if text[j] == '\\':
                    j += 1
                elif text[j] == '\n':
                    break
                j += 1
            value = text[i:j + 1]
            tokens.append(Token('string', value, start_line))
            line += value.count('\n')
            i = j + 1
            continue
        m = re.match(r'0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?', text[i:])
        if m and (c.isdigit() or (c == '.' and i + 1 < n and text[i + 1].isdigit())):
            tokens.append(Token('number', m.group(0), start_line))
            i += len(m.group(0))
            continue
        m = re.match(r'[A-Za-z_][A-Za-z0-9_]*', text[i:])
        if m:
            word = m.group(0)
            tokens.append(Token('keyword' if word in KEYWORDS else 'name', word, start_line))
            i += len(word)
            continue
        for op in OPERATORS:
            if text.startswith(op, i):
                tokens.append(Token('op', op, start_line))
                i += len(op)
                break
        else:
            tokens.append(Token('op', c, start_line))
            i += 1
    return tokens


class Finding:
    def __init__(self, path, line, rule, message):
        self.path, self.line, self.rule, self.message = path, line, rule, message

    def __str__(self):
        return '%s:%d: [%s] %s' % (self.path, self.line, self.rule, self.message)


def path_matches(rel, patterns):
    return any(fnmatch.fnmatchcase(rel, p) for p in patterns or [])


def rule_applies(rule, rel):
    if rule.get('include') and not path_matches(rel, rule['include']):
        return False
    if path_matches(rel, rule.get('exclude')):
        return False
    return True


def find_close(code, i, open_tok='(', close_tok=')'):
    depth = 0
    for j in range(i, len(code)):
        v = code[j].value if code[j].kind == 'op' else None
        if v == open_tok:
            depth += 1
        elif v == close_tok:
            depth -= 1
            if depth == 0:
                return j
    return len(code) - 1


def find_open(code, i, open_tok='(', close_tok=')'):
    depth = 0
    for j in range(i, -1, -1):
        v = code[j].value if code[j].kind == 'op' else None
        if v == close_tok:
            depth += 1
        elif v == open_tok:
            depth -= 1
            if depth == 0:
                return j
    return 0


def tok(code, i):
    if 0 <= i < len(code):
        return code[i]
    return Token('eof', '', code[-1].line if code else 0)


def is_op(t, *values):
    return t.kind == 'op' and t.value in values


def chain_start(code, i):
    """Walk back over a.b:c(...) chains to the first token of the expression ending at name i."""
    k = i
    while True:
        prev = tok(code, k - 1)
        if is_op(prev, '.', ':'):
            before = tok(code, k - 2)
            if before.kind == 'name':
                k -= 2
                continue
            if is_op(before, ')'):
                k = find_open(code, k - 2, '(', ')')
                if tok(code, k - 1).kind == 'name':
                    k -= 1
                continue
            if is_op(before, ']'):
                k = find_open(code, k - 2, '[', ']')
                if tok(code, k - 1).kind == 'name':
                    k -= 1
                continue
        return k


def enclosing_open(code, i):
    """Index of the unmatched ( or { that encloses token i, or -1."""
    depth = {'(': 0, '{': 0, '[': 0}
    pairs = {')': '(', '}': '{', ']': '['}
    for j in range(i - 1, -1, -1):
        t = code[j]
        if t.kind != 'op':
            continue
        if t.value in pairs:
            depth[pairs[t.value]] += 1
        elif t.value in depth:
            if depth[t.value] == 0:
                return j
            depth[t.value] -= 1
    return -1


LIST_BOUNDARY_KEYWORDS = {'return', 'local', 'in', 'then', 'do', 'else', 'end', 'until', 'if', 'elseif', 'while', 'repeat', 'for', 'function'}


def list_head(code, i):
    """The token that opens the comma list holding token i: an unmatched ( { [, '=', or a keyword."""
    depth = 0
    for j in range(i - 1, -1, -1):
        t = code[j]
        if t.kind == 'op' and t.value in (')', '}', ']'):
            depth += 1
        elif t.kind == 'op' and t.value in ('(', '{', '['):
            if depth == 0:
                return j
            depth -= 1
        elif depth == 0 and ((t.kind == 'keyword' and t.value in LIST_BOUNDARY_KEYWORDS) or is_op(t, '=', ';')):
            return j
    return -1


BAD_BEFORE = {'==', '~=', '<', '>', '<=', '>=', 'and', 'or', 'not', 'if', 'elseif', 'while', 'until', '+', '-', '*', '/', '%', '^', '#', '['}
BAD_AFTER = {'==', '~=', '<', '>', '<=', '>=', 'and', 'or', '+', '-', '*', '/', '%', '^', '[', '.', ':'}


def is_param(code, i):
    """True when token i sits in a function's parameter list."""
    opener = enclosing_open(code, i)
    if opener < 0 or not is_op(code[opener], '('):
        return False
    k = opener - 1
    while k >= 0 and (code[k].kind == 'name' or is_op(code[k], '.', ':')):
        k -= 1
    return tok(code, k).value == 'function' or tok(code, opener - 1).value == 'function'


def is_target(code, i):
    """True when name i is an assignment target or a declared name (local x, for k, v in)."""
    k = i + 1
    while is_op(tok(code, k), ',') and tok(code, k + 1).kind == 'name':
        k += 2
    t = tok(code, k)
    if is_op(t, '='):
        return True
    if t.kind == 'keyword' and t.value == 'in':
        return True
    k = i - 1
    while is_op(tok(code, k), ',') and tok(code, k - 1).kind == 'name':
        k -= 2
    return tok(code, k).value in ('local', 'for')


_sink_cache = {}


def secret_sink_list(text):
    """Names in a `Secret.SINKS = { ... }` table (the documented list in Core/Secret.lua). Entries
    such as 'C_CurveUtil.EvaluateColorFromBoolean' or 'P.Colors:Apply' give their last name."""
    match = re.search(r'\bSINKS\s*=\s*\{(.*?)\n\}', text, flags=re.S)
    if not match:
        return set()
    names = set()
    for entry in re.findall(r"'([^']+)'", match.group(1)):
        # Core helpers (P.Colors:Apply) are matched by their own definitions; a bare last name such
        # as Apply would let any function of that name through
        if not entry.startswith('P.'):
            names.add(re.split(r'[.:]', entry)[-1])
    return names


def rule_sinks(rule, root):
    """The sink list: the rule's names, plus game APIs documented AllowedWhenTainted in any data file,
    plus every function the sink modules define, plus the Secret.SINKS list those modules hold,
    minus notSinks (names documented as sinks that wait for an in-game check)."""
    key = (id(rule), root)
    if key in _sink_cache:
        return _sink_cache[key]
    sinks = set(rule.get('sinks', []))
    if rule.get('sinksFromData'):
        folder = os.path.join(HERE, 'data')
        if os.path.isdir(folder):
            for name in os.listdir(folder):
                if name.endswith('.lua'):
                    with open(os.path.join(folder, name), encoding='utf-8') as fh:
                        sinks.update(re.findall(r"^\s*([A-Za-z_][A-Za-z0-9_]*) = 'T\|", fh.read(), flags=re.M))
    for module in rule.get('sinkModules', []):
        path = os.path.join(root, module)
        if os.path.exists(path):
            with open(path, encoding='utf-8') as fh:
                text = fh.read()
            sinks.update(re.findall(r'^function\s+[A-Za-z_][A-Za-z0-9_]*[.:]([A-Za-z_][A-Za-z0-9_]*)\s*\(', text, flags=re.M))
            sinks.update(re.findall(r'^[A-Za-z_][A-Za-z0-9_]*\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function', text, flags=re.M))
            sinks.update(secret_sink_list(text))
    sinks.difference_update(rule.get('notSinks', []))
    _sink_cache[key] = sinks
    return sinks


def check_secret(rule, code, rel, report, root=ROOT):
    suffix = rule.get('suffix', 'Secret')
    ignore = re.compile(rule['ignorePattern']) if rule.get('ignorePattern') else None
    qualifiers = set(rule.get('ignoreQualifiers', []))
    sinks = rule_sinks(rule, root)
    for i, t in enumerate(code):
        if t.kind != 'name' or not t.value.endswith(suffix) or t.value == suffix:
            continue
        if ignore and ignore.match(t.value):
            continue
        if is_op(tok(code, i - 1), '.', ':') and tok(code, i - 2).value in qualifiers:
            continue
        start = chain_start(code, i)
        if tok(code, start - 1).value == 'function' or is_param(code, i):
            continue
        nxt = tok(code, i + 1)
        end, is_call = i, False
        if is_op(nxt, '('):
            end, is_call = find_close(code, i + 1), True
        elif nxt.kind == 'string':
            end, is_call = i + 1, True
        elif is_op(nxt, '{'):
            end, is_call = find_close(code, i + 1, '{', '}'), True
        if not is_call and start == i and is_target(code, i):
            continue
        # A PascalCase name that is not called is a function reference (kind.TestSecret), not a value
        if not is_call and t.value[:1].isupper():
            continue
        if not is_call and start != i and is_op(nxt, '=') and not is_op(tok(code, start - 1), '(', ','):
            continue  # self.xSecret = value
        before, after = tok(code, start - 1), tok(code, end + 1)
        what = ('the result of %s()' % t.value) if is_call else t.value
        bad = None
        if after.kind in ('op', 'keyword') and after.value in BAD_AFTER:
            bad = "'%s' after %s" % (after.value, what)
        elif before.kind in ('op', 'keyword') and before.value in BAD_BEFORE:
            bad = "'%s' before %s" % (before.value, what)
        elif is_op(before, '='):
            target = tok(code, start - 2)
            if target.kind != 'name':
                bad = '%s stored in a table slot' % what
            elif not target.value.endswith(suffix):
                bad = '%s stored in %s; name it ...%s' % (what, target.value, suffix)
        elif is_op(before, '{'):
            bad = '%s stored in a table constructor' % what
        elif is_op(before, '(', ','):
            opener = start - 1 if is_op(before, '(') else list_head(code, start)
            head = tok(code, opener)
            if head.value == 'return':
                opener = -1
            elif is_op(head, '='):
                k = opener - 1
                targets = []
                while tok(code, k).kind == 'name':
                    targets.append(tok(code, k).value)
                    if not is_op(tok(code, k - 1), ','):
                        break
                    k -= 2
                if any(not name.endswith(suffix) for name in targets) or not targets:
                    bad = '%s stored in %s; name it ...%s' % (what, ', '.join(reversed(targets)) or 'a table slot', suffix)
                opener = -1
            elif head.kind == 'keyword':
                opener = -1
            if opener >= 0 and is_op(code[opener], '{'):
                bad = '%s stored in a table constructor' % what
            elif opener >= 0 and is_op(code[opener], '['):
                bad = '%s used as a table key' % what
            elif opener >= 0 and is_op(code[opener], '('):
                callee = tok(code, opener - 1)
                if callee.kind != 'name':
                    bad = '%s passed to a computed function' % what
                elif not (callee.value in sinks or callee.value.endswith(suffix)):
                    bad = '%s passed to %s(), which is not an approved sink' % (what, callee.value)
        if bad:
            report(t.line, bad)


def lint_lua(rel, text, rules):
    findings = []
    lines = text.split('\n')
    tokens = tokenize(text)
    code = [t for t in tokens if t.kind != 'comment']
    for rule in rules:
        if not rule_applies(rule, rel):
            continue
        rid, kind = rule['id'], rule['kind']

        def report(line, detail=None, rid=rid, rule=rule):
            findings.append(Finding(rel, line, rid, rule['message'] + (' (%s)' % detail if detail else '')))

        if kind == 'text':
            pattern = re.compile(rule['pattern'], re.I if rule.get('ignoreCase') else 0)
            for no, line in enumerate(lines, 1):
                if pattern.search(line):
                    report(no, pattern.search(line).group(0).strip())
        elif kind == 'identifier':
            names = set(rule['names'])
            for t in code:
                if t.kind == 'name' and t.value in names:
                    report(t.line, t.value)
        elif kind == 'call':
            names = set(rule['names'])
            for i, t in enumerate(code):
                if t.kind == 'name' and t.value in names and not is_op(tok(code, i - 1), '.', ':'):
                    nxt = tok(code, i + 1)
                    if is_op(nxt, '(', '{') or nxt.kind == 'string':
                        report(t.line, t.value + '()')
        elif kind == 'keyword':
            names = set(rule['names'])
            for i, t in enumerate(code):
                if t.kind == 'name' and t.value in names and not is_op(tok(code, i - 1), '.', ':'):
                    report(t.line, t.value)
        elif kind == 'operator':
            ops = set(rule['operators'])
            for t in code:
                if t.kind == 'op' and t.value in ops:
                    report(t.line, t.value)
        elif kind == 'global-ref':
            if path_matches(rel, rule.get('allow')):
                continue
            patterns = [re.compile(p) for p in rule.get('patterns', [])]
            qualified = [q.split('.') for q in rule.get('qualified', [])]
            indirect = set(rule.get('indirectCallers', ['pcall', 'xpcall', 'securecall', 'securecallfunction']))
            for i, t in enumerate(code):
                if t.kind != 'name' or is_op(tok(code, i - 1), '.', ':'):
                    continue
                if is_op(tok(code, i + 1), '=') and is_op(tok(code, i - 1), '{', ','):
                    continue  # table constructor key
                label, end = None, i
                if any(p.match(t.value) for p in patterns):
                    label = t.value
                    if is_op(tok(code, i + 1), '.', ':') and tok(code, i + 2).kind == 'name':
                        end = i + 2
                        label = t.value + '.' + tok(code, i + 2).value
                else:
                    for q in qualified:
                        if t.value == q[0] and is_op(tok(code, i + 1), '.') and tok(code, i + 2).value == q[1]:
                            label, end = '.'.join(q), i + 2
                if not label:
                    continue
                after, before = tok(code, end + 1), tok(code, i - 1)
                if is_op(after, '(', '{') or after.kind == 'string':
                    report(t.line, 'calls ' + label)
                elif is_op(before, '=') and not (after.kind in ('op', 'keyword') and after.value in ('==', '~=', 'and', 'or', '.', ':', '[')):
                    report(t.line, 'aliases ' + label)
                elif is_op(before, '(') and tok(code, i - 2).value in indirect:
                    report(t.line, 'calls %s through %s' % (label, tok(code, i - 2).value))
        elif kind == 'secret':
            if not path_matches(rel, rule.get('allow')):
                check_secret(rule, code, rel, report)
        elif kind == 'index-key':
            names = set(rule['names'])
            for i, t in enumerate(code):
                if t.kind == 'name' and t.value in names and is_op(tok(code, i + 1), ']'):
                    opener = find_open(code, i + 1, '[', ']')
                    if opener > 0 and code[opener - 1].kind in ('name', 'op'):
                        report(t.line, t.value)
        elif kind == 'named-create':
            functions = rule['functions']
            for i, t in enumerate(code):
                if t.kind == 'name' and t.value in functions and is_op(tok(code, i + 1), '('):
                    if tok(code, i - 1).value == 'function':
                        continue
                    want = functions[t.value]
                    close = find_close(code, i + 1)
                    arg, depth, k = 1, 0, i + 2
                    while k < close:
                        v = code[k]
                        if v.kind == 'op' and v.value in '({[':
                            depth += 1
                        elif v.kind == 'op' and v.value in ')}]':
                            depth -= 1
                        elif depth == 0 and is_op(v, ','):
                            arg += 1
                        elif depth == 0 and arg == want and v.kind == 'string' and (is_op(tok(code, k + 1), ',') or k + 1 == close):
                            if not is_op(tok(code, k - 1), '..') and not is_op(tok(code, k + 1), '..'):
                                report(v.line, '%s(... %s ...)' % (t.value, v.value))
                        k += 1
    return apply_suppressions(findings, lines, rules)


def lint_xml(rel, text, rules):
    findings = []
    lines = text.split('\n')
    for rule in rules:
        if not rule_applies(rule, rel):
            continue
        rid, kind = rule['id'], rule['kind']
        if kind == 'text':
            pattern = re.compile(rule['pattern'], re.I if rule.get('ignoreCase') else 0)
            for no, line in enumerate(lines, 1):
                if pattern.search(line):
                    findings.append(Finding(rel, no, rid, rule['message'] + ' (%s)' % pattern.search(line).group(0).strip()))
        elif kind == 'xml-name':
            for no, line in enumerate(lines, 1):
                for m in re.finditer(r'<(\w+)\b[^>]*?\bname\s*=\s*"([^"]+)"', line):
                    if m.group(1) in ('Script', 'Include', 'Ui') or m.group(2).startswith('$parent'):
                        continue
                    findings.append(Finding(rel, no, rid, rule['message'] + ' (%s)' % m.group(2)))
    return apply_suppressions(findings, lines, rules)


SUPPRESS = re.compile(r'(?:--|<!--)\s*np-lint:\s*allow\s+([\w-]+)(.*)')


def apply_suppressions(findings, lines, rules):
    by_id = {r['id']: r for r in rules}
    kept = []
    for f in findings:
        suppressed = False
        for no in (f.line, f.line - 1):
            if 1 <= no <= len(lines):
                m = SUPPRESS.search(lines[no - 1])
                if m and m.group(1) == f.rule:
                    reason = m.group(2).strip().rstrip('->').strip()
                    if not by_id[f.rule].get('suppressible', True):
                        f.message += ' (this rule cannot be suppressed)'
                    elif not reason:
                        f.message += ' (a suppression needs a reason)'
                    else:
                        suppressed = True
        if not suppressed:
            kept.append(f)
    return kept


def load_rules():
    with open(RULES_FILE, encoding='utf-8') as fh:
        return json.load(fh)


def files_in_scope(cfg, root):
    out = []
    for scope in cfg['scope']:
        base = scope.split('*')[0].rstrip('/')
        folder = os.path.join(root, base)
        if not os.path.isdir(folder):
            continue
        for dirpath, _, names in os.walk(folder):
            for name in sorted(names):
                if os.path.splitext(name)[1] in cfg['extensions']:
                    rel = os.path.relpath(os.path.join(dirpath, name), root).replace('\\', '/')
                    if path_matches(rel, cfg['scope']):
                        out.append(rel)
    return sorted(set(out))


def lint_file(rel, text, cfg):
    if rel.endswith('.xml'):
        return lint_xml(rel, text, cfg['rules'])
    return lint_lua(rel, text, cfg['rules'])


def run_lint(paths=None, root=ROOT):
    cfg = load_rules()
    rels = paths or files_in_scope(cfg, root)
    findings = []
    for rel in rels:
        with open(os.path.join(root, rel), encoding='utf-8') as fh:
            findings.extend(lint_file(rel.replace('\\', '/'), fh.read(), cfg))
    return rels, findings


def self_test():
    cfg = load_rules()
    failures = 0
    cases = sorted(f for f in os.listdir(FIXTURES) if f.endswith('.txt'))
    for name in cases:
        with open(os.path.join(FIXTURES, name), encoding='utf-8') as fh:
            text = fh.read()
        rel = re.search(r'path:\s*(\S+)', text).group(1)
        expect = re.search(r'expect:\s*([^\n]*)', text).group(1).replace('-->', '').strip()
        want = sorted(x.strip() for x in expect.split(',') if x.strip() and x.strip() != 'none')
        found = lint_file(rel, text, cfg)
        got = sorted({f.rule for f in found})
        if got != want:
            failures += 1
            print('FAIL %s: expected %s, got %s' % (name, want or ['none'], got or ['none']))
            for f in found:
                print('     ' + str(f))
        else:
            print('ok   %s' % name)
    print('%d lint fixtures, %d failed' % (len(cases), failures))
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('files', nargs='*')
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    rels, findings = run_lint(args.files or None)
    for f in findings:
        print(f)
    print('lint: %d files, %d findings' % (len(rels), len(findings)))
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
