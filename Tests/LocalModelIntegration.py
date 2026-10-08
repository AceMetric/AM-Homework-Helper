"""Loopback-only model fixture. Never contacts Ollama or sends course originals."""
import http.server
import json
import pathlib
import subprocess
import threading

ROOT = pathlib.Path(__file__).resolve().parents[1]

class Fixture(http.server.BaseHTTPRequestHandler):
    calls = 0
    def log_message(self, *args):
        pass
    def respond(self, obj):
        data = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    def do_GET(self):
        assert self.path == '/api/tags'
        self.respond({'models': [{'name': 'installed-fixture', 'digest': str(Fixture.calls)}]})
    def do_POST(self):
        assert self.path == '/api/chat'
        assert self.headers.get('Authorization') is None
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert 'tools' not in body
        Fixture.calls += 1
        text = body['messages'][-1]['content']
        activities = [{'kind': 'assignment', 'title': '模拟课程报告', 'summary': '分析模拟任务。',
                       'submissionRequirements': '', 'evidence': text,
                       'deadlineEvidence': next((line for line in text.splitlines() if line.startswith('截止')), '')}]
        content = '{}' if body['model'] == 'invalid-fixture' else json.dumps({'activities': activities})
        self.respond({'message': {'content': content}})

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    subprocess.run([str(ROOT / 'build/tests/local-model-integration'), f'http://127.0.0.1:{server.server_port}'], cwd=ROOT, check=True)
finally:
    server.shutdown()
    server.server_close()
