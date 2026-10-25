import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import mobile_release as release

class ReleaseTest(unittest.TestCase):
    def inputs(self, **overrides):
        return dict(environment='prod', platform='both', version_mode='keep', version='',
                    source_sha='a'*40, run_id=42, repository='Palladin-io/palladin-flutter-mobile', **overrides)

    def test_version_modes(self):
        for mode, expected in [('keep','1.2.3'),('patch','1.2.4'),('minor','1.3.0'),('major','2.0.0')]:
            self.assertEqual(release.resolve_version('1.2.3',mode,''),expected)
        self.assertEqual(release.resolve_version('1.2.3','manual','1.2.3'),'1.2.3')

    def test_bad_versions(self):
        for value in ['01.2.3','1.2','1.2.3-beta','1.2.2','1.2.4\n','$(whoami)']:
            with self.subTest(value=value), self.assertRaises(ValueError):
                release.resolve_version('1.2.3','manual',value)
        with self.assertRaises(ValueError): release.resolve_version('1.2.3','patch','2.0.0')

    def test_ios_bounds(self):
        self.assertEqual(release.ios_build(1),'1.0.1')
        self.assertEqual(release.ios_build(9999),'1.99.99')
        self.assertEqual(release.ios_build(10000),'2.0.0')
        self.assertEqual(release.ios_build(99989999),'9999.99.99')
        for value in [0,99990000,-1,True]:
            with self.assertRaises(ValueError): release.ios_build(value)

    def test_reservations_survive_failures_and_reruns(self):
        first=release.reserve_record(self.inputs(),[],10,'0.1.0')
        self.assertEqual(first['sequence'],11)
        self.assertEqual(first['bundle_id'],'io.palladin.mobile')
        self.assertEqual(release.reserve_record(self.inputs(),[first],10,'0.1.0'), first)
        changed=self.inputs(); changed['platform']='android'
        with self.assertRaises(ValueError): release.reserve_record(changed,[first],10,'0.1.0')
        changed=self.inputs(); changed['run_id']=43; changed['version_mode']='minor'
        second=release.reserve_record(changed,[first],10,'0.1.0')
        self.assertEqual((second['sequence'],second['marketing_version']),(12,'0.2.0'))

    def test_staging_has_separate_version_and_identity(self):
        first=release.reserve_record(self.inputs(),[],0,'1.2.3')
        inputs=self.inputs(); inputs.update(environment='stg',run_id=43)
        second=release.reserve_record(inputs,[first],0,'0.1.0')
        self.assertEqual(second['marketing_version'],'0.1.0')
        self.assertEqual(second['bundle_id'],'io.palladin.mobile.staging')

    def test_manifest_binds_bytes_and_identity(self):
        record=release.reserve_record(self.inputs(),[],0,'0.1.0')
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); (root/'app.aab').write_bytes(b'signed artifact')
            manifest=release.create_manifest(record,root/'app.aab','android')
            release.verify_manifest(record,manifest,root,'android')
            for field,value in [('environment','stg'),('run_id',99),('source_sha','b'*40)]:
                wrong=dict(manifest); wrong[field]=value
                with self.subTest(field=field),self.assertRaises(ValueError):
                    release.verify_manifest(record,wrong,root,'android')
            (root/'app.aab').write_bytes(b'changed')
            with self.assertRaises(ValueError): release.verify_manifest(record,manifest,root,'android')

    def test_manifest_rejects_path_escape_and_symlink(self):
        record=release.reserve_record(self.inputs(),[],0,'0.1.0')
        with tempfile.TemporaryDirectory() as d:
            root=Path(d); (root/'app.aab').write_bytes(b'a')
            manifest=release.create_manifest(record,root/'app.aab','android')
            manifest['artifact']['name']='../app.aab'
            with self.assertRaises(ValueError): release.verify_manifest(record,manifest,root,'android')

    def test_original_run_must_be_main_dispatch_from_expected_workflow(self):
        run={'id':42,'head_sha':'a'*40,'head_branch':'main','event':'workflow_dispatch',
             'workflow_id':123,'repository':{'full_name':'Palladin-io/palladin-flutter-mobile'}}
        record=release.reserve_record(self.inputs(),[],0,'0.1.0')
        release.validate_run(run,record,123,'prod','android')
        for field,value in [('event','pull_request'),('head_branch','evil'),('workflow_id',999),('head_sha','b'*40)]:
            with self.subTest(field=field),self.assertRaises(ValueError):
                release.validate_run(dict(run,**{field:value}),record,123,'prod','android')
        with self.assertRaises(ValueError): release.validate_run(run,record,123,'stg','ios')
