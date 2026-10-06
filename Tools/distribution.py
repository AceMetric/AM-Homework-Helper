"""Public distribution addresses, derived from the application configuration."""
import re
from urllib.parse import urlsplit


def update_locations(info):
    repository = info.get('DDLRepositoryURL', '')
    parsed = urlsplit(repository)
    parts = parsed.path.strip('/').split('/')
    if (parsed.scheme != 'https' or parsed.netloc != 'github.com'
            or parsed.query or parsed.fragment or len(parts) != 2
            or not re.fullmatch(r'[A-Za-z0-9-]+', parts[0])
            or not re.fullmatch(r'[A-Za-z0-9_.-]+', parts[1])
            or parts[1] in ('.', '..')
            or repository != f'https://github.com/{parts[0]}/{parts[1]}'):
        raise ValueError('公开仓库地址必须是无凭据、无查询参数的 GitHub HTTPS 仓库地址。')
    notes = f'https://{parts[0].lower()}.github.io/{parts[1]}/updates/'
    if info.get('SUFeedURL') != notes + 'appcast.xml':
        raise ValueError('应用更新源与公开仓库地址不一致。')
    version = info['CFBundleShortVersionString']
    if not re.fullmatch(r'\d+(?:\.\d+){1,2}', version):
        raise ValueError('发布版本必须是数字版本号。')
    return repository, f'{repository}/releases/download/v{version}/', notes
