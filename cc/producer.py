#!/usr/bin/env python
# -*- coding: utf-8 -*-
""" Kafka producer for creating segmented large messages
"""
import time
import getopt
import os
import os.path
import sys
import glob
import logging
import random
import string
import hashlib
import csv
from collections import namedtuple
from kafka import KafkaProducer
# from kafka.errors import KafkaError


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


@timeit
def write_random_lowercase(n_bytes, fname):
    """ Generate file containing an arbitrary length random string
    """
    logging.debug('creating: %s of length: %d', fname, n_bytes)
    with open(fname, 'wb') as out:
        min_lc = ord(b'a')
        len_lc = 26
        byte_array = bytearray(os.urandom(n_bytes))
        for element, byte in enumerate(byte_array):
            # convert 0..255 to 97..122
            byte_array[element] = min_lc + byte % len_lc
        out.write(byte_array)


@timeit
def split(fromfile, chunksize):
    """ Split a file into partition files of length chunks
    """
    # delete any existing files
    for fname in sorted(glob.glob(fromfile + '.part*')):
        logging.debug('deleting file: %s', fname)
        os.remove(fname)
    partnum = 0
    infile = open(fromfile, 'rb')                  # use binary mode on Windows
    while 1:                                       # eof=empty string from read
        chunk = infile.read(chunksize)             # get next part <= chunksize
        if not chunk:
            break
        partnum = partnum + 1
        filename = fromfile + '.part.%07d' % (partnum)
        fileobj = open(filename, 'wb')
        fileobj.write(chunk)
        fileobj.close()
        logging.debug('writing file: %s of length: %d', filename, chunksize)
    infile.close()
    # join sort fails if 5 digits
    assert partnum <= 9999999
    return partnum


@timeit
def split_in_mem(fromfile, chunksize):
    """ Split a file into partition in memory of length chunks
    """
    # delete any existing files
    for fname in sorted(glob.glob(fromfile + '.part*')):
        logging.debug('deleting file: %s', fname)
        os.remove(fname)
    partnum = 0
    infile = open(fromfile, 'rb')                  # use binary mode on Windows
    while 1:                                       # eof=empty string from read
        chunk = infile.read(chunksize)             # get next part <= chunksize
        if not chunk:
            break
        partnum = partnum + 1
        logging.debug('yielding part: %07d of length: %d', partnum, chunksize)
        yield (partnum, chunk)
    infile.close()


@timeit
def md5checksum(fname):
    """ Calculate md5 checksum of a file
    """
    hash_md5 = hashlib.md5()
    with open(fname, "rb") as file:
        for chunk in iter(lambda: file.read(4096), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()


@timeit
def send_message_chunks(fromfile, checksum, producer, csvwriter, options):
    """ Send partition files as chunks to Kafka with complete message metadata
    """
    start_time = time.time()
    uuid = ''.join(random.choice(string.ascii_letters + string.digits)
                   for _ in range(16))
    datalen = 0
    tot = len(glob.glob(fromfile + '.part*'))
    for i, part in enumerate(sorted(glob.glob(fromfile + '.part*'))):
        prefix = 'part: %s checksum: %s seg: %07d/%07d data: ' % \
                 (uuid, checksum, i+1, tot)
        with open(part, 'rb') as infile:
            data = infile.read()
        # why does this not work?
        # producer.send(topic_id, key=uuid,
        #               value=prefix.encode('utf-8') + data)
        producer.send(options.topic_id, prefix.encode('utf-8') + data)
        datalen += len(data)
        logging.debug('sent message segment with key/segs: %s[%d] ' +
                      'to: %s [%d] prefix: [%s]',
                      uuid, len(data), options.topic_id, datalen, prefix)

    # block until all async messages are sent
    producer.flush()

    build_time = time.time() - start_time
    csvwriter.writerow([uuid, checksum, datalen, tot, build_time])
    logging.info('sent messages with key/segs: %s[%d] ' +
                 'to: %s [%d] prefix: [%s] in: %3.03f',
                 uuid, tot, options.topic_id, datalen, prefix, build_time)


def parse_opts():
    """ Parse out the command line options
    """
    options = {
        'chunksize': int(1.4 * 1024 * 1000),  # 1MB
        'topic_id': "test100m",
        'broker': "kafka-master-0:9092," +
                  "kafka-worker-0:9092," +
                  "kafka-worker-1:9092",
        'dir': "/tmp/producer",
        'file': "message.txt",
        'filename': None,
        'csv_file': '/tmp/producer_times.csv',
        'no_trials': 10,
        'msgsize': int(1.4 * 1024 * 1000) * 100,  # 100MB
        'debug': False
    }

    # parse command line opts
    try:
        (opts, _) = getopt.getopt(sys.argv[1:],
                                  'dt:b:r:l:f:c:s:o:',
                                  ["debug",
                                   "topic=",
                                   "broker=",
                                   "range=",
                                   "dir=",
                                   "file=",
                                   "chunksize=",
                                   "size=",
                                   "csv_file"])
    except getopt.GetoptError:
        print('producer.py [-d -t <topic_id> -b <brokerlist> -r <range>' +
              ' -l <dir> -f <file> -c <chunksize> -s <message size> ' +
              '-o <csv_file>]')
        sys.exit(2)

    dopts = {}
    for (key, value) in opts:
        dopts[key] = value
    if '-t' in dopts:
        options['topic_id'] = dopts['-t']
    if '-b' in dopts:
        options['broker'] = dopts['-b']
    if '-r' in dopts:
        options['no_trials'] = int(dopts['-r'])
    if '-l' in dopts:
        options['dir'] = dopts['-l']
    if '-f' in dopts:
        options['file'] = dopts['-f']
    if '-c' in dopts:
        options['chunksize'] = int(dopts['-c'])
    if '-o' in dopts:
        options['csv_file'] = dopts['-o']
    if '-s' in dopts:
        options['msgsize'] = int(dopts['-s'])
    if '-d' in dopts:
        options['debug'] = True

    options['filename'] = os.path.join(options['dir'], options['file'])

    # container class for options parameters
    option = namedtuple('option', options.keys())
    return option(**options)


def main():
    """ Main
    """
    options = parse_opts()

    # setup logging
    logging.basicConfig(level=(logging.DEBUG if options.debug
                               else logging.INFO),
                        format=('%(asctime)s [%(name)s] ' +
                                '%(levelname)s: %(message)s'))
    logging.info('topic_id is: %s ', options.topic_id)
    logging.info('total message size: %s[%d] in chunks: %d ',
                 options.filename, options.msgsize, options.chunksize)

    # purge output directory
    if os.path.exists(options.dir):
        for root, dirs, files in os.walk(options.dir, topdown=False):
            for name in files:
                os.remove(os.path.join(root, name))
            for name in dirs:
                os.rmdir(os.path.join(root, name))
    else:
        os.mkdir(options.dir)

    # generate random string for large message
    write_random_lowercase(options.msgsize, options.filename)
    logging.info('written random byte[%d] filename: %s ',
                 options.msgsize, options.filename)

    # partition large message and find checksum
    splits = split(options.filename, options.chunksize)
    checksum = md5checksum(options.filename)
    logging.info('written split files: %s[%d] sum: %s',
                 options.filename, splits, checksum)

    # setup producer connection
    producer = KafkaProducer(bootstrap_servers=options.broker.split(","),
                             # batch is roughly one Large Message
                             batch_size=int(options.msgsize /
                                            options.chunksize),
                             acks=1,
                             buffer_memory=(options.msgsize +
                                            options.chunksize + 100),
                             max_request_size=(options.chunksize + 100) * 2,
                             send_buffer_bytes=(options.chunksize + 100) * 2)

    # write timing results out to a CSV file
    with open(options.csv_file, 'w', newline='') as csvfile:
        csvwriter = csv.writer(csvfile, delimiter=',',
                               quotechar='"', quoting=csv.QUOTE_MINIMAL)
        csvwriter.writerow(['uuid', 'md5checksum', 'datalen', 'segs', 'time'])

        # produce asynchronously for range with flush after each large message
        for _ in range(0, options.no_trials):
            send_message_chunks(options.filename, checksum,
                                producer, csvwriter, options)
        csvfile.flush()

    logging.info('Finished - exiting.')
    sys.exit(0)


# main
if __name__ == "__main__":

    main()
