#!/usr/bin/env python3
"""Only public OAuth and legacy GitHub App identities are eligible for packaging."""
import plistlib
import re
import sys
from pathlib import Path
configuration = plistlib.loads(Path(sys.argv[1]).read_bytes())
if set(configuration) not in ({'clientID', 'installationURL'}, {'clientID', 'installationURL', 'oauthClientID'}):
    raise SystemExit('Config must contain only public clientID, installationURL and optional oauthClientID')
client = configuration['clientID']
url = configuration['installationURL']
if not isinstance(client, str) or not isinstance(url, str):
    raise SystemExit('Public configuration must be strings')
if client or url:
    if not re.fullmatch(r'Iv[A-Za-z0-9.]{10,80}', client):
        raise SystemExit('Use a public GitHub App Client ID, never a token or Client Secret')
    if not re.fullmatch(r'https://github\.com/apps/[a-z0-9-]+/installations/new', url):
        raise SystemExit('Installation URL must be an official GitHub App page')
oauth = configuration.get('oauthClientID', '')
if oauth and (not isinstance(oauth, str) or not re.fullmatch(r'Ov[A-Za-z0-9.]{10,80}', oauth)):
    raise SystemExit('Use only a public OAuth Client ID')
bundle = Path(sys.argv[2])
info = plistlib.loads(bundle.read_bytes())
info.update(SSGitHubClientID=client, SSGitHubInstallationURL=url, SSOAuthClientID=oauth)
bundle.write_bytes(plistlib.dumps(info))
