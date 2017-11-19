LIMIT ?=

all: build

build_hosts:
	ansible-playbook -e @config/cc.yml -i ansible/inventory ansible/cluster-infra.yml

add_common:
	ansible-playbook -e @config/cc.yml -i ansible/inventory_cc ansible/cc.yml

build_cc:
	cd cc && ansible-playbook -i ../ansible/inventory_cc -i ./inventory $(LIMIT) playbooks/cc.yml

check:
	cd cc && ansible -i ../ansible/inventory_cc -i ./inventory --limit=cc-nodes all -b -m shell -a '/etc/init.d/cc-server status; /etc/init.d/zookeeper-server status; uptime'

build: build_hosts add_common build_cc

reboot:
	# cd cc && ansible -P 0 -B 10 -i ../ansible/inventory_cc -i ./inventory --limit=cc-nodes all -b -m shell -a  "echo 'reboot' | sudo at 'now + 0 minute'"
	cd cc && ansible -P 0 -B 10 -i ../ansible/inventory_cc -i ./inventory --limit=cc-nodes all -b -m shell -a  "sudo reboot"
