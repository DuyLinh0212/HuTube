"""Catalog source bindings/routes, real OpenAPI operations and existing tests; no coverage claims."""
import argparse
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
WEB = {
    'auth': 'AUTH', 'account': 'U-ACCOUNT', 'channel': 'U-CHANNEL', 'home': 'U-DISCOVERY',
    'explore': 'U-DISCOVERY', 'subscriptions': 'U-SUBSCRIPTION', 'playlists': 'U-PLAYLIST',
    'video': 'U-WATCH', 'policy': 'U-POLICY', 'plans': 'U-PLAN', 'library': 'U-LIBRARY',
    'studio': 'U-STUDIO', 'users': 'A-USERS', 'channels': 'A-CHANNELS', 'videos': 'A-VIDEOS',
    'rbac': 'A-RBAC', 'moderation': 'A-MODERATION', 'topics': 'A-TOPICS',
    'cf-seeder': 'A-CF', 'recommendations': 'A-RECOMMENDATION', 'policies': 'A-POLICY',
    'error': 'X-ACCESS',
}
API = {'Auth': 'B-AUTH', 'Account': 'B-ACCOUNT', 'Channel': 'B-CHANNEL', 'Videos': 'B-VIDEO',
       'Comments': 'B-COMMENT', 'Feed': 'B-FEED', 'Library': 'B-LIBRARY', 'Playlist': 'B-PLAYLIST',
       'Plans': 'B-PLAN', 'Payments': 'B-PAYMENT', 'Notifications': 'B-NOTIFICATION',
       'UserModeration': 'B-MODERATION', 'Policy': 'B-TAXONOMY', 'Categories': 'B-TAXONOMY',
       'ViolationTypes': 'B-TAXONOMY', 'Downloads': 'B-DOWNLOAD', 'Subscriptions': 'B-SUBSCRIPTION',
       'CfSeeder': 'B-CF', 'RecommendationAdmin': 'B-RECOMMENDATION', 'Admin': 'B-ADMIN',
       'HuTube.Api': 'B-SYSTEM'}


def write(name, value):
    (ROOT / 'coverage' / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def web():
    routes, actions, navigation, controls, excluded = [], [], [], [], []
    for app in ('user', 'admin'):
        base = REPO / f'frontend/{app}-web/src/app'
        source = (base / 'app.routes.ts').read_text(encoding='utf-8')
        studio_start = source.find("path: 'studio'")
        for match in re.finditer(r"path:\s*'([^']*)'", source):
            literal = match.group(1)
            expanded = 'studio/' + literal if app == 'user' and studio_start >= 0 and match.start() > studio_start and literal != '**' else literal
            routes.append({'app': app, 'literal': literal, 'path': '/' + expanded,
                           'conditional': literal == 'register' and app == 'admin',
                           'source': str((base / 'app.routes.ts').relative_to(REPO)).replace('\\', '/'),
                           'line': source[:match.start()].count('\n') + 1, 'scenario': 'X-ROUTES'})
        for path in sorted(base.rglob('*')):
            if path.suffix not in ('.html', '.ts') or path.name.endswith('.spec.ts'):
                continue
            relative = path.relative_to(base)
            if 'upload copy' in relative.parts:
                excluded.append(str(path.relative_to(REPO)).replace('\\', '/')); continue
            content = path.read_text(encoding='utf-8')
            feature = relative.parts[1] if len(relative.parts) > 2 and relative.parts[0] == 'features' else None
            scenario = WEB.get(feature, 'X-SHELL')
            if app == 'admin' and feature in ('account', 'plans'):
                scenario = 'A-' + feature.upper()
            # Inline templates are included. A binding is a planning obligation, not a passing test.
            for match in re.finditer(r'\(([\w.:-]+)\)\s*=\s*([\"\'])(.*?)\2', content, re.S):
                actions.append({'app': app, 'event': match.group(1), 'expression': match.group(3),
                                'source': str(path.relative_to(REPO)).replace('\\', '/'),
                                'line': content[:match.start()].count('\n') + 1,
                                'scenario': scenario, 'status': 'PLANNED'})
            for match in re.finditer(r'(\[?routerLink\]?|\[?(?:attr\.)?href\]?)\s*=\s*([\"\'])(.*?)\2', content, re.S):
                navigation.append({'app': app, 'attribute': match.group(1), 'expression': match.group(3),
                                   'source': str(path.relative_to(REPO)).replace('\\', '/'),
                                   'line': content[:match.start()].count('\n') + 1,
                                   'scenario': scenario, 'status': 'PLANNED'})
            for match in re.finditer(r'<(input|textarea|select)\b([^>]*?)>', content, re.S):
                controls.append({'app': app, 'element': match.group(1), 'attributes': match.group(2).strip(),
                                 'source': str(path.relative_to(REPO)).replace('\\', '/'),
                                 'line': content[:match.start()].count('\n') + 1,
                                 'scenario': scenario, 'status': 'PLANNED'})
    write('web-inventory.json', {'routes': routes, 'bindings': actions, 'navigation': navigation,
                                'form_controls': controls, 'excluded_unrouted_copy_files': excluded,
                                'note': 'Lexical inventory: inspect route guards and dynamic UI branches manually too.'})
    print('Navigation references/form controls:', len(navigation), len(controls))
    return len(routes), len(actions)


def backend(openapi):
    schema = json.loads(openapi.read_text(encoding='utf-8'))
    operations = []
    for path, item in sorted(schema['paths'].items()):
        for method, operation in sorted(item.items()):
            if method not in ('get', 'post', 'put', 'patch', 'delete', 'head', 'options'):
                continue
            tags = operation.get('tags', ['HuTube.Api'])
            if tags[0] not in API:
                raise ValueError('Unmapped API tag: ' + tags[0])
            operations.append({'method': method.upper(), 'path': path, 'tags': tags,
                               'scenario': API[tags[0]], 'status': 'PLANNED',
                               'required_variants': ['success', 'input-boundaries', 'authorization-as-applicable',
                                                     'not-found-as-applicable', 'repeat-or-concurrency-as-applicable']})
    write('backend-endpoints.json', {'source': 'Real local /openapi/v1.json', 'operations': operations,
                                    'outside_openapi': ['/hubs/notifications (negotiate/connect/events)',
                                                        '/openapi/v1.json', 'Development Swagger UI', 'background workers']})
    return Counter(op['tags'][0] for op in operations)


def existing_tests():
    tests = []
    for path in sorted((REPO / 'backend/tests').rglob('*Tests.cs')):
        content = path.read_text(encoding='utf-8')
        for match in re.finditer(r'\[(Fact|Theory)(?:\([^\]]*\))?\](.*?)(?=\[(?:Fact|Theory)(?:\(|\])|\Z)', content, re.S):
            name = re.search(r'public\s+(?:async\s+)?(?:Task(?:<[^>]+>)?|void)\s+(\w+)\s*\(', match.group(2))
            if name:
                tests.append({'project': path.parent.name, 'file': str(path.relative_to(REPO)).replace('\\', '/'),
                              'method': name.group(1), 'kind': match.group(1),
                              'inline_data_rows': len(re.findall(r'\[InlineData\(', match.group(2)))})
    python = []
    for path in sorted((REPO / 'recommendation-service/tests').glob('test_*.py')):
        for name in re.findall(r'^\s*(?:async\s+)?def (test_\w+)\(', path.read_text(encoding='utf-8'), re.M):
            python.append({'file': str(path.relative_to(REPO)).replace('\\', '/'), 'method': name})
    write('existing-tests.json', {'dotnet': tests, 'recommendation_python': python,
                                 'note': 'Method inventory, not expanded execution count or assertion/branch coverage.'})
    return Counter(test['project'] for test in tests), len(python)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--openapi', type=Path, required=True)
    args = parser.parse_args()
    print('Web routes/bindings:', web())
    print('API operations:', dict(backend(args.openapi)))
    print('Existing test methods:', existing_tests())
