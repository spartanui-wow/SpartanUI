"""Game API lists for the nameplate harness, read from Blizzard's UI source.

Usage (from the SpartanUI folder):
  python Tests/Nameplates/api_matrix.py                    report: every game API Modules/Nameplates uses, per client
  python Tests/Nameplates/api_matrix.py --generate         rebuild Tests/Nameplates/data/<flavor>.lua for every flavor
  python Tests/Nameplates/api_matrix.py --generate --flavor retail

Branches are read with "git show" / "git grep" from wow-ui-source; nothing is checked out.
The generated API documentation is executed in a Lua 5.1 sandbox (lupa) so its tables are read
exactly, including the secret-value markers the strict mock enforces.
"""
import argparse
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flavors as F  # noqa: E402

DOC_DIR = 'Interface/AddOns/Blizzard_APIDocumentationGenerated'
MODULE_DIR = os.path.join(F.ROOT, 'Modules', 'Nameplates')
FRAMEXML_MODELS = os.path.join(F.HERE, 'harness', 'framexml.lua')
LABELS = {'retail': 'Retail', 'ptr': 'PTR', 'forever': 'Forever', 'mists': 'Mists', 'titan': 'Titan', 'tbc': 'TBC', 'era': 'Era'}
POLICY = {'AllowedWhenTainted': 'T', 'AllowedWhenUntainted': 'U', 'NotAllowed': 'N'}
STRUCTURAL = {'Name', 'Type', 'Arguments', 'Returns', 'Documentation', 'SecretArguments', 'Payload', 'LiteralName', 'Environment'}


def git(*args):
    return subprocess.run(['git', '-C', F.UI_SOURCE] + list(args), capture_output=True, text=True, encoding='utf-8', errors='replace').stdout


# ---------------------------------------------------------------------------------------------
# API documentation, executed in Lua 5.1
# ---------------------------------------------------------------------------------------------

DOC_PRELUDE = r'''
DOCS = {}
APIDocumentation = { AddDocumentationTable = function(self, t) DOCS[#DOCS + 1] = t end }
local ref
local proxyMeta = {}
local function zero() return 0 end
proxyMeta.__add, proxyMeta.__sub, proxyMeta.__mul, proxyMeta.__div = zero, zero, zero, zero
proxyMeta.__mod, proxyMeta.__pow, proxyMeta.__unm = zero, zero, zero
proxyMeta.__concat = function() return '' end
proxyMeta.__tostring = function(t) return rawget(t, 'name') end
proxyMeta.__index = function(t, k) return setmetatable({ name = rawget(t, 'name') .. '.' .. k }, proxyMeta) end
Enum = setmetatable({ name = 'Enum' }, proxyMeta)
Constants = setmetatable({ name = 'Constants' }, proxyMeta)
function PROXYNAME(v)
	if type(v) == 'table' and getmetatable(v) == proxyMeta then
		return rawget(v, 'name')
	end
end
'''


def lua_runtime():
    from lupa import lua51

    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(DOC_PRELUDE)
    return lua


def lua_list(t):
    if t is None:
        return []
    out = []
    i = 1
    while t[i] is not None:
        out.append(t[i])
        i += 1
    return out


def scalar(lua, v):
    """Turn a doc value into something we can write back out: numbers, strings, bools, proxy names."""
    if isinstance(v, (bool, int, float, str)):
        return v
    name = lua.globals().PROXYNAME(v)
    if name is not None:
        return str(name)
    if v is not None and lua.eval('type')(v) == 'table':
        return [scalar(lua, x) for x in lua_list(v)]
    return None


def fn_record(lua, fn):
    args = lua_list(fn['Arguments'])
    unit_index = 0
    for i, a in enumerate(args, 1):
        if 'UnitToken' in str(a['Type'] or ''):
            unit_index = i
            break
    flags = []
    for key, value in fn.items():
        if key in STRUCTURAL:
            continue
        v = scalar(lua, value)
        if v is True:
            flags.append(key)
        elif isinstance(v, list) and v:
            flags.append(key + '=' + '+'.join(str(x).split('.')[-1] for x in v))
        elif isinstance(v, str) and key not in ('Namespace',):
            flags.append(key + '=' + v.split('.')[-1])
    policy = POLICY.get(str(fn['SecretArguments'] or ''), '')
    nret = len(lua_list(fn['Returns']))
    return '%s|%d|%d|%s' % (policy, unit_index, nret, ','.join(sorted(flags)))


def parse_docs(ref):
    lua = lua_runtime()
    files = [f for f in git('ls-tree', '--name-only', ref, DOC_DIR + '/').split() if f.endswith('.lua')]
    errors = []
    for f in files:
        try:
            lua.execute(git('show', ref + ':' + f))
        except Exception as e:  # a broken doc file only costs its own entries
            errors.append('%s: %s' % (f, str(e).splitlines()[0][:120]))
    inv = {'functions': {}, 'namespaces': {}, 'scriptObjects': {}, 'events': {}, 'enums': {}, 'constants': {}, 'docErrors': errors, 'secrets': False}
    for d in lua_list(lua.eval('DOCS')):
        kind = d['Type']
        ns = d['Namespace']
        for fn in lua_list(d['Functions']):
            rec = fn_record(lua, fn)
            if fn['SecretArguments'] is not None:
                inv['secrets'] = True
            name = fn['Name']
            if kind == 'ScriptObject':
                inv['scriptObjects'].setdefault(d['Name'], {})[name] = rec
            elif ns:
                inv['namespaces'].setdefault(ns, {})[name] = rec
            else:
                inv['functions'][name] = rec
        for ev in lua_list(d['Events']):
            literal = ev['LiteralName']
            if not literal:
                continue
            payload = lua_list(ev['Payload'])
            unit_index = 0
            for i, p in enumerate(payload, 1):
                if 'UnitToken' in str(p['Type'] or ''):
                    unit_index = i
                    break
            flags = []
            for key, value in ev.items():
                if key in STRUCTURAL:
                    continue
                v = scalar(lua, value)
                if v is True:
                    flags.append(key)
            inv['events'][literal] = '%d|%d|%s' % (len(payload), unit_index, ','.join(sorted(flags)))
        for t in lua_list(d['Tables']):
            if t['Type'] == 'Enumeration':
                fields = {}
                for fld in lua_list(t['Fields']):
                    v = scalar(lua, fld['EnumValue'])
                    if isinstance(v, (int, float)) and not isinstance(v, bool):
                        fields[fld['Name']] = int(v) if float(v).is_integer() else v
                inv['enums'][t['Name']] = fields
            elif t['Type'] == 'Constants':
                values = {}
                for val in lua_list(t['Values']):
                    v = scalar(lua, val['Value'])
                    if isinstance(v, (bool, int, float, str)) and not (isinstance(v, str) and v.startswith(('Enum.', 'Constants.'))):
                        values[val['Name']] = v
                inv['constants'][t['Name']] = values
    return inv


# ---------------------------------------------------------------------------------------------
# Lua and XML source: globals Blizzard defines, CVars it names, aura container methods
# ---------------------------------------------------------------------------------------------


def source_globals(ref):
    names = set()
    out = git('grep', '-h', '-o', '-E', r'^(function [A-Za-z_][A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]* *=)', ref, '--', 'Interface/*.lua')
    for t in out.splitlines():
        names.add(t.replace('function ', '').replace('=', '').strip())
    out = git('grep', '-h', '-o', '-E', r'<[A-Za-z]+ [^>]*name="[A-Za-z_][A-Za-z0-9_]*"', ref, '--', 'Interface/*.xml')
    for t in out.splitlines():
        if 'virtual="true"' in t:
            continue
        m = re.search(r'name="([A-Za-z_][A-Za-z0-9_]*)"', t)
        if m:
            names.add(m.group(1))
    return names


def source_templates(ref):
    names = set()
    out = git('grep', '-h', '-o', '-E', r'<[A-Za-z]+ [^>]*virtual="true"[^>]*>|<[A-Za-z]+ [^>]*name="[A-Za-z_][A-Za-z0-9_]*"[^>]*virtual="true"', ref, '--', 'Interface/*.xml')
    for t in out.splitlines():
        m = re.search(r'name="([A-Za-z_][A-Za-z0-9_]*)"', t)
        if m:
            names.add(m.group(1))
    return names


def modeled_templates():
    names = []
    if not os.path.exists(FRAMEXML_MODELS):
        return names
    with open(FRAMEXML_MODELS, encoding='utf-8') as fh:
        for line in fh:
            m = re.match(r'^\t([A-Za-z_][A-Za-z0-9_]*) = function\(M, frame\)', line)
            if m:
                names.append(m.group(1))
    return names


def modeled_engine_names():
    """Global functions the mock implements (lines starting "FN.Name =" in harness/*.lua)."""
    names = set()
    folder = os.path.join(F.HERE, 'harness')
    for n in os.listdir(folder):
        if n.endswith('.lua'):
            with open(os.path.join(folder, n), encoding='utf-8') as fh:
                names.update(re.findall(r'^FN\.([A-Za-z_][A-Za-z0-9_]*)\s*=', fh.read(), flags=re.M))
    return names


def engine_functions(ref, inv):
    """Engine functions the API docs leave out on this branch (common on Classic) but Blizzard's own
    code uses. Only names the mock implements or Modules/Nameplates calls are checked."""
    wanted = modeled_engine_names()
    if os.path.isdir(MODULE_DIR):
        _, calls, _ = module_usage()
        wanted |= {c for c in calls if c[:1].isupper()}
    wanted = sorted(n for n in wanted if n not in inv['functions'])
    found = set()
    for i in range(0, len(wanted), 150):
        chunk = wanted[i:i + 150]
        out = git('grep', '-h', '-o', '-E', r'(^|[^.:A-Za-z0-9_])(%s)\s*\(' % '|'.join(chunk), ref, '--', 'Interface/*.lua')
        found.update(re.findall(r'([A-Za-z_][A-Za-z0-9_]*)\s*\(', out))
    return {n for n in wanted if n in found}


def source_calls(ref):
    out = git('grep', '-h', '-o', '-E', r'(^|[^.:A-Za-z0-9_])[A-Za-z_][A-Za-z0-9_]+\(', ref, '--', 'Interface/*.lua')
    return set(re.findall(r'([A-Za-z_][A-Za-z0-9_]*)\(', out))


CVAR_CALL = re.compile(r'(?:GetCVar|GetCVarBool|GetCVarDefault|GetCVarInfo|GetCVarNumberOrDefault|GetCVarBitfield|SetCVar|SetCVarBitfield|SetCVarToDefault|'
                       r'RegisterCVar|SetCVarCallback|GetCVarValue|GetCVarValueBool|RegisterCVarSetting|SetupCVar[A-Za-z]*|RegisterProxyCVarSetting)\s*\(\s*(?:[A-Za-z_.:]+\s*,\s*)?["\']([A-Za-z_][A-Za-z0-9_]*)["\']')
CVAR_FIELD = re.compile(r'\b(?:cvar|cvarName|CVar)\s*=\s*["\']([A-Za-z_][A-Za-z0-9_]*)["\']')


def known_cvar_names():
    """CVar names from the ketho.wow-api annotations (a Retail list), when the extension is installed."""
    import glob
    names = set()
    pattern = os.path.join(os.path.expanduser('~'), '.vscode', 'extensions', 'ketho.wow-api-*', 'Annotations', 'Core', 'Data', 'CVar.lua')
    for path in sorted(glob.glob(pattern))[-1:]:
        with open(path, encoding='utf-8') as fh:
            names.update(re.findall(r'^---\|"([A-Za-z_][A-Za-z0-9_]*)"', fh.read(), flags=re.M))
    return names


def source_cvars(ref):
    """CVars this branch's own code names: in CVar calls, or as a quoted string that is a known CVar name."""
    out = git('grep', '-h', '-E', r'CVar|cvar', ref, '--', 'Interface/*.lua', 'Interface/*.xml')
    names = set()
    for line in out.splitlines():
        names.update(CVAR_CALL.findall(line))
        names.update(CVAR_FIELD.findall(line))
    known = sorted(known_cvar_names())
    for i in range(0, len(known), 150):
        chunk = known[i:i + 150]
        found = git('grep', '-h', '-o', '-E', '["\'](%s)["\']' % '|'.join(chunk), ref, '--', 'Interface/*.lua', 'Interface/*.xml')
        names.update(x.strip('\'"') for x in found.split())
    # Nameplate CVars newer than the annotation list (nameplateStackingTypes is held in a local first)
    found = git('grep', '-h', '-o', '-E', '["\']nameplate[A-Z][A-Za-z0-9_]*["\']', ref, '--', 'Interface/*.lua', 'Interface/*.xml')
    names.update(x.strip('\'"') for x in found.split())
    return names


def aura_container_methods(ref):
    folder = 'Interface/AddOns/Blizzard_AuraContainer'
    files = [f for f in git('ls-tree', '-r', '--name-only', ref, folder + '/').split() if f.endswith('.lua')]
    if not files:
        return []
    compose, methods = {}, {}
    for f in files:
        for line in git('show', ref + ':' + f).splitlines():
            m = re.match(r'^([A-Za-z_]\w*)\s*=\s*CreateFromMixins\(([^)]*)\)', line)
            if m:
                compose[m.group(1)] = [x.strip() for x in m.group(2).split(',') if x.strip()]
                continue
            m = re.match(r'^function ([A-Za-z_]\w*)[:.]([A-Za-z_]\w*)\s*\(', line)
            if m:
                methods.setdefault(m.group(1), set()).add(m.group(2))

    def resolve(name, seen):
        if name in seen:
            return set()
        seen.add(name)
        out = set(methods.get(name, set()))
        for parent in compose.get(name, []):
            out |= resolve(parent, seen)
        return out

    found = resolve('CustomAuraContainerInboundMixin', set())
    return sorted(m for m in found if m[:1].isupper())


def modeled_framexml_names():
    names = []
    if not os.path.exists(FRAMEXML_MODELS):
        return names
    with open(FRAMEXML_MODELS, encoding='utf-8') as fh:
        for line in fh:
            m = re.match(r'^\t([A-Za-z_][A-Za-z0-9_]*) = function\(M\)', line)
            if m:
                names.append(m.group(1))
    return names


def literal_table_names():
    if not os.path.exists(FRAMEXML_MODELS):
        return []
    with open(FRAMEXML_MODELS, encoding='utf-8') as fh:
        return re.findall(r"M\.LiteralTable\('([A-Za-z_][A-Za-z0-9_]*)'\)", fh.read())


def literal_tables(ref, names):
    """Read simple `Name = { Key = number, ... }` tables Blizzard defines in Lua."""
    out = {}
    for name in names:
        hits = git('grep', '-l', '-E', r'^%s\s*=' % name, ref, '--', 'Interface/*.lua').split()
        if not hits:
            continue
        text = git('show', hits[0])
        m = re.search(r'^%s\s*=\s*\{(.*?)^\}' % name, text, flags=re.S | re.M)
        if not m:
            continue
        fields = {}
        for key, value in re.findall(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(-?\d+)\s*,', m.group(1), flags=re.M):
            fields[key] = int(value)
        out[name] = fields
    return out


def undocumented_enums(ref, documented):
    """Enum tables Blizzard's code uses that the documentation leaves out (Enum.GameRule on Forever).
    Field values are unknown: the data file numbers them 1..n so names stay distinct."""
    out = {}
    found = git('grep', '-h', '-o', '-E', r'Enum\.[A-Za-z_][A-Za-z0-9_]*\.[A-Za-z_][A-Za-z0-9_]*', ref, '--', 'Interface/*.lua')
    for item in set(found.split()):
        _, enum, field = item.split('.')
        if enum not in documented:
            out.setdefault(enum, set()).add(field)
    return {enum: {field: i for i, field in enumerate(sorted(fields), 1)} for enum, fields in out.items()}


def version_of(ref):
    subject = git('log', '-1', '--format=%s', ref).strip()
    m = re.match(r'([\d.]+)\s*\((\d+)\)', subject)
    return (m.group(1), m.group(2)) if m else (subject, '0')


# ---------------------------------------------------------------------------------------------
# Writing the data files
# ---------------------------------------------------------------------------------------------

LUA_KEY = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')
LUA_RESERVED = {'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while'}


def lua_key(k):
    if isinstance(k, str) and LUA_KEY.match(k) and k not in LUA_RESERVED:
        return k
    if isinstance(k, str):
        return '[%s]' % lua_value(k)
    return '[%s]' % k


def lua_value(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(v)
    s = str(v).replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n')
    return "'%s'" % s


def write_table(out, value, indent, inline=False):
    pad = '\t' * indent
    for k in sorted(value, key=lambda x: str(x)):
        v = value[k]
        if isinstance(v, dict) and inline:
            items = ', '.join('%s = %s' % (lua_key(ik), lua_value(v[ik])) for ik in sorted(v, key=lambda x: str(x)))
            out.append('%s%s = { %s },' % (pad, lua_key(k), items))
        elif isinstance(v, dict):
            out.append('%s%s = {' % (pad, lua_key(k)))
            write_table(out, v, indent + 1, inline=(indent == 1 and k in ('enums', 'enumsUndocumented', 'constants')))
            out.append('%s},' % pad)
        elif isinstance(v, (list, tuple, set)):
            items = ', '.join(lua_value(x) for x in sorted(v))
            out.append('%s%s = { %s },' % (pad, lua_key(k), items))
        else:
            out.append('%s%s = %s,' % (pad, lua_key(k), lua_value(v)))


def generate(flavor):
    cfg = F.FLAVORS[flavor]
    ref = cfg['ref']
    version, build = version_of(ref)
    print('  %s: reading %s (%s %s)' % (flavor, ref, version, build))
    inv = parse_docs(ref)
    defined = source_globals(ref)
    templates = source_templates(ref)
    fxml = {}
    for name in modeled_framexml_names():
        if name in defined:
            fxml[name] = True
    data = {
        'meta': {
            'flavor': flavor, 'ref': ref, 'version': version, 'build': build, 'interface': cfg['interface'], 'project': cfg['project'], 'secrets': inv['secrets'],
        },
        'functions': inv['functions'],
        'namespaces': inv['namespaces'],
        'scriptObjects': inv['scriptObjects'],
        'events': inv['events'],
        'enums': inv['enums'],
        'enumsUndocumented': undocumented_enums(ref, inv['enums']),
        'constants': {k: v for k, v in inv['constants'].items() if v},
        'fxml': fxml,
        'cvars': {name: True for name in source_cvars(ref)},
        'auraContainer': {name: True for name in aura_container_methods(ref)},
        'fxmlTables': literal_tables(ref, [n for n in literal_table_names() if n in fxml]),
        'templates': {name: True for name in modeled_templates() if name in templates},
        'engine': {name: True for name in engine_functions(ref, inv)},
    }
    out = ['-- Generated by Tests/Nameplates/api_matrix.py --generate from wow-ui-source %s (%s %s). Do not edit by hand.' % (ref, version, build), 'return {']
    write_table(out, data, 1)
    out.append('}')
    path = F.data_path(flavor)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write('\n'.join(out) + '\n')
    # Format like the pre-commit hook would, so committing never rewrites a generated file
    try:
        subprocess.run(['stylua', path], cwd=F.ROOT, capture_output=True)
    except FileNotFoundError:
        print('    stylua not found; the file is left unformatted')
    for err in inv['docErrors']:
        print('    doc file skipped: ' + err)
    print('    %d functions, %d namespaces, %d script objects, %d events, %d enums, %d cvars -> %s' % (
        len(inv['functions']), len(inv['namespaces']), len(inv['scriptObjects']), len(inv['events']), len(inv['enums']), len(data['cvars']), os.path.relpath(path, F.ROOT)))


# Engine functions the documentation leaves out. The mock provides them on every flavor; the data
# file records whether Blizzard's own code calls them on that branch, as a cross-check.
CORE_UNDOCUMENTED = {
    'CreateFrame', 'CreateFont', 'hooksecurefunc', 'issecure', 'securecall', 'securecallfunction', 'debugstack', 'debugprofilestart', 'debugprofilestop',
    'geterrorhandler', 'seterrorhandler', 'EnumerateFrames', 'GetFramesRegisteredForEvent', 'wipe', 'strsplit', 'strjoin', 'strconcat', 'strtrim',
    'strlenutf8', 'tostringall', 'GetBuildInfo', 'GetLocale', 'GetPhysicalScreenSize', 'GetCurrentRegion', 'forceinsecure', 'issecurevariable',
}


# ---------------------------------------------------------------------------------------------
# Report: what Modules/Nameplates calls, per client
# ---------------------------------------------------------------------------------------------


def strip_lua(text):
    text = re.sub(r'--\[(=*)\[.*?\]\1\]', '', text, flags=re.S)
    text = re.sub(r'--[^\n]*', '', text)
    text = re.sub(r'\[(=*)\[.*?\]\1\]', '""', text, flags=re.S)
    text = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", text)
    text = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', text)
    return text


def module_usage():
    files = []
    for dirpath, _, names in os.walk(MODULE_DIR):
        for n in names:
            if n.endswith('.lua'):
                files.append(os.path.join(dirpath, n))
    source = {}
    for f in files:
        with open(f, encoding='utf-8') as fh:
            source[f] = fh.read()
    code = strip_lua('\n'.join(source.values()))
    defined = set(re.findall(r'\bfunction\s+(?:[A-Za-z_][A-Za-z0-9_]*[.:])*([A-Za-z_][A-Za-z0-9_]*)\s*\(', code))
    defined |= set(re.findall(r'\blocal\s+function\s+([A-Za-z_][A-Za-z0-9_]*)', code))
    for m in re.findall(r'\blocal\s+([A-Za-z_][A-Za-z0-9_,\s]*?)\s*=', code):
        defined |= {n.strip() for n in m.split(',')}
    for m in re.findall(r'\blocal\s+([A-Za-z_][A-Za-z0-9_, \t]*?)[ \t]*$', code, flags=re.M):
        defined |= {n.strip() for n in m.split(',')}
    for m in re.findall(r'\bfunction\s*[A-Za-z0-9_.:]*\s*\(([^)]*)\)', code):
        defined |= {n.strip() for n in m.split(',') if n.strip() and n.strip() != '...'}
    for m in re.findall(r'\bfor\s+([A-Za-z_][A-Za-z0-9_, \t]*?)\s+in\b', code):
        defined |= {n.strip() for n in m.split(',')}
    lua_builtins = set('assert error ipairs pairs next pcall xpcall select setmetatable getmetatable tonumber tostring type unpack rawget rawset rawequal date time collectgarbage loadstring require'.split())
    keywords = {'function', 'if', 'and', 'or', 'not', 'return', 'elseif', 'while', 'for', 'until', 'local', 'then', 'do', 'end', 'in'}
    calls = set()
    for name in re.findall(r'(?<![\.:\w])([A-Za-z_][A-Za-z0-9_]*)\s*\(', code):
        if name in defined or name in lua_builtins or name in keywords or name in ('LibStub',):
            continue
        calls.add(name)
    namespaced = set(re.findall(r'(?<![\.:\w])(C_[A-Za-z]+)\.([A-Za-z0-9_]+)', code))
    return source, calls, namespaced


def report(flavor_list):
    source, calls, namespaced = module_usage()
    if not source:
        print('Modules/Nameplates has no Lua files yet; nothing to check.')
        return 0
    inventories = {}
    for flavor in flavor_list:
        ref = F.FLAVORS[flavor]['ref']
        print('reading %s ...' % ref, file=sys.stderr)
        inv = parse_docs(ref)
        inventories[flavor] = (inv, source_globals(ref), source_calls(ref))

    def exists(flavor, kind, item):
        inv, defined, called = inventories[flavor]
        if kind == 'ns':
            return item[1] in inv['namespaces'].get(item[0], {})
        return item in inv['functions'] or item in defined or item in called or item in CORE_UNDOCUMENTED

    rows = [('call', n, n) for n in sorted(calls)] + [('ns', item, '.'.join(item)) for item in sorted(namespaced)]
    print('%-60s %s' % ('API', ' '.join('%-8s' % LABELS[f] for f in flavor_list)))
    missing = []
    for kind, item, label in rows:
        marks = ['Y' if exists(f, kind, item) else '-' for f in flavor_list]
        print('%-60s %s' % (label, ' '.join('%-8s' % m for m in marks)))
        if '-' in marks:
            missing.append((label, [f for f, m in zip(flavor_list, marks) if m == '-']))
    print('\n%d APIs checked; %d missing on at least one client' % (len(rows), len(missing)))
    for label, where in missing:
        print('\n== %s (missing on: %s)' % (label, ', '.join(LABELS[f] for f in where)))
        for f, text in source.items():
            for i, line in enumerate(text.splitlines(), 1):
                if re.search(r'(?<![\w])' + re.escape(label) + r'(?![\w])', line) and not line.strip().startswith('--'):
                    print('   %s:%d: %s' % (os.path.relpath(f, F.ROOT), i, line.strip()[:150]))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--generate', action='store_true', help='rebuild the data files the mock reads')
    parser.add_argument('--flavor', action='append', choices=F.ORDER, help='limit to one flavor (repeatable)')
    args = parser.parse_args()
    flavor_list = args.flavor or F.ORDER
    if args.generate:
        for flavor in flavor_list:
            generate(flavor)
        return 0
    return report(flavor_list)


if __name__ == '__main__':
    sys.exit(main())
