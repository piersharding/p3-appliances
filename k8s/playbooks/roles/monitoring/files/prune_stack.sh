#!/bin/sh
DATE=`date +%Y.%m.%d`

echo "Real delete flag is: $1"

for idx in metricbeat journalbeat filebeat
do
    echo "Processing: ${idx}"
    for j in `curl -s -X GET "localhost:9200/_cat/indices?v" | grep ${idx} | awk '{print $3}' | sort | grep -v ${DATE}`
    do
        echo "Deleting index: ${j}"

        if [ "$1" = "x" ]; then
            echo "really deleting: ${j}"
            curl -X DELETE "localhost:9200/${j}?pretty"
        fi
    done
    echo ""
done
echo "Indexes remaining are:"
curl -X GET "localhost:9200/_cat/indices?v"
