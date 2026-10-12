"""Nameplate test entry point.

Usage (from the SpartanUI folder):
  python Tests/Nameplates/run.py                      everything: stylua, lint, every suite on every default flavor
  python Tests/Nameplates/run.py --flavor retail      one flavor (repeatable; 'ptr' is available but not in the default set)
  python Tests/Nameplates/run.py --suite smoke        suites whose file name contains 'smoke' (repeatable)
  python Tests/Nameplates/run.py --only "restricted"  only tests whose full name contains the text
  python Tests/Nameplates/run.py --runtime lua51      force one runtime for every suite
  python Tests/Nameplates/run.py --syntax-only        formatting differences warn instead of failing
  python Tests/Nameplates/run.py --skip-stylua --skip-lint

Steps: stylua --check on Modules/Nameplates and Tests/Nameplates, the token lint and its self-test,
then every Tests/Nameplates/suites/*_spec.lua under every flavor, one process per suite, flavor and
runtime. A suite's first line picks its runtime: "-- @runtime lua51", "luals" (the default) or "both".
Exit code 1 when anything fails.
"""
import argparse
import concurrent.futures
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flavors as F  # noqa: E402
import lint  # noqa: E402

HERE = F.HERE


def find_luals():
    if os.environ.get('NP_LUALS'):
        return os.environ['NP_LUALS']
    pattern = os.path.join(os.path.expanduser('~'), '.vscode', 'extensions', 'sumneko.lua-*', 'server', 'bin', 'lua-language-server*')
    found = sorted(p for p in glob.glob(pattern) if os.path.isfile(p))
    return found[-1] if found else None


def stage_root(root):
    """The LuaLS binary breaks on paths containing '--' (pitfalls 2026-09-28): copy what the run needs."""
    if '--' not in root:
        return root, None
    staged = tempfile.mkdtemp(prefix='np_tests_')
    for rel in ('Tests/Nameplates', 'Modules/Nameplates', 'libs/Ace3', 'libs/LibSharedMedia-3.0'):
        src = os.path.join(root, rel)
        if os.path.isdir(src):
            shutil.copytree(src, os.path.join(staged, rel))
    for name in ('.stylua.toml', '.styluaignore'):
        if os.path.exists(os.path.join(root, name)):
            shutil.copy(os.path.join(root, name), staged)
    return staged, staged


def run_stylua(root, syntax_only):
    targets = [t for t in ('Modules/Nameplates', 'Tests/Nameplates') if os.path.isdir(os.path.join(root, t))]
    try:
        proc = subprocess.run(['stylua', '--check'] + targets, cwd=root, capture_output=True, text=True, encoding='utf-8', errors='replace')
    except FileNotFoundError:
        return False, ['stylua was not found on PATH']
    out = proc.stdout + proc.stderr
    parse_errors = [line for line in out.splitlines() if 'error parsing' in line.lower() or line.lower().startswith('error')]
    diffs = sorted(set(re.findall(r'Diff in (.+?):?$', out, flags=re.M)))
    messages = []
    for line in parse_errors:
        messages.append('syntax: ' + line.strip())
    for path in diffs:
        messages.append(('format (warning): ' if syntax_only else 'format: ') + path.strip())
    ok = not parse_errors and (syntax_only or not diffs) and (proc.returncode == 0 or (syntax_only and not parse_errors))
    return ok, messages


def suite_runtime(path):
    with open(path, encoding='utf-8') as fh:
        head = fh.read(400)
    m = re.search(r'@runtime\s+(lua51|luals|both)', head)
    return m.group(1) if m else 'luals'


def parse_output(text):
    result = {'pass': 0, 'fail': 0, 'skip': 0, 'failures': [], 'skips': [], 'notes': [], 'complete': False, 'info': ''}
    current = None
    for line in text.splitlines():
        if line.startswith('@@'):
            current = None
            if line.startswith('@@PASS'):
                continue
            if line.startswith('@@FAIL '):
                current = {'name': line[7:], 'detail': []}
                result['failures'].append(current)
            elif line.startswith('@@SKIP '):
                result['skips'].append(line[7:])
            elif line.startswith('@@NOTE '):
                result['notes'].append(line[7:])
            elif line.startswith('@@INFO '):
                result['info'] = line[7:]
            elif line.startswith('@@RESULT'):
                m = re.search(r'pass=(\d+) fail=(\d+) skip=(\d+)', line)
                if m:
                    result['pass'], result['fail'], result['skip'] = (int(x) for x in m.groups())
                    result['complete'] = True
        elif current is not None:
            current['detail'].append(line)
    return result


LUA55_ONLY = re.compile(r"attempt to assign to const variable '[^']+'")


def run_job(job, root, luals, only):
    suite, flavor, runtime = job
    rel = os.path.join(root, 'Tests', 'Nameplates', 'suites', suite).replace('\\', '/')
    rootarg = root.replace('\\', '/') + '/'
    if runtime == 'luals':
        cmd = [luals, os.path.join(root, 'Tests', 'Nameplates', 'harness', 'boot.lua'), rootarg, flavor, rel, only or '']
    else:
        cmd = [sys.executable, os.path.join(HERE if root == F.ROOT else os.path.join(root, 'Tests', 'Nameplates'), 'lupa_run.py'), rootarg, flavor, rel, only or '']
    try:
        proc = subprocess.run(cmd, cwd=root, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=600)
        text = proc.stdout + ('\n' + proc.stderr if proc.stderr.strip() else '')
    except subprocess.TimeoutExpired:
        text = '@@FAIL (timeout)\nthe run took longer than 10 minutes'
    result = parse_output(text)
    if runtime == 'luals' and LUA55_ONLY.search(text):
        # Valid Lua 5.1 that Lua 5.5 refuses to compile (assigning to a for-loop variable): rerun on 5.1
        job2, result2 = run_job((suite, flavor, 'lua51'), root, luals, only)
        result2['notes'].insert(0, 'reran under lua51: Lua 5.5 refuses valid 5.1 code (%s)' % LUA55_ONLY.search(text).group(0))
        return job, result2
    if not result['complete']:
        result['fail'] = max(result['fail'], 1)
        if not result['failures']:
            result['failures'].append({'name': '(runner)', 'detail': text.splitlines()[-30:]})
    return job, result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--flavor', action='append', choices=F.ORDER)
    parser.add_argument('--suite', action='append', help='run suites whose file name contains this text')
    parser.add_argument('--only', help='run only tests whose full name contains this text')
    parser.add_argument('--runtime', choices=['lua51', 'luals'])
    parser.add_argument('--jobs', type=int, default=max(2, (os.cpu_count() or 4) - 1))
    parser.add_argument('--syntax-only', action='store_true', help='formatting differences warn instead of failing')
    parser.add_argument('--skip-stylua', action='store_true')
    parser.add_argument('--skip-lint', action='store_true')
    parser.add_argument('-v', '--verbose', action='store_true', help='print full failure output and skipped tests')
    args = parser.parse_args()

    root, staged = stage_root(F.ROOT)
    failed_steps = []
    try:
        if not args.skip_stylua:
            ok, messages = run_stylua(root, args.syntax_only)
            print('== stylua --check: %s' % ('ok' if ok else 'FAILED'))
            for m in messages:
                print('   ' + m)
            if not ok:
                failed_steps.append('stylua')

        if not args.skip_lint:
            rels, findings = lint.run_lint(root=root)
            print('== lint: %d files, %d findings' % (len(rels), len(findings)))
            for f in findings:
                print('   ' + str(f))
            if findings:
                failed_steps.append('lint')
            import io
            import contextlib
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                code = lint.self_test()
            last = buf.getvalue().strip().splitlines()[-1] if buf.getvalue().strip() else ''
            print('== lint self-test: %s' % last)
            if code:
                print(buf.getvalue())
                failed_steps.append('lint self-test')

        luals = find_luals()
        suites = sorted(os.path.basename(p) for p in glob.glob(os.path.join(root, 'Tests', 'Nameplates', 'suites', '*_spec.lua')))
        if args.suite:
            suites = [s for s in suites if any(want in s for want in args.suite)]
        flavor_list = args.flavor or F.DEFAULT_FLAVORS
        jobs = []
        for suite in suites:
            runtime = args.runtime or suite_runtime(os.path.join(root, 'Tests', 'Nameplates', 'suites', suite))
            runtimes = ['lua51', 'luals'] if runtime == 'both' else [runtime]
            for flavor in flavor_list:
                for rt in runtimes:
                    if rt == 'luals' and not luals:
                        print('   LuaLS binary not found; running %s under lua51 instead' % suite)
                        rt = 'lua51'
                    jobs.append((suite, flavor, rt))
        jobs = sorted(set(jobs), key=lambda j: (j[0], F.ORDER.index(j[1]), j[2]))
        print('== suites: %d runs (%d suites x %s)' % (len(jobs), len(suites), ', '.join(flavor_list)))
        results = {}
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            futures = [pool.submit(run_job, job, root, luals, args.only) for job in jobs]
            for fut in concurrent.futures.as_completed(futures):
                job, result = fut.result()
                results[job] = result

        totals = {'pass': 0, 'fail': 0, 'skip': 0}
        current = None
        for job in jobs:
            suite, flavor, rt = job
            r = results[job]
            if suite != current:
                print('   %s' % suite)
                current = suite
            for k in totals:
                totals[k] += r[k]
            status = 'FAIL' if r['fail'] else 'ok  '
            print('     %s %-8s %-6s pass %3d  fail %3d  skip %3d' % (status, flavor, rt, r['pass'], r['fail'], r['skip']))
            for note in r['notes']:
                print('          note: ' + note)
            if args.verbose:
                for s in r['skips']:
                    print('          skip: ' + s)
        failures = [(job, f) for job in jobs for f in results[job]['failures']]
        if failures:
            print('\n== failures')
            for (suite, flavor, rt), f in failures:
                print('-- %s [%s, %s] %s' % (suite, flavor, rt, f['name']))
                detail = [d for d in f['detail'] if d.strip()]
                if not args.verbose:
                    cut = next((i for i, d in enumerate(detail) if d.strip().startswith('stack traceback')), len(detail))
                    detail = detail[:max(cut, 1)][:12]
                for d in detail:
                    print('   ' + d)
            failed_steps.append('suites')
        print('\n== total: %d passed, %d failed, %d skipped across %d runs' % (totals['pass'], totals['fail'], totals['skip'], len(jobs)))
    finally:
        if staged:
            shutil.rmtree(staged, ignore_errors=True)
    if failed_steps:
        print('FAILED: ' + ', '.join(failed_steps))
        return 1
    print('ALL PASSED')
    return 0


if __name__ == '__main__':
    sys.exit(main())
