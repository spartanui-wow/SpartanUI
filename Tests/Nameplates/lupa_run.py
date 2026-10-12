"""Run one suite under one flavor in Lua 5.1 (lupa). Used by run.py; prints the same @@ lines as the
LuaLS runner. Usage: python Tests/Nameplates/lupa_run.py <repo root> <flavor> <suite file> [name filter]"""
import sys


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    root, flavor, suite = sys.argv[1], sys.argv[2], sys.argv[3]
    only = sys.argv[4] if len(sys.argv) > 4 else ''
    from lupa import lua51

    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    root = root.replace('\\', '/')
    if not root.endswith('/'):
        root += '/'
    g.HARNESS_ROOT = root
    g.FLAVOR = flavor
    g.SUITE = suite.replace('\\', '/')
    g.SUITE_ONLY = only or None
    g.RUNTIME = 'lua51'
    try:
        lua.execute('dofile(HARNESS_ROOT .. "Tests/Nameplates/harness/boot.lua")')
    except Exception as e:  # a crash outside the suite's own error handling
        sys.stdout.write('@@FAIL (runner)\n%s\n@@RESULT pass=0 fail=1 skip=0\n' % e)
    sys.stdout.flush()
    return 0


if __name__ == '__main__':
    sys.exit(main())
