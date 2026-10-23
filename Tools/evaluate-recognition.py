#!/usr/bin/env python3
"""Run identical synthetic materials twice through released/current local recognition."""
import argparse,json,pathlib,subprocess,tarfile,io,urllib.request,urllib.error,os,http.server,threading
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--model',required=True);p.add_argument('--report-dir',type=pathlib.Path,required=True);args=p.parse_args()
folder=args.report_dir.resolve();folder.mkdir(parents=True,exist_ok=True)
previous=folder/'baseline';previous.mkdir(exist_ok=True)
archive=subprocess.check_output(['git','archive','v1.14.5','Sources'],cwd=ROOT)
with tarfile.open(fileobj=io.BytesIO(archive)) as tf:tf.extractall(previous,filter='data')
(previous/'Tests').mkdir(exist_ok=True);(previous/'Tests/RecognitionEvaluation.m').write_bytes((ROOT/'Tests/RecognitionEvaluation.m').read_bytes())
class Counter(http.server.BaseHTTPRequestHandler):
    calls=0
    def log_message(self,*args):pass
    def do_POST(self):
        assert self.path=='/api/chat' and not self.headers.get('Authorization')
        Counter.calls+=1
        body=self.rfile.read(int(self.headers['Content-Length']))
        request=urllib.request.Request('http://localhost:11434/api/chat',data=body,headers={'Content-Type':'application/json'})
        try:
            response=urllib.request.urlopen(request,timeout=180)
        except urllib.error.HTTPError as error:response=error
        with response:
            data=response.read();self.send_response(response.code);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Counter)
threading.Thread(target=server.serve_forever,daemon=True).start()
for revision,source in [('old',previous),('new',ROOT)]:
 Counter.calls=0
 compiler=['clang','-DDDL_TESTING=1','-fobjc-arc','-fblocks','-Wno-unused-parameter','-O2','-mmacosx-version-min=13.0']
 for framework in ('Foundation','Cocoa','Vision','Security'):compiler+=['-framework',framework]
 compiler += [str(source/'Sources'/f'{name}.m') for name in ('SSRecognition','SSAssignments','SSLocalData','SSSecurity','DDLCore','DDLImport')]
 binary=folder/f'evaluate-{revision}';compiler += [str(source/'Tests/RecognitionEvaluation.m'),'-o',str(binary)];subprocess.run(compiler,cwd=ROOT,check=True)
 isolated=folder/f'data-{revision}';isolated.mkdir(exist_ok=True)
 subprocess.run([str(binary),str(ROOT/'Tests/recognition-evaluation.json'),args.model,f'http://127.0.0.1:{server.server_port}',str(folder/f'{revision}.json')],cwd=ROOT,env=dict(os.environ,AM_TEST_DATA=str(isolated)),check=True)
 rows=json.loads((folder/f'{revision}.json').read_text());summary={'revision':revision,'cases':len(rows),'correct':sum(r['correct'] for r in rows),'complete':sum(r['modelComplete'] for r in rows),'duplicates':sum(r['duplicateCount'] for r in rows),'falsePositives':sum(r['falsePositiveCount'] for r in rows),'misses':sum(r['missedCount'] for r in rows),'extractionCalls':sum(r['requests'] for r in rows),'networkRequests':Counter.calls,'seconds':round(sum(r['seconds'] for r in rows),2)}
 (folder/f'{revision}-summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary),flush=True)

server.shutdown();server.server_close()
