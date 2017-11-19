#!/usr/bin/env python
# -*- coding: utf-8 -*-
""" Kafka consumer for reassembling segmented large messages
"""

import time
import getopt
import os
import os.path
import sys
import glob
import logging
import hashlib
import csv
import signal
from collections import namedtuple
from kafka import KafkaConsumer

# container class for message segment
MsgSegment = namedtuple('MsgSegment', ['uuid', 'checksum', 'seg',
                                       'batch_tot', 'datalen',
                                       'partition', 'topic',
                                       'offset', 'key', 'value'])


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
def md5checksum(fname):
    """ Calculate md5 checksum of a file
    """
    hash_md5 = hashlib.md5()
    with open(fname, "rb") as file:
        for chunk in iter(lambda: file.read(4096), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()


def parse_opts():
    """ Parse out the command line options
    """
    options = {
        'chunksize': int(1024 * 1024),  # 1MB
        'topic_id': "test100m",
        'broker': "kafka-master-0:9092," +
                  "kafka-worker-0:9092," +
                  "kafka-worker-1:9092",
        'dir': "/tmp/consumer",
        'file': "received_message.txt",
        'filename': None,
        'group_id': 'con0',
        'client_id': 'client1',
        'csv_file': '/tmp/consumer_times.csv',
        'debug': False,
        'nofiles': False
    }

    try:
        (opts, _) = getopt.getopt(sys.argv[1:],
                                  'dnt:b:l:f:g:c:z:s:',
                                  ["debug",
                                   "nofiles",
                                   "topic=",
                                   "broker=",
                                   "dir=",
                                   "file=",
                                   "group_id=",
                                   "client_id=",
                                   "csv_file=",
                                   "chunksize="])
    except getopt.GetoptError:
        print('producer.py [-d -t <topic_id> ' +
              '-b <comma separated broker list> ' +
              '-f <output file> -g <group_id> ' +
              '-z <csv_file> -s <chunksize>]')
        sys.exit(2)

    dopts = {}
    for (key, value) in opts:
        dopts[key] = value
    if '-t' in dopts:
        options['topic_id'] = dopts['-t']
    if '-b' in dopts:
        options['broker'] = dopts['-b']
    if '-l' in dopts:
        options['dir'] = dopts['-l']
    if '-f' in dopts:
        options['file'] = dopts['-f']
    if '-g' in dopts:
        options['group_id'] = dopts['-g']
    if '-c' in dopts:
        options['client_id'] = dopts['-c']
    if '-z' in dopts:
        options['csv_file'] = dopts['-z']
    if '-d' in dopts:
        options['debug'] = True
    if '-s' in dopts:
        options['chunksize'] = int(dopts['-s'])
    if '-n' in dopts:
        options['nofiles'] = True

    options['filename'] = os.path.join(options['dir'], options['file'])

    # container class for options parameters
    option = namedtuple('option', options.keys())
    return option(**options)


def my_deserialiser(msg):
    """ Simple deserialiser for incoming messages
    """
    # MsgSegment = namedtuple('MsgSegment', ['uuid', 'checksum', 'seg',
    #                                        'batch_tot', 'datalen',
    #                                        'partition', 'topic',
    #                                        'offset', 'key', 'value'])
    return MsgSegment(uuid=msg.value[6:22].decode('utf8'),
                      checksum=msg.value[33:65].decode('utf8'),
                      seg=msg.value[71:78].decode('utf8'),
                      batch_tot=int(msg.value[79:86].decode('utf8')),
                      datalen=len(msg.value[93:]),
                      partition=msg.partition,
                      topic=msg.topic,
                      offset=msg.offset,
                      key=msg.key,
                      value=msg.value)


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
    logging.info('topic_id is: %s ', options.topic_id)

    purge_output_dir(options.dir)

    # To consume latest messages and auto-commit offsets
    consumer = KafkaConsumer(options.topic_id,
                             group_id=options.group_id,
                             client_id=options.client_id,
                             bootstrap_servers=options.broker.split(","),
                             enable_auto_commit=False,
                             # auto_commit_interval_ms=100000,
                             # auto_offset_reset='earliest',
                             # heartbeat_interval_ms=3000,
                             # consumer_timeout_ms=3000,
                             # request_timeout_ms=10000,
                             # session_timeout_ms=3000,
                             receive_buffer_bytes=(options.chunksize +
                                                   100) * 10,
                             fetch_max_bytes=(options.chunksize + 100) * 10,
                             max_partition_fetch_bytes=(options.chunksize +
                                                        100) * 10)

    logging.info('consumer connected: %s ', consumer)

    # trap the keyboard interrupt
    def signal_handler(signal_caught, frame):
        """ Catch the keyboard interrupt and gracefully exit
        """
        logging.info('You pressed Ctrl+C!: %s/%s', signal_caught, frame)
        consumer.close()
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

        # main message loop
        for message in consumer:
            message = my_deserialiser(message)
            logging.debug("%s:%d:%d: key=%s rawlen=%d " +
                          "datalen=%d uuid=%s seg=%d batch_tot=%d",
                          message.topic, message.partition,
                          message.offset, message.key, len(message.value),
                          message.datalen, message.uuid,
                          int(message.seg), message.batch_tot)
            logging.debug("%s:%d:%d: key=%s metadata=%s",
                          message.topic, message.partition,
                          message.offset, message.key, message.value[0:93])

            # stash file parts
            if not options.nofiles:
                filename = (options.filename + '.' + message.uuid +
                            '.part.' + message.seg)
                with open(filename, 'wb') as fileobj:
                    fileobj.write(message.value[93:])
                logging.debug('writing file: %s of length: %d',
                              filename, message.datalen)

            if message.uuid not in batches:
                batches[message.uuid] = {'start_time': time.time(), 'segs': []}
            batches[message.uuid]['segs'].append(message.seg)

            # do we have complete batch
            if message.batch_tot == len(batches[message.uuid]['segs']):
                # we have a complete batch!  Combine the segments
                tot = 0
                filename = ""
                file_checksum = ""
                if not options.nofiles:
                    filename = options.filename + '.' + message.uuid + '.txt'
                    with open(filename, 'wb') as out:
                        for part in sorted(glob.glob(options.filename +
                                                     '.' +
                                                     message.uuid +
                                                     '.part.*')):
                            with open(part, 'rb') as infile:
                                data = infile.read()
                            out.write(data)
                            logging.debug('adding file: %s[%d] to %s',
                                          part,
                                          os.stat(part).st_size,
                                          message.uuid)
                            os.remove(part)
                            tot += len(data)
                    # check the checksum
                    file_checksum = md5checksum(filename)
                # commit after each large message found
                # - this is actually wrong when multiple partitions !
                consumer.commit()
                build_time = time.time() - batches[message.uuid]['start_time']
                logging.info('completed file: %s of length: %d ' +
                             'segs: %d checksum[%s]: [%s/%s] time: %3.03f',
                             filename, tot, message.batch_tot,
                             ('OK' if file_checksum ==
                              message.checksum else 'NOT_OK'),
                             message.checksum, file_checksum, build_time)
                csvwriter.writerow([message.uuid, message.checksum,
                                    file_checksum,
                                    ('OK' if file_checksum ==
                                     message.checksum else 'NOT_OK'),
                                    tot, message.batch_tot,
                                    build_time])
                csvfile.flush()

    logging.info('Timeout - stopping ')

    sys.exit(0)


# main
if __name__ == "__main__":

    main()
