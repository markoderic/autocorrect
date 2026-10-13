"""Release orchestration checks with fake signing services; never submits software."""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
IDENTITY = 'Developer ID Application: Test Developer (TESTTEAM)'


@unittest.skipUnless(Path('/usr/libexec/PlistBuddy').exists(), 'macOS packaging tools required')
class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='autocorrect release tests ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root / 'scripts').mkdir()
        (self.root / 'Resources').mkdir()
        (self.root / 'bin').mkdir()
        shutil.copy(ROOT / 'scripts/release.sh', self.root / 'scripts/release.sh')
        with (self.root / 'Resources/Info.plist').open('wb') as f:
            plistlib.dump({'CFBundleShortVersionString': '9.8.7'}, f)
        self.script('bin/security', 'printf \'  1) HASH "%s"\\n\' "$TEST_IDENTITY"\n')
        self.script('bin/xcrun', 'echo "$*" >> "$TEST_ROOT/notary-calls"\nexit "${TEST_AUTH_EXIT:-0}"\n')
        self.script('scripts/build.sh', 'mkdir -p "$DIST_DIR"\nprintf "%s\\n%s\\n" "$VERSION" "$DIST_DIR" > "$TEST_ROOT/build-call"\nprintf "checksum\\n" > "$DIST_DIR/AutoCorrect-$VERSION-universal.zip.sha256"\n')
        self.script('scripts/notarize.sh', 'printf "%s\\n" "$DIST_DIR" > "$TEST_ROOT/notarize-call"\n')
        self.env = {key: value for key, value in os.environ.items()
                    if key not in ('VERSION', 'DIST_DIR', 'SIGNING_IDENTITY', 'NOTARY_PROFILE', 'RELEASE_CHANNEL')}
        self.env.update(PATH=str(self.root / 'bin') + ':' + os.environ['PATH'],
                        TEST_ROOT=str(self.root), TEST_IDENTITY=IDENTITY,
                        SIGNING_IDENTITY=IDENTITY, NOTARY_PROFILE='test-profile')

    def script(self, name, body):
        path = self.root / name
        path.write_text('#!/bin/bash\nset -eu\n' + body)
        path.chmod(0o755)

    def run_release(self, *args, **env):
        return subprocess.run(['bash', str(self.root / 'scripts/release.sh'), *args],
                              cwd=self.root, env=self.env | env, capture_output=True, text=True)

    def test_check_authenticates_without_building(self):
        result = self.run_release('--check')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('version 9.8.7', result.stdout)
        self.assertIn('notarytool history', (self.root / 'notary-calls').read_text())
        self.assertFalse((self.root / 'build-call').exists())
        self.assertFalse((self.root / 'notarize-call').exists())

    def test_rejects_development_missing_identity_and_bad_credentials_before_build(self):
        for overrides in [dict(SIGNING_IDENTITY='Apple Development: Test'),
                          dict(TEST_IDENTITY=IDENTITY + ' Other'), dict(NOTARY_PROFILE=''),
                          dict(TEST_AUTH_EXIT='1')]:
            with self.subTest(overrides=overrides):
                result = self.run_release(**overrides)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.root / 'build-call').exists())

    def test_stable_uses_same_custom_output_and_version_for_both_steps(self):
        result = self.run_release(DIST_DIR='custom output', VERSION='1.0.0')
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = str(self.root / 'custom output')
        self.assertEqual((self.root / 'build-call').read_text(), '1.0.0\n' + expected + '\n')
        self.assertEqual((self.root / 'notarize-call').read_text(), expected + '\n')
        self.assertIn('checksum', result.stdout)

    def test_preview_does_not_authenticate_or_notarize(self):
        result = self.run_release(RELEASE_CHANNEL='preview', SIGNING_IDENTITY='-', NOTARY_PROFILE='')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / 'build-call').exists())
        self.assertFalse((self.root / 'notary-calls').exists())
        self.assertFalse((self.root / 'notarize-call').exists())

    def test_bad_arguments_channel_and_version_fail_before_build(self):
        for args, env in [(('--unknown',), {}), ((), {'RELEASE_CHANNEL': 'typo'}),
                          ((), {'VERSION': '../bad'})]:
            with self.subTest(args=args, env=env):
                self.assertNotEqual(self.run_release(*args, **env).returncode, 0)
                self.assertFalse((self.root / 'build-call').exists())

    def test_notarize_reads_custom_bundle_instead_of_default(self):
        # Stop at codesign; verify the real script selected the requested bundle.
        shutil.copy(ROOT / 'scripts/notarize.sh', self.root / 'scripts/notarize.sh')
        custom = self.root / 'custom output/AutoCorrect.app/Contents'
        custom.mkdir(parents=True)
        shutil.copy(self.root / 'Resources/Info.plist', custom / 'Info.plist')
        self.script('bin/codesign', 'echo "fixture-stop" >&2\nexit 42\n')
        result = subprocess.run(['bash', str(self.root / 'scripts/notarize.sh')], cwd=self.root,
                                env=self.env | {'DIST_DIR': 'custom output'}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 42, result.stderr)
        self.assertIn('fixture-stop', result.stderr)
        self.assertTrue((custom / 'Info.plist').exists())
        self.assertFalse((self.root / 'notary-calls').exists())


if __name__ == '__main__':
    unittest.main()
