#!/usr/bin/env python3
# -*- coding: utf-8 -*-
""" librados python client - test io
"""

import time
import datetime
import getopt
import os
import os.path
import sys
import glob
import logging
import rados
from rados import LIBRADOS_ALL_NSPACES
import signal
import csv
from collections import namedtuple
# import hashlib
#from kafka import KafkaConsumer
from timeit import default_timer as timer

XATTRS = {
        'author': 'Piers Harding',
        'date': datetime.datetime.now().strftime("%I:%M%p on %B %d, %Y"),
    }


def timeit(method):
    """ Timing decorator for method run times
    """
    def timed(*this_args, **kw):
        """ inner decorator function
        """
        time_start = time.time()
        result = method(*this_args, **kw)
        time_end = time.time()

        logging.debug('%r (%r, %r) %3.3f sec',
                      method.__name__, this_args, kw, time_end - time_start)
        return result
    return timed


def parse_opts():
    """ Parse out the command line options
    """
    options = {
        'ceph_conf': "/etc/ceph/ceph.conf",
        'pool': "scbench",
        'namespace': "ns1",
        'object_prefix': "rados_test_",
        'input_dir': "/tmp/rados_input",
        'output_dir': "/tmp/rados_output",
        'csv_file': '/tmp/rados_times.csv',
        'buf': 1024 * 1024,
        'debug': False,
        'write': False,
        'read': False
    }

    try:
        (opts, _) = getopt.getopt(sys.argv[1:],
                                  'dnrwc:p:o:i:u:z:b:',
                                  ["debug",
                                   # "nofiles",
                                   "ceph_conf=",
                                   "pool=",
                                   "namespace=",
                                   "object_prefix=",
                                   "input_dir=",
                                   "output_dir=",
                                   "csv_file=",
                                   "buf"])
    except getopt.GetoptError:
        print('rados_client.py [-d -r -w -c <ceph_conf> -p <pool> ' +
              '-n <namespace> -o <object_prefix> -b <buffer length>' +
              '-i <input_dir> -u <output_dir> ' +
              '-z <csv_file>]')
        sys.exit(2)

    dopts = {}
    for (key, value) in opts:
        dopts[key] = value
    if '-c' in dopts:
        options['ceph_conf'] = dopts['-c']
    if '-p' in dopts:
        options['pool'] = dopts['-p']
    if '-n' in dopts:
        options['namespace'] = dopts['-n']
    if '-o' in dopts:
        options['object_prefix'] = dopts['-o']
    if '-i' in dopts:
        options['input_dir'] = dopts['-i']
    if '-u' in dopts:
        options['output_dir'] = dopts['-u']
    if '-z' in dopts:
        options['csv_file'] = dopts['-z']
    if '-b' in dopts:
        options['buf'] = int(dopts['-b'])
    if '-d' in dopts:
        options['debug'] = True
    if '-r' in dopts:
        options['read'] = True
    if '-w' in dopts:
        options['write'] = True

    # container class for options parameters
    option = namedtuple('option', options.keys())
    return option(**options)


def purge_output_dir(output_dir):
    """ purge output directory
    """
    if os.path.exists(output_dir):
        for root, dirs, files in os.walk(output_dir, topdown=False):
            for name in files:
                os.remove(os.path.join(root, name))
            for name in dirs:
                os.rmdir(os.path.join(root, name))
    else:
        os.mkdir(output_dir)

def read_in_chunks(f, chunk_size=1024*1024):
    """Lazy function (generator) to read a file piece by piece.
    Default chunk size: 1MB."""
    f = open(f)
    while True:
        data = f.read(chunk_size)
        if not data:
            break
        yield data


def get_files(input_dir):
    """ walk directory for file names
    """
    files = []
    if os.path.exists(input_dir):
        for root, dirs, files in os.walk(input_dir, topdown=False):
            for name in files:
                files.append(os.path.join(root, name))
    else:
        os.mkdir(input_dir)
    return files

# main
def main():
    """ Main
    """
    options = parse_opts()

    # setup logging
    logging.basicConfig(level=(logging.DEBUG if options.debug
                               else logging.INFO),
                        format=('%(asctime)s [%(name)s] ' +
                                '%(levelname)s: %(message)s'))
    logging.info('input: %s output: %s ', options.input_dir, options.output_dir)
    logging.info('pool is: %s object prefix: %s ', options.pool, options.object_prefix)

    purge_output_dir(options.output_dir)

    cluster = rados.Rados(conffile=options.ceph_conf)
    ioctx = cluster.open_ioctx(options.pool)
    # ioctx.set_namespace(LIBRADOS_ALL_NSPACES)
    ioctx.set_namespace(options.namespace)

    logging.info('client connected to pool: %s ', options.pool)

    # trap the keyboard interrupt
    def signal_handler(signal_caught, frame):
        """ Catch the keyboard interrupt and gracefully exit
        """
        logging.info('You pressed Ctrl+C!: %s/%s', signal_caught, frame)
        ioctx.close()
        cluster.shutdown()
        sys.exit(0)

    signal.signal(signal.SIGINT, signal_handler)

    # record batches - once all segments are retrieved then reconstruct
    #   the entire message and apply the checksum
    batches = {}

    # write timing results out to a CSV file
    with open(options.csv_file, 'w', newline='') as csvfile:
        csvwriter = csv.writer(csvfile, delimiter=',',
                               quotechar='"', quoting=csv.QUOTE_MINIMAL)
        csvwriter.writerow(['uuid', 'md5checksum',
                            'file_checksum', 'OK', 'datalen',
                            'segs', 'time'])

        # if we are writing objects to storage
        if options.write:

            # find input files
            files = get_files(options.input_dir)
            logging.info('files to send: %d', length(files))
            for f in files:
                # read file in chunks - default 1MB
                # write to Ceph
                offset = 0
                key = options.object_prefix + os.path.basename(f)
                time_start = time.time()
                for piece in read_in_chunks(f, buf):
                    logging.debug('writing object: %s of length: %d at offset: %d',
                                  key, length(piece), offset)
                    ioctx.write(key, piece, offset)
                    offset += options.buf
                time_end = time.time()
                for k, v in XATTRS.items():
                    ioctx.set_xattr(key, k, v)
                csvwriter.writerow(['w', key, f, offset, "%3.5f" % (time_end - time_start), repr(time_start), repr(time_end)])
                csvfile.flush()

        # if we are reading objects from storage
        if options.read:

            # find object list
            pool_stats = ioctx.get_stats()
            logging.debug('pool stats: %s', repr(pool_stats))

            objects = ioctx.list_objects()
            while True:
                try:
                    rados_object = object_iterator.next()
                    # print "Object contents = " + rados_object.read()
                    logging.debug('object: %s', repr(rados_object))
                    logging.debug('object stats: %s', repr(rados_object.stat()))
                    logging.debug('object xattrs: %s', repr(rados_object.get_xattrs()))
                    filename = os.path.join(options.output_dir, rados_object.key)
                    offset = 0
                    time_start = time.time()
                    with open(filename, 'wb') as fobj:
                        while True:
                            try:
                                piece = rados_object.read(options.buf, offset)
                                fobj.write(piece)
                                offset += options.buf
                            except:
                                break
                    time_end = time.time()
                    csvwriter.writerow(['r', rados_object.key, filename, os.stat(filename).st_size , "%3.5f" % (time_end - time_start), repr(time_start), repr(time_end)])
                    csvfile.flush()
                except StopIteration:
                    break

    logging.info('Timeout - stopping ')


    ioctx.close()
    cluster.shutdown()

    sys.exit(0)


# main
if __name__ == "__main__":

    main()
