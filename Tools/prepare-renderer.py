#!/usr/bin/env python3
"""Fetch immutable upstream browser distributions; never runs package scripts."""
from pathlib import Path
import hashlib, io, tarfile, urllib.request, shutil, json
ROOT=Path(__file__).resolve().parents[1]
CACHE=ROOT/'build/deps/renderer'
OUT=CACHE/'public'
PACKAGES=[
 ('mathjax','https://registry.npmjs.org/mathjax/-/mathjax-4.1.3.tgz','b7109f516f3d842de62b95d653e35fa0976dc223706a2a77440e7f7723f0c54d'),
 ('markdown-it','https://registry.npmjs.org/markdown-it/-/markdown-it-15.0.2.tgz','3237f5ecac432f99453e6d8d345b6e4764a22f1781c96e02dc9e89777b9c23c1'),
 ('dompurify','https://registry.npmjs.org/dompurify/-/dompurify-3.4.17.tgz','056cbdae276897208b88c21d1d779adfa09ad7be488a2f510a28e900d3bbffe7'),
 ('mathjax-font','https://registry.npmjs.org/@mathjax/mathjax-newcm-font/-/mathjax-newcm-font-4.1.3.tgz','87d7b869c6a2a6169d9a53acc4eab6c846a9cbe11752738226461bb5070c8b88'),
]
CACHE.mkdir(parents=True,exist_ok=True)
stamp=hashlib.sha256((repr(PACKAGES)+'manifest-v2').encode()).hexdigest()
marker=OUT/'.pinned'
if not marker.exists() or marker.read_text()!=stamp:
 if OUT.exists():shutil.rmtree(OUT)
 OUT.mkdir()
 for name,url,digest in PACKAGES:
  archive=CACHE/(name+'.tgz')
  if not archive.exists():archive.write_bytes(urllib.request.urlopen(url,timeout=90).read())
  data=archive.read_bytes()
  if hashlib.sha256(data).hexdigest()!=digest:raise SystemExit('Pinned renderer checksum mismatch: '+name)
  with tarfile.open(fileobj=io.BytesIO(data)) as package:
   for member in package.getmembers():
    parts=Path(member.name).parts
    if not member.isfile() or not parts or parts[0]!='package' or '..' in parts:continue
    relative='/'.join(parts[1:]);target=None
    if relative in ('LICENSE','LICENSE-MPL'):target=OUT/(name+'-'+relative+'.txt')
    elif name=='markdown-it' and relative=='dist/browser/markdown-it.umd.min.js':target=OUT/'markdown-it.js'
    elif name=='dompurify' and relative=='dist/purify.min.js':target=OUT/'dompurify.js'
    elif name=='mathjax' and relative.endswith('.js'):target=OUT/'mathjax'/relative
    elif name=='mathjax-font' and relative.endswith('.js') and (relative=='svg.js' or relative.startswith('svg/')):target=OUT/'font'/relative
    if target:
     target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(package.extractfile(member).read())
 shutil.copy2(OUT/'mathjax-LICENSE.txt',OUT/'mathjax-font-LICENSE.txt')
 manifest={str(p.relative_to(OUT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.rglob('*') if p.is_file() and p.name not in ('.pinned','am-renderer.js','manifest.json')}
 (OUT/'manifest.json').write_text(json.dumps(manifest,sort_keys=True))
 marker.write_text(stamp)
for name,url,digest in PACKAGES:
 if hashlib.sha256((CACHE/(name+'.tgz')).read_bytes()).hexdigest()!=digest:raise SystemExit('Cached renderer checksum mismatch: '+name)
for relative,digest in json.loads((OUT/'manifest.json').read_text()).items():
 if hashlib.sha256((OUT/relative).read_bytes()).hexdigest()!=digest:raise SystemExit('Prepared renderer checksum mismatch: '+relative)
shutil.copy2(ROOT/'Sources/AMRenderer.js',OUT/'am-renderer.js')
print(OUT)
