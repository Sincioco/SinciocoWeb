"""Fail closed before publishing; never print or persist a deployment token."""
import argparse
import json
import os
from pathlib import Path
import sys
from urllib.parse import urlsplit

REPOSITORY = 'Sincioco/SinciocoWeb'
BRANCH = 'refs/heads/main'
SWITCH = 'AZURE_SINCIOCO_FREE_DEPLOY_ENABLED'
SECRET = 'AZURE_STATIC_WEB_APPS_API_TOKEN_SINCIOCO_FREE'
EXPECTED_SITE_ORIGIN = 'https://black-tree-0f54e0110.1.azurestaticapps.net'


def validate_context(environment, event, require_secret=False):
    if environment.get('GITHUB_REPOSITORY') != REPOSITORY:
        raise ValueError('Only the approved Sincioco/SinciocoWeb repository may publish.')
    if environment.get('GITHUB_REF') != BRANCH:
        raise ValueError('Only refs/heads/main may publish.')
    if environment.get('GITHUB_EVENT_NAME') not in ('push', 'workflow_dispatch'):
        raise ValueError('Only main push or manual main events may publish; PR events are refused.')
    repository = event.get('repository', {})
    if repository.get('full_name') != REPOSITORY:
        raise ValueError('Event repository does not match the approved repository.')
    if repository.get('private') is not False or repository.get('visibility') != 'public':
        raise ValueError('Hosted execution requires verified public repository visibility.')
    if environment.get(SWITCH) != 'true':
        raise ValueError('Deployment is disabled until the authorized secure handoff is complete.')
    if require_secret and not environment.get(SECRET, '').strip():
        raise ValueError('Missing app-scoped GitHub Actions secret ' + SECRET + '; nothing was deployed.')


def validate_deployment_result(value):
    parsed = urlsplit(value)
    expected = urlsplit(EXPECTED_SITE_ORIGIN)
    if (parsed.scheme != 'https' or parsed.netloc != expected.netloc or
            parsed.path not in ('','/') or parsed.query or parsed.fragment):
        raise ValueError('Azure did not report the expected sincioco-free application URL; investigate without automatic retry.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require-secret', action='store_true')
    parser.add_argument('--verify-deployment', action='store_true')
    args = parser.parse_args()
    try:
        if sys.version_info < (3, 12):
            raise ValueError('Python 3.12 or newer is required; do not install unreviewed dependencies.')
        event_file = os.environ.get('GITHUB_EVENT_PATH')
        if not event_file:
            raise ValueError('GitHub event metadata is required.')
        event = json.loads(Path(event_file).read_text(encoding='utf-8'))
        validate_context(os.environ, event, args.require_secret)
        if args.verify_deployment:
            validate_deployment_result(os.environ.get('SWA_DEPLOYED_SITE_URL',''))
    except (ValueError, OSError, TypeError) as error:
        print('Release gate failed: ' + str(error), file=sys.stderr)
        return 1
    print('Release gate passed for the approved public repository and main branch.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
