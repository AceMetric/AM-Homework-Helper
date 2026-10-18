#!/usr/bin/env python3
"""Real, silent macOS notification identity regression; no production identity/data.

Requires a local desktop session. Provisional authorization never requests alert
or sound permission. All test requests are future-only and explicitly cleaned.
"""
from pathlib import Path
import argparse
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]

def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, **kwargs)

def suite(identity_only=False):
    outcomes = {}; checks = 0
    with tempfile.TemporaryDirectory(prefix='reminder-identities-', dir=ROOT / 'build/tests') as directory:
        root = Path(directory)
        for stable in (False, True):
            name = 'stable' if stable else 'default'
            app = root / (name+'.app'); backup = root / (name+'-original.app')
            mac = app / 'Contents/MacOS'; mac.mkdir(parents=True)
            bundle = 'io.github.ddl-manager.reminder-identity.'+uuid.uuid4().hex
            result = root / (name+'.plist')
            info = {'CFBundleIdentifier':bundle, 'CFBundleName':'Isolated Reminder Identity Test', 'CFBundleExecutable':'Probe', 'CFBundlePackageType':'APPL', 'LSUIElement':True, 'ProbeResult':str(result)}
            (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
            rows = []; requirements = []
            try:
                for version in (1,2):
                    run('clang','-fobjc-arc','-fblocks',f'-DREVISION={version}','-framework','Cocoa','-framework','UserNotifications',ROOT/'Tests/ReminderIdentityProbe.m','-o',mac/'Probe')
                    options = ['--requirements',f'=designated => identifier "{bundle}"'] if stable else []
                    run('codesign','--force','--sign','-',*options,app)
                    run('codesign','--verify','--deep','--strict',app)
                    display=run('codesign','-d','-r-',app)
                    dr=next(line.split('designated =>',1)[1].strip() for line in (display.stdout+display.stderr).decode().splitlines() if 'designated =>' in line)
                    requirements.append(dr)
                    if version==1:
                        shutil.copytree(app,backup)
                    if not identity_only:
                        for mode in (['seed'] if version==1 else ['read','clear']):
                            run('/usr/bin/open','-g','-n','-W',app,'--args',mode,timeout=20)
                            value=plistlib.loads(result.read_bytes());rows.append({'mode':mode,'result':value})
                            if mode=='seed':
                                assert value.get('granted') and value.get('pending')==['synthetic.future'],value
                            elif mode=='read':
                                assert value['pending']==(['synthetic.future'] if stable else []),value
                            else:
                                assert value['pending']==[],value
                            checks+=1
                assert (requirements[0]==requirements[1])==stable
                checks+=1
                cross=subprocess.run(['codesign','--verify','--strict','-R','='+requirements[0],str(app)],capture_output=True)
                assert (cross.returncode==0)==stable,(name,cross.returncode,cross.stderr.decode())
                checks+=1
                if not identity_only:
                    shutil.rmtree(app);shutil.copytree(backup,app)
                    run('/usr/bin/open','-g','-n','-W',app,'--args','read',timeout=20)
                    value=plistlib.loads(result.read_bytes());rows.append({'mode':'old-after-new-clear','result':value})
                    assert value['pending']==([] if stable else ['synthetic.future']),value
                    checks+=1
                    run('/usr/bin/open','-g','-n','-W',app,'--args','seed',timeout=20)
                    bridge=root/(name+'.dylib')
                    run('clang','-fobjc-arc','-fblocks','-dynamiclib',f'-DAM_REMINDER_HOST_PREFIX=@"{bundle}"','-framework','Cocoa','-framework','UserNotifications',ROOT/'Tools/ReminderMaintenance.m','-o',bridge)
                    run('codesign','--force','--sign','-',bridge)
                    env={'HOME':str(Path.home()),'PATH':'/usr/bin:/bin','DYLD_INSERT_LIBRARIES':str(bridge),'AM_REMINDER_MAINTENANCE':'1'}
                    copy=root/(name+'-copy.app');shutil.copytree(app,copy)
                    report=root/(name+'-maintenance.plist')
                    run(copy/'Contents/MacOS/Probe','--am-reminder-maintenance',report,env=env,timeout=10)
                    denied=subprocess.run([str(copy/'Contents/MacOS/Probe')],env=env,capture_output=True,timeout=10);assert denied.returncode==91;checks+=1
                    value=plistlib.loads(report.read_bytes());assert value['confirmed'] and value['pendingBefore']==1 and value['remaining']==0,value
                    rows.append({'mode':'original-copy-maintenance','result':value});checks+=1
                outcomes[name]=rows
            finally:
                if not identity_only and backup.exists():
                    if app.exists():shutil.rmtree(app)
                    shutil.copytree(backup,app)
                    run('/usr/bin/open','-g','-n','-W',app,'--args','clear',timeout=20)
        (ROOT/'build/qa/reminder-identity-regression.json').write_text(json.dumps({'checks':checks,'realNotifications':not identity_only,'scenarios':outcomes},indent=2))
    print(f'PASS: {checks} '+('code identity' if identity_only else 'real notification identity, isolation and maintenance')+' assertions; no alert/sound or production identity')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--identity-only',action='store_true');args=parser.parse_args();suite(args.identity_only)
