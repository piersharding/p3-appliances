LIMIT ?=
REPL ?= 2
PARTS ?= 20

all: build

build_hosts:
	ansible-playbook -e @config/kafka.yml -i ansible/inventory ansible/cluster-infra.yml

add_common:
	ansible-playbook -e @config/kafka.yml -i ansible/inventory_kafka ansible/kafka.yml

build_kafka:
	cd kafka && ansible-playbook -i ../ansible/inventory_kafka -i ./inventory $(LIMIT) playbooks/kafka.yml

stop:
	cd kafka && ansible -i ../ansible/inventory_kafka -i ./inventory --limit=kafka-nodes all -b -m shell -a '/etc/init.d/kafka-server stop; /etc/init.d/zookeeper-server stop'

clean_kafka: stop
	cd kafka && ansible -i ../ansible/inventory_kafka -i ./inventory --limit=kafka-nodes all -b -m shell -a 'rm -rf /var/lib/kafka-data/*; rm -rf /var/lib/kafka-logs/*; rm -rf /var/lib/zookeeper/ver*'

restart:
	cd kafka && ansible -i ../ansible/inventory_kafka -i ./inventory --limit=kafka-nodes all -b -m shell -a '/etc/init.d/kafka-server restart; /etc/init.d/zookeeper-server restart'

check:
	cd kafka && ansible -i ../ansible/inventory_kafka -i ./inventory --limit=kafka-nodes all -b -m shell -a '/etc/init.d/kafka-server status; /etc/init.d/zookeeper-server status'

create_topic:
	cd kafka && ansible -i ../ansible/inventory_kafka -i ./inventory --limit=kafka-master all -b -m shell -a 'for i in test256b  test1k test1k10 test1m test1m10 test10m test10m10 test100m test100m10; do /opt/kafka/bin/kafka-topics.sh --create --zookeeper kafka-master-0:2181 --replication-factor $(REPL) --partitions $(PARTS) --topic  $$i || true; done'

reload_kafka: clean_kafka restart check create_topic

build: build_hosts add_common build_kafka
