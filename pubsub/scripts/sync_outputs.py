#!/usr/bin/env python3

import rclone
import os
import sys
import argparse


DEFAULT_S3_BUCKET = 'gossipsub-test-outputs'
DEFAULT_REGION = 'eu-central-1'
RCLONE_CONFIG_TEMPLATE = """
[s3]
type = s3
provider = AWS
env_auth = true
region = {region}
location_constraint = "{region}"
acl = public-read
"""


def rclone_config(region):
    return RCLONE_CONFIG_TEMPLATE.format(region=region)


class OutputSyncer(object):
    def __init__(self, region=DEFAULT_REGION, bucket=DEFAULT_S3_BUCKET):
        self.config = rclone_config(region)
        self.bucket = bucket
        self._ensure_rclone_exists()

    def _ensure_rclone_exists(self):
        result = rclone.with_config(self.config).listremotes()
        if result['code'] == -20:
            raise EnvironmentError("the 'rclone' command must be present on the $PATH")

    def list_outputs(self):
        path = 's3:/{}/'.format(self.bucket)
        result = rclone.with_config(self.config).run_cmd('lsd', [path])
        if result['code'] != 0:
            raise ValueError('failed to list output bucket: {}'.format(result))
        out = result['out'].decode('utf8')
        dirs = []
        for line in out.splitlines():
            name = line.split()[-1]
            dirs.append(name)
        return dirs

    def fetch(self, name, dest_dir):
        src = 's3:/{}/{}'.format(self.bucket, name)
        dest = os.path.join(dest_dir, name)
        result = rclone.with_config(self.config).sync(src, dest)
        if result['code'] != 0:
            print('error fetching {}: {}'.format(name, result['error']), file=sys.stderr)

    def fetch_all(self, dest_dir):
        src = 's3:/{}/'.format(self.bucket)
        result = rclone.with_config(self.config).sync(src, dest_dir)
        if result['code'] != 0:
            print('error fetching all test outputs: {}'.format(result['error']), file=sys.stderr)

    def store_single(self, test_run_dir):
        """
        :param test_run_dir: path to local dir containing a single test run output, e.g. ./output/pubsub-test-20200409-152658
        """
        name = os.path.basename(test_run_dir)
        dest = 's3:/{}/{}'.format(self.bucket, name)
        result = rclone.with_config(self.config).sync(test_run_dir, dest)
        if result['code'] != 0:
            print('error storing {}: {}'.format(name, result['error']), file=sys.stderr)

    def store_all(self, src_dir, ignore=[]):
        """
        :param src_dir: path to local dir containing multiple test run dirs, e.g. ./output
        :param ignore: list of subdirectories to ignore
        """
        for f in os.listdir(src_dir):
            if f in ignore:
                continue
            src = os.path.join(src_dir, f)
            dest = 's3:/{}/{}'.format(self.bucket, f)

            print('syncing {} to {}'.format(src, dest))
            result = rclone.with_config(self.config).sync(src, dest)
            if result['code'] != 0:
                print('error storing {}: {}'.format(f, result['error']), file=sys.stderr)


def parse_args():
    parser = argparse.ArgumentParser(description="sync test outputs to/from an s3 bucket")
    parser.add_argument('--region', default=DEFAULT_REGION, help='AWS region containing test output bucket')
    parser.add_argument('--bucket', default=DEFAULT_S3_BUCKET, help='name of s3 bucket to store and fetch test outputs')

    commands = parser.add_subparsers()
    ls_cmd = commands.add_parser('list', aliases=['ls'], help='list test outputs in the s3 bucket')
    ls_cmd.set_defaults(subcommand='list')

    fetch_cmd = commands.add_parser('fetch', help='fetch one or more named test outputs from the s3 bucket')
    fetch_cmd.set_defaults(subcommand='fetch')
    fetch_cmd.add_argument('names', nargs='+', help='name of a test output directory to fetch')
    fetch_cmd.add_argument('--dest', default='./output', help='directory to store fetched test output')

    fetch_all_cmd = commands.add_parser('fetch-all', help='fetch all test outputs from the s3 bucket to a local dir')
    fetch_all_cmd.set_defaults(subcommand='fetch-all')
    fetch_all_cmd.add_argument('dest', help='directory to store fetched test output')

    store_cmd = commands.add_parser('store', help='store one or more test outputs in s3')
    store_cmd.set_defaults(subcommand='store')
    store_cmd.add_argument('paths', nargs='+', help='path to a test output directory to store')

    store_all_cmd = commands.add_parser('store-all', help='send all test outputs in a directory to s3')
    store_all_cmd.set_defaults(subcommand='store-all')
    store_all_cmd.set_defaults(ignore=['failed'])
    store_all_cmd.add_argument('dir', help='local dir containing test output directories')
    store_all_cmd.add_argument('--ignore', help='subdirectory to ignore (e.g. failed outputs)',
                               action='append')

    return parser.parse_args()


def run():
    args = parse_args()

    syncer = OutputSyncer(region=args.region, bucket=args.bucket)
    if args.subcommand == 'list':
        outputs = syncer.list_outputs()
        print('\n'.join(outputs))
        return

    if args.subcommand == 'fetch':
        dest_dir = args.dest
        for name in args.names:
            print('fetching {} from s3://{} to {}'.format(name, args.bucket, dest_dir))
            syncer.fetch(name, dest_dir)
        return

    if args.subcommand == 'fetch-all':
        dest_dir = args.dest
        print('fetching all test outputs from s3://{}'.format(args.bucket))
        syncer.fetch_all(dest_dir)
        return

    if args.subcommand == 'store':
        for p in args.paths:
            print('syncing {} to s3://{}'.format(p, args.bucket))
            syncer.store_single(p)
        return

    if args.subcommand == 'store-all':
        print('syncing all subdirs of {} to s3://{} - excluding {}'.format(args.dir, args.bucket, args.ignore))
        syncer.store_all(args.dir, ignore=args.ignore)


if __name__ == '__main__':
    run()
