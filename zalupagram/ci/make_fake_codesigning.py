#!/usr/bin/env python3
# ZalupaGram: fake codesigning for our own bundle id.
#
# build-system/fake-codesigning has self-signed profiles for ph.telegra.Telegraph.
# The IPA is re-signed by AltStore/SideStore anyway, so we only need profiles
# that Bazel accepts: copy them, swap the bundle id inside and sign them again
# with the same self-signed certificate. Runs on macOS (security, plutil).

import argparse
import base64
import datetime
import os
import plistlib
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'build-system', 'Make'))

from BuildEnvironment import run_executable_with_output
import GenerateProfiles

OFFICIAL_BUNDLE_ID = 'ph.telegra.Telegraph'


def make_profile(source, destination, bundle_id, certificate_data, signing_identity, keychain_name):
    parsed = run_executable_with_output('security', arguments=['cms', '-D', '-i', source], check_result=True)
    parsed = parsed.replace(OFFICIAL_BUNDLE_ID, bundle_id)
    # The upstream profiles expire, extend them.
    profile = plistlib.loads(parsed.encode('utf-8'))
    profile['CreationDate'] = datetime.datetime(2026, 1, 1)
    profile['ExpirationDate'] = datetime.datetime(2036, 1, 1)
    # Same as GenerateProfiles.process_provisioning_profile, which takes
    # a signed profile: put our certificate in and sign the plist again.
    profile['DeveloperCertificates'] = [base64.b64decode(certificate_data)]
    profile.pop('DER-Encoded-Profile', None)
    fd, temp_path = tempfile.mkstemp(suffix='.plist')
    os.close(fd)
    with open(temp_path, 'wb') as file:
        plistlib.dump(profile, file)
    try:
        run_executable_with_output('security', arguments=[
            'cms', '-S', '-k', keychain_name, '-N', signing_identity,
            '-i', temp_path, '-o', destination
        ], check_result=True)
    finally:
        os.unlink(temp_path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', required=True, help='build-system/fake-codesigning')
    parser.add_argument('--destination', required=True)
    parser.add_argument('--bundleId', required=True)
    args = parser.parse_args()

    if os.path.exists(args.destination):
        shutil.rmtree(args.destination)
    os.makedirs(args.destination + '/profiles')
    shutil.copytree(args.source + '/certs', args.destination + '/certs')

    p12_path = args.source + '/certs/SelfSigned.p12'
    certificate_data = GenerateProfiles.get_certificate_base64_from_p12(p12_path, '')
    signing_identity = GenerateProfiles.get_signing_identity_from_p12(p12_path, '')
    if not signing_identity:
        print('Could not extract signing identity from {}'.format(p12_path))
        sys.exit(1)

    keychain_name = GenerateProfiles.setup_temp_keychain(p12_path, '')
    try:
        for file_name in sorted(os.listdir(args.source + '/profiles')):
            if not file_name.endswith('.mobileprovision'):
                continue
            print('Profile {}'.format(file_name))
            make_profile(
                source=args.source + '/profiles/' + file_name,
                destination=args.destination + '/profiles/' + file_name,
                bundle_id=args.bundleId,
                certificate_data=certificate_data,
                signing_identity=signing_identity,
                keychain_name=keychain_name)
    finally:
        GenerateProfiles.cleanup_temp_keychain(keychain_name)


if __name__ == '__main__':
    main()
