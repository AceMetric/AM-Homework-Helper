#!/usr/bin/env python3
"""Compare released/current prompts on fixed synthetic inputs using a loopback model only."""
import argparse
import json
import pathlib
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]


def old_function(source, name):
    section = source.split(f'{name}(void)', 1)[1].split(';}', 1)[0]
    return ''.join(json.loads('"' + value + '"') for value in re.findall(r'@"((?:\\.|[^"\\])*)"', section))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--endpoint', default='http://localhost:11434')
    parser.add_argument('--model', required=True)
    parser.add_argument('--cases', nargs='*', help='Optional synthetic case IDs for a focused replay')
    parser.add_argument('--report', required=True, type=pathlib.Path)
    args = parser.parse_args()
    address = urllib.parse.urlsplit(args.endpoint)
    if address.hostname not in ('localhost', '127.0.0.1', '::1') or address.scheme not in ('http', 'https') or address.username or address.password or address.query or address.fragment:
        parser.error('Only a credential-free loopback endpoint is allowed')
    compiler = ['clang', '-DDDL_TESTING=1', '-fobjc-arc', '-fblocks', '-Wno-unused-parameter', '-mmacosx-version-min=13.0']
    for framework in ('Foundation', 'Cocoa', 'Vision', 'Security'):
        compiler += ['-framework', framework]
    compiler += ['Sources/' + name + '.m' for name in ('SSRecognition', 'SSAssignments', 'SSLocalData', 'SSSecurity', 'DDLCore', 'DDLImport')]
    compiler += ['Tests/PromptContract.m', '-o', 'build/tests/prompt-contract']
    (ROOT / 'build/tests').mkdir(parents=True, exist_ok=True)
    subprocess.run(compiler, cwd=ROOT, check=True)
    current = json.loads(subprocess.check_output([str(ROOT / 'build/tests/prompt-contract'), '--export']))
    previous = subprocess.check_output(['git', 'show', 'v1.14.0:Sources/AMPrompts.h'], cwd=ROOT, text=True)
    skill = subprocess.check_output(['git', 'show', 'v1.14.0:Skills/am-homework-extract/SKILL.md'], cwd=ROOT, text=True)
    baseline = {'course': old_function(previous, 'AMCoursePrompt'), 'review': old_function(previous, 'AMReviewPrompt'), 'notice': skill.split('## Local notices and screenshot text', 1)[1].split('## Pre-submission', 1)[0]}
    baseline['focus'] = baseline['review'] + '\n请结合整份项目重新核对这个疑点；允许撤回原判断。'
    cases = [{'kind': 'course', 'id': f'course-{i}', 'text': row['text'], 'expected': len(row['activities'])} for i, row in enumerate(current['examples'])]
    cases.append({'kind': 'notice', 'id': 'notice', 'text': '作业：写一份报告。截止：2027年4月20日18:00。', 'expected': 1})
    # These cases test false positives and independent withdrawal; no real student work is read.
    for kind, identifier, text in [('review', 'teacher-only', '# Assignment\nProve theorem A.'), ('review', 'valid-alternative', 'For every real x, x*x is nonnegative because a square is nonnegative.'), ('focus', 'withdraw', 'For all real x, x² ≥ 0. A previous finding claimed x² could be negative. Recheck this claim.')]:
        cases.append({'kind': kind, 'id': identifier, 'text': text, 'expected': 0})
    args.report.parent.mkdir(parents=True, exist_ok=True)
    contract = args.report.parent / 'prompt-contract-input.json'
    contract.write_text(json.dumps({'noticeText': cases[5]['text']}))
    notice_material = json.loads(subprocess.check_output([str(ROOT / 'build/tests/prompt-contract'), str(contract)]))
    cases.append({'kind': 'review', 'id': 'actual-error', 'text': 'For every real x, x*x is strictly negative. For x=2, x*x=-4.', 'expected': 1})
    rows = []
    for case in cases:
        if args.cases and case['id'] not in args.cases:
            continue
        for revision in ('old', 'new'):
            prompt = (baseline if revision == 'old' else current)[case['kind']]
            if case['kind'] == 'course':
                material = case['text'] if revision == 'old' else json.dumps({'text': case['text'], 'lines': [{'line': i + 1, 'text': line} for i, line in enumerate(case['text'].split('\n'))]}, ensure_ascii=False)
            elif case['kind'] == 'notice':
                material = json.dumps({'format': 'am-local-context-v1', 'batchID': 'synthetic-batch', 'documents': [dict(notice_material, sourceID=notice_material['id'])]}, ensure_ascii=False)
            else:
                material = json.dumps({'format': 'am-preflight-context-v1', 'batchID': 'synthetic-batch', 'reportVersion': 'v1', 'documents': [{'path': 'answer.md' if case['id'] != 'teacher-only' else 'assignment/README.md', 'version': 'v1', 'text': case['text']}], 'images': [], 'requirements': ''}, ensure_ascii=False)
                if case['kind'] == 'focus' and revision == 'new':
                    prompt = current['review'] + '\n' + current['focus']
            body = {'model': args.model, 'messages': [{'role': 'system', 'content': prompt}, {'role': 'user', 'content': material}], 'stream': False, 'think': False, 'format': current['courseSchema'] if revision == 'new' and case['kind'] == 'course' else 'json', 'options': {'temperature': 0, 'num_predict': 2400}}
            started = time.monotonic()
            row = {'case': case['id'], 'revision': revision, 'requests': 0, 'passed': False}
            try:
                for attempt in range(2):
                    row['requests'] += 1
                    request = urllib.request.Request(args.endpoint.rstrip('/') + '/api/chat', data=json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
                    try:
                        with urllib.request.urlopen(request, timeout=70) as response:
                            result = json.load(response)
                        break
                    except urllib.error.HTTPError as error:
                        if error.code != 501 or attempt:
                            raise
                        body.pop('format', None)
                content = result['message']['content'].strip()
                if content.startswith('```') and content.endswith('```'):
                    content = content.split('\n', 1)[1].rsplit('```', 1)[0]
                (args.report.parent / ('prompt-' + case['id'] + '-' + revision + '.txt')).write_text(content)
                if revision == 'new':
                    contract.write_text(json.dumps({'decode': content}))
                    decoded = json.loads(subprocess.check_output([str(ROOT / 'build/tests/prompt-contract'), str(contract)]))
                    if not decoded['valid']:
                        raise ValueError('Invalid structured output')
                    answer = decoded['object']
                else:
                    answer = json.loads(content)
                if case['kind'] == 'course':
                    contract = args.report.parent / 'prompt-contract-input.json'
                    contract.write_text(json.dumps({'text': case['text'], 'activities': answer.get('activities')}, ensure_ascii=False))
                    check = json.loads(subprocess.check_output([str(ROOT / 'build/tests/prompt-contract'), str(contract)]))
                    row.update(check)
                    row['passed'] = check['complete'] and check['count'] == case['expected']
                    row['false_positives'] = max(0, check['count'] - case['expected'])
                    row['misses'] = max(0, case['expected'] - check['count'])
                else:
                    payload = {'kind': 'notice', 'material': notice_material, 'answer': answer} if case['kind'] == 'notice' else {'kind': 'review', 'context': json.loads(material), 'answer': answer}
                    contract.write_text(json.dumps(payload, ensure_ascii=False))
                    check = json.loads(subprocess.check_output([str(ROOT / 'build/tests/prompt-contract'), str(contract)]))
                    row.update(check)
                    row['passed'] = (check.get('valid', check['complete']) if case['id'] == 'teacher-only' else check['complete']) and (check['count'] >= 1 if case['id'] == 'actual-error' else check['count'] == case['expected'])
                    row['false_positives'] = max(0, check['count'] - case['expected']) if case['id'] != 'actual-error' else 0
                    row['misses'] = max(0, case['expected'] - check['count'])
            except Exception as error:
                row['error_type'] = type(error).__name__
            row['seconds'] = round(time.monotonic() - started, 3)
            rows.append(row)
            args.report.write_text(json.dumps({'model': args.model, 'synthetic_only': True, 'results': rows}, ensure_ascii=False, indent=2))
            print(f"{case['id']} {revision}: {'PASS' if row['passed'] else 'FAIL'} ({row['seconds']}s, {row['requests']} requests)", flush=True)
    summary = {revision: {'passed': sum(r['passed'] for r in rows if r['revision'] == revision), 'cases': sum(r['revision'] == revision for r in rows)} for revision in ('old', 'new')}
    print(json.dumps(summary), flush=True)


if __name__ == '__main__':
    main()
