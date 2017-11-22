LIMIT ?=
DOCKER_USER := piers@catalyst.net.nz
DOCKER_PASSWORD := secret

all: build

build_hosts:
	ansible-playbook -e @config/cc.yml -i ansible/inventory ansible/cluster-infra.yml

add_common:
	ansible-playbook -e @config/cc.yml -i ansible/inventory_cc ansible/cc.yml

build_cc:
	cd cc && ansible-playbook -i ../ansible/inventory_cc -i ./inventory $(LIMIT) playbooks/cc.yml --extra-vars="docker_user=$(DOCKER_USER) docker_password=$(DOCKER_PASSWORD)"

check:
	cd cc && ansible -i ../ansible/inventory_cc -i ./inventory --limit=cc-nodes all -b -m shell -a 'systemctl status docker; docker ps -a; uptime'

build: build_hosts add_common build_cc

reboot:
	cd cc && ansible -P 0 -B 0 -i ../ansible/inventory_cc -i ./inventory --limit=cc-nodes all -b -m shell -a  "/usr/bin/sudo /sbin/reboot"
