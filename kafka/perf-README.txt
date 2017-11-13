# Apache Kafka 

## Performance testing

To run the Kafka performance tests you can update the server.properties to dump the metrics of the test to CSV files.

Add this to your brokers' server.properties file setting the values approriate for your enviornment.

    kafka.metrics.polling.interval.secs=5
    kafka.metrics.reporters=kafka.metrics.KafkaCSVMetricsReporter
    kafka.csv.metrics.dir=/tmp/kafka_metrics
    kafka.csv.metrics.reporter.enabled=true

Before running the tests decide on what settings make the test valid for your implementation for producers and consumers.

    bin/kafka-producer-perf-test.sh --help
    bin/kafka-consumer-perf-test.sh --help
    
You may want to review the wiki page on performance testing https://cwiki.apache.org/confluence/display/KAFKA/Performance+testing for more detail about this or review the help that each test provides from the command line.

After you have run your tests and you have your CSV results you can now graph the metrics using the `draw-performance-graphs.r` script.

You need to have R http://www.r-project.org/ installed and X11 too (for Mac users this is no longer shipped by Apple but available here http://xquartz.macosforge.org/landing/)

Once these are installed then you can go to the folder where your metrics csv where created (e.g. /tmp/kafka_metrics) and then run the script (assuming you have kafka cloned e.g. /opt/apache/kafka)

    cd /tmp/kafka_metrics
    RScript /opt/apache/kafka/perf/draw-performance-graphs.r TRUE Produce-RequestsPerSec.csv
    
This will generate an image of all metrics in one png and also a png for each metric seperatly (metrics being total count, total mean, 1min, 5min, 15min moving averages)

If you want to generate a graph for more than one CSV file then add it as another argument to the command line.

    RScript /opt/apache/kafka/perf/draw-performance-graphs.r TRUE Produce-RequestsPerSec.csv test-MessagesInPerSec.csv
    
If you want to generate pngs for every CSV in the directory then run

    RScript /opt/apache/kafka/perf/draw-performance-graphs.r FALSE
