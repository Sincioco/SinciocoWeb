"""Offline release-boundary tests. Synthetic tokens only; no network or upload."""
import copy
import importlib.util
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('release_gate', ROOT / 'check-release-gate.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
from deployment_lib import public_relative


class ReleaseBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.env = {'GITHUB_REPOSITORY':'Sincioco/SinciocoWeb', 'GITHUB_REF':'refs/heads/main',
                    'GITHUB_EVENT_NAME':'push', gate.SWITCH:'true'}
        self.event = {'repository':{'full_name':'Sincioco/SinciocoWeb','private':False,'visibility':'public'}}
        self.publications = []

    def mock_pipeline(self, require_secret=True):
        gate.validate_context(self.env, self.event, require_secret)
        self.publications.append('mock sincioco-free upload')

    def assert_blocked(self):
        with self.assertRaises(ValueError):
            self.mock_pipeline()
        self.assertEqual(self.publications, [])

    def test_missing_secret_stops_before_mock_upload(self):
        self.assert_blocked()
        self.env[gate.SECRET] = '  \n'
        self.assert_blocked()

    def test_explicitly_disabled_stops_even_with_synthetic_secret(self):
        self.env[gate.SECRET] = 'synthetic-test-value'
        for value in ('', 'false', 'TRUE'):
            with self.subTest(value=value):
                self.env[gate.SWITCH] = value
                self.assert_blocked()

    def test_no_pull_request_events(self):
        self.env[gate.SECRET] = 'synthetic-test-value'
        for value in ('pull_request','pull_request_target','workflow_run','repository_dispatch'):
            with self.subTest(event=value):
                self.env['GITHUB_EVENT_NAME'] = value
                self.assert_blocked()

    def test_wrong_branch_and_fork_are_refused(self):
        self.env[gate.SECRET] = 'synthetic-test-value'
        for value in ('refs/heads/feature','refs/pull/1/merge','refs/tags/main'):
            self.env['GITHUB_REF'] = value
            self.assert_blocked()
        self.env['GITHUB_REF'] = 'refs/heads/main'
        self.env['GITHUB_REPOSITORY'] = 'SomeoneElse/SinciocoWeb'
        self.assert_blocked()

    def test_private_unknown_and_malformed_visibility_fail_closed(self):
        self.env[gate.SECRET] = 'synthetic-test-value'
        original = copy.deepcopy(self.event)
        for private, visibility in [(True,'private'),(None,None),(False,None),('false','public')]:
            self.event['repository'].update(private=private,visibility=visibility)
            self.assert_blocked()
        self.event = original
        self.event['repository']['full_name'] = 'SomeoneElse/SinciocoWeb'
        self.assert_blocked()

    def test_public_main_push_and_manual_pass_with_synthetic_secret(self):
        self.env[gate.SECRET] = 'synthetic-test-value'
        for event in ('push','workflow_dispatch'):
            self.env['GITHUB_EVENT_NAME'] = event
            self.mock_pipeline()
        self.assertEqual(len(self.publications),2)

    def test_validation_never_requires_a_secret(self):
        gate.validate_context(self.env,self.event,False)
        self.assertNotIn(gate.SECRET,self.env)

    def test_only_expected_azure_application_result_passes(self):
        for value in (gate.EXPECTED_SITE_ORIGIN,gate.EXPECTED_SITE_ORIGIN+'/'):
            gate.validate_deployment_result(value)
        for value in ('', 'https://sincioco.com/', 'https://another.azurestaticapps.net/',
                      gate.EXPECTED_SITE_ORIGIN.replace('https:','http:'),
                      gate.EXPECTED_SITE_ORIGIN+':443/', gate.EXPECTED_SITE_ORIGIN+'/different',
                      gate.EXPECTED_SITE_ORIGIN+'/?query=1', gate.EXPECTED_SITE_ORIGIN+'/#hash',
                      gate.EXPECTED_SITE_ORIGIN.replace('https://','https://name:password@')):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    gate.validate_deployment_result(value)


class PublicationContractTests(unittest.TestCase):
    def test_private_paths_and_traversal_refused(self):
        for path in ['../Index.html','/Index.html','C:/secret.txt','Deployment/deployment.json',
                     '.github/static-site/prepare-site.py','.env','Images/../.env',
                     'Images/secret.key','diagnostics/result.json','node_modules/index.js',
                     'pages-migration-contract.json','Images/credentials.json']:
            with self.subTest(path=path):
                with self.assertRaises(ValueError):
                    public_relative(path)
        self.assertEqual(public_relative('smile2/examples/example.ps1').as_posix(),'smile2/examples/example.ps1')

    def test_exact_reviewed_main_only_allowlist(self):
        entries=json.loads((ROOT/'publish-files.json').read_text(encoding='utf-8-sig'))
        self.assertEqual(len(entries),359)
        self.assertTrue(all(entry['source']=='main' for entry in entries))
        paths=[public_relative(entry['deployed']).as_posix() for entry in entries]
        self.assertEqual(len({p.casefold() for p in paths}),len(paths))
        self.assertNotIn('sitemap-sinstar.xml',paths)
        self.assertEqual({p for p in paths if p.startswith('BookOne/')},
                         {'BookOne/index.html','BookOne/sw.js','BookOne/retire-legacy-workers.js'})
        self.assertFalse(any(p.startswith('SinStar/') or p.casefold().startswith('sinstar/bookone/') for p in paths))
        book_source='BookOne/index.html'
        book_outputs={book_source,'SinStar/BookOne/index.html'}
        book_entries=[entry for entry in entries if entry['deployed'] in book_outputs or entry['path'] in book_outputs]
        self.assertEqual(book_entries,[{'source':'main','path':book_source,'deployed':book_source}])
        self.assertIn('SinStar_Storyboard/index.html',paths)
        self.assertIn('wrapper-nav.js',paths)
        self.assertEqual(json.loads((ROOT/'sources.json').read_text()),{'main':'../..'})

    def test_native_auto_preserves_final_canonical_contract(self):
        config=json.loads((ROOT/'site-config/staticwebapp.config.json').read_text(encoding='utf-8-sig'))
        self.assertEqual(config.get('trailingSlash'),'auto')
        self.assertEqual(len(config['routes']),142)
        paths={rule['route'] for rule in config['routes']}
        self.assertTrue(paths.isdisjoint({'/AgenticAI','/Military','/Resume','/smile2'}))
        self.assertNotIn('navigationFallback',config)
        self.assertFalse(any('*' in path for path in paths))
        self.assertTrue(paths.isdisjoint({'/SinStar/BookOne','/SinStar/BookOne/'}))
        for folder in ('/BookOne','/SinStar_Storyboard'):
            self.assertTrue(paths.isdisjoint({folder,folder+'/',folder+'/index.html'}))

    def test_book_wrapper_migration_contract_preserves_legacy_assets(self):
        contract=json.loads((ROOT/'pages-migration-contract.json').read_text(encoding='utf-8-sig'))
        config=json.loads((ROOT/'site-config/staticwebapp.config.json').read_text(encoding='utf-8-sig'))
        book_pages='https://sincioco.github.io/SinStar_Audio_BookOne/'
        book_wrapper='https://sincioco.com/SinStar/BookOne/'
        self.assertEqual(contract['book_pages_url'],book_pages)
        self.assertEqual(contract['book_wrapper_url'],book_wrapper)
        self.assertEqual(contract['azure_origins'],['https://sincioco.com','https://www.sincioco.com'])
        self.assertEqual(contract['retirement_worker_paths'],['/BookOne/sw.js','/sinstar/novel/sw.js'])
        self.assertEqual(len(contract['wrappers']),3)
        expected_wrappers=[
            {'path':'SinStar/BookOne/index.html','source':'BookOne/index.html','canonical':book_pages},
            {'path':'BookOne/index.html','canonical':book_pages},
            {'path':'SinStar_Storyboard/index.html','canonical':'https://sincioco.github.io/SinStar_Storyboard/'},
        ]
        self.assertEqual(sorted(contract['wrappers'],key=lambda item:item['path']),
                         sorted(expected_wrappers,key=lambda item:item['path']))
        rules={rule['route']:rule for rule in config['routes']}
        self.assertEqual(len(rules),142)
        self.assertEqual(rules['/SinStar/BookOne/index.html'],
                         {'route':'/SinStar/BookOne/index.html','rewrite':'/BookOne/index.html'})
        self.assertEqual(rules['/sinstar/novel/index.html'],
                         {'route':'/sinstar/novel/index.html','redirect':book_wrapper,'statusCode':301})
        assets=contract['retired_reader_assets']
        self.assertEqual(len(assets),62)
        self.assertEqual(len(set(assets)),62)
        self.assertEqual(sum(asset.startswith('audio/') for asset in assets),43)
        targets=contract['reader_asset_targets']
        expected_targets={f'audio/{chapter:02d}.mp3':f'audio/{chapter:02d}-headings-v1.mp3' for chapter in range(42)}
        self.assertEqual(targets,expected_targets)
        self.assertEqual({asset for asset in assets if asset.startswith('audio/')},set(expected_targets)|{'audio/title.mp3'})
        current_targets=[targets.get(asset,asset) for asset in assets]
        self.assertEqual(len(set(current_targets)),62)
        self.assertIn('audio/title.mp3',current_targets)
        for asset in list(assets)+list(targets)+current_targets:
            self.assertRegex(asset,r'\A[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*\Z')
            self.assertTrue(set(asset.split('/')).isdisjoint({'.','..'}))
            self.assertEqual(public_relative(asset).as_posix(),asset)
        for prefix in ('/BookOne/','/sinstar/novel/'):
            for asset in assets:
                self.assertEqual(rules[prefix+asset],
                                 {'route':prefix+asset,'redirect':book_pages+targets.get(asset,asset),'statusCode':301})
        for path in contract['retirement_worker_paths']:
            self.assertEqual(rules[path],
                             {'route':path,'headers':{'Cache-Control':'no-cache, no-store, must-revalidate'}})

    def test_workflow_never_deploys_pull_requests_or_builds_repository_root(self):
        text=(ROOT.parent/'workflows/deploy-sincioco-free.yml').read_text()
        triggers=text.split('\npermissions:',1)[0]
        self.assertIn('branches: [main]',triggers)
        self.assertIn('workflow_dispatch:',triggers)
        self.assertNotRegex(triggers,r'(?m)^\s*(pull_request|pull_request_target|workflow_run|repository_dispatch):')
        self.assertIn("github.event.repository.private == false",text)
        self.assertIn("github.event.repository.visibility == 'public'",text)
        self.assertNotIn('ACTIONS_ZERO_PAID_USAGE_CONFIRMED',text)
        self.assertIn("vars.AZURE_SINCIOCO_FREE_DEPLOY_ENABLED == 'true'",text)
        self.assertIn('runs-on: ubuntu-24.04',text)
        self.assertIn('persist-credentials: false',text)
        self.assertIn('app_location: .github/static-site/website',text)
        for value in ['api_location: \'\'','output_location: \'\'','skip_app_build: true','skip_api_build: true','production_branch: main']:
            self.assertIn(value,text)
        for forbidden in ['pull-requests: write','contents: write','id-token:', 'repo_token:', 'deployment_environment:', 'continue-on-error:', 'upload-artifact@','actions/cache@']:
            self.assertNotIn(forbidden,text)
        pins=re.findall(r'uses: ([^\s#]+)',text)
        self.assertEqual(pins,[
            'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1',
            'Azure/static-web-apps-deploy@4d27395796ac319302594769cfe812bd207490b1'])
        self.assertLess(text.index('verify-stage.py'),text.index('Require the app-scoped deployment secret'))
        self.assertLess(text.index('--require-secret'),text.index('uses: Azure/static-web-apps-deploy@'))
        self.assertLess(text.index('uses: Azure/static-web-apps-deploy@'),text.index('--verify-deployment'))
        self.assertLess(text.index('--verify-deployment'),text.index('Verify-Live.ps1'))


def load_tests(loader, tests, pattern):
    # Run stdlib thumbnail failure cases as part of the existing pre-upload tests.
    path = ROOT.parents[1] / 'AgenticAI/tools/test-card-thumbnails.py'
    spec = importlib.util.spec_from_file_location('card_thumbnail_tests', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    tests.addTests(loader.loadTestsFromModule(module))
    return tests


if __name__ == '__main__':
    unittest.main(verbosity=2)
