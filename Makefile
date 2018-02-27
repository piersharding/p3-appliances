LIMIT ?=
DOCKER_USER := piers@catalyst.net.nz
DOCKER_PASSWORD := secret

all: build

build_hosts:
	ansible-playbook -e @config/shared.yml -i ansible/inventory ansible/cluster-infra.yml

add_common:
	ansible-playbook -e @config/shared.yml -i ansible/inventory_shared_services ansible/shared.yml

build_dcos:
	cd dcos && ansible-playbook -i ../ansible/inventory_shared_services -i ./inventory $(LIMIT) playbooks/dcos.yml --extra-vars="docker_user=$(DOCKER_USER) docker_password=$(DOCKER_PASSWORD)"

check_dcos:
	cd dcos && ansible -i ../ansible/inventory_shared_services -i ./inventory --limit=shared-nodes all -b -m shell -a 'systemctl status docker; docker ps -a; uptime'
	cd dcos && ansible -i ../ansible/inventory_shared_services all -m shell -a "hostname -f; hostname -s; hostnamectl"

# ssh-keygen -y -f piers-p3.pem > piers-p3.pub
shared_ssh_keys:
	cd shared && ansible-playbook -i ../ansible/inventory_shared_services playbooks/ssh-keys.yml

reboot:
	cd shared && ansible-playbook -i ../ansible/inventory_shared_services playbooks/restart-hosts.yml

dcos_ssh_key:
	cd shared && ansible -i ../ansible/inventory_shared_services shared_services_controller -m copy -a "src=playbooks/tmp/id_rsa dest=/home/ubuntu/genconf/ssh_key"

dcos: build_hosts add_common build_dcos shared_ssh_keys dcos_ssh_key

docker_registry:
	cd dcos && ansible -i ../ansible/inventory_shared_services -i ./inventory shared_services_controller -b -m shell -a 'docker pull registry:2; docker run -d --name registry --restart=always -p 5000:5000 -v /home/ubuntu/registry:/var/lib/registry registry:2'
	sleep 5
	cd dcos && ansible -i ../ansible/inventory_shared_services -i ./inventory shared_services_controller -b -m shell -a 'docker logs registry'

prep_dcos:
	cd dcos && ansible -i ../ansible/inventory_shared_services -i ./inventory shared_services_controller -b -m shell -a 'cd /home/ubuntu; bash dcos_generate_config.sh --genconf'
	cd dcos && ansible -i ../ansible/inventory_shared_services -i ./inventory shared_services_controller -b -m shell -a 'docker run -d --name nginx -p 5001:80 -v /home/ubuntu/genconf/serve:/usr/share/nginx/html:ro nginx'
	cd dcos && ansible -i ../ansible/inventory_shared_services -i ./inventory shared_services_controller -b -m shell -a 'cd /home/ubuntu; bash dcos_generate_config.sh --install-prereqs'
	cd dcos && ansible -i ../ansible/inventory_shared_services -i ./inventory shared_services_controller -b -m shell -a 'cd /home/ubuntu; bash dcos_generate_config.sh --preflight'

# https://docs.mesosphere.com/1.10/installing/oss/custom/cli/
# https://docs.mesosphere.com/1.10/installing/oss/custom/configuration/configuration-parameters/#resolvers
# https://docs.mesosphere.com/1.10/installing/oss/troubleshooting/
deploy_dcos:
	cd dcos && ansible -i ../ansible/inventory_shared_services -i ./inventory shared_services_controller -b -m shell -a 'cd /home/ubuntu; bash dcos_generate_config.sh --deploy'

post_deploy_dcos:
	cd dcos && ansible -i ../ansible/inventory_shared_services -i ./inventory shared_services_controller -b -m shell -a 'cd /home/ubuntu; bash dcos_generate_config.sh --postflight'

all_deploy: prep_dcos deploy_dcos post_deploy_dcos

# get the comand line client
# [ -d /usr/local/bin ] || sudo mkdir -p /usr/local/bin &&  curl https://downloads.dcos.io/binaries/cli/linux/x86-64/dcos-1.10/dcos -o dcos &&  sudo mv dcos /usr/local/bin &&  sudo chmod +x /usr/local/bin/dcos &&  dcos cluster setup http://shared_services-compute-0 && dcos config validate

# test drive
# sudo killall ssh-agent
# eval `ssh-agent -s`
# ssh-add ~/.ssh/id_rsa 
# dcos node ssh --master-proxy --leader --user ubuntu
#
# logs
# dcos node log --leader
#
# marathon-lb
# dcos package install marathon-lb
# dcos task


build_shared:
	cd shared && ansible-playbook -i ../ansible/inventory_shared_services -i ./inventory $(LIMIT) playbooks/shared.yml --extra-vars="docker_user=$(DOCKER_USER) docker_password=$(DOCKER_PASSWORD)"

check_shared:
	cd shared && ansible -i ../ansible/inventory_shared_services -i ./inventory --limit=shared-nodes all -b -m shell -a 'systemctl status docker; docker ps -a; uptime'

shared: build_hosts add_common build_shared


# fixing leftover raid
# cat /proc/mdstat 
# sudo mdadm --detail /dev/md127 # a number
# sudo mdadm -S /dev/md127
# sudo mdadm --zero-superblock /dev/sdc
# sudo fsck.xfs -a /dev/sdc
# sudo mkfs.xfs /dev/sdc
# sudo mount /dev/sdc /var/lib/mesos
# cat /proc/mdstat 


# VPN over PPP
# https://wiki.archlinux.org/index.php/VPN_over_SSH#Using_PPP_over_SSH

# sudo /usr/sbin/pppd updetach noauth silent nodeflate pty "/usr/bin/ssh ubuntu@10.60.253.25 sudo /usr/sbin/pppd nodetach notty noauth" ipparam vpn 10.0.8.1:10.0.8.2

# sudo /usr/sbin/pppd updetach noauth silent nodeflate pty "/usr/bin/ssh ubuntu@10.60.253.26 sudo /usr/sbin/pppd nodetach notty noauth" ipparam vpn 10.0.9.1:10.0.9.2
# sudo /usr/sbin/pppd updetach noauth silent nodeflate pty "/usr/bin/ssh ubuntu@10.60.253.47 sudo /usr/sbin/pppd nodetach notty noauth" ipparam vpn 10.0.10.1:10.0.10.2
# sudo /usr/sbin/pppd updetach noauth silent nodeflate pty "/usr/bin/ssh ubuntu@10.60.253.49 sudo /usr/sbin/pppd nodetach notty noauth" ipparam vpn 10.0.11.1:10.0.11.2

# ip route add 10.60.253.25/32 via 10.0.8.2

# ip route add 10.60.253.26/32 via 10.0.9.2
# ip route add 10.60.253.47/32 via 10.0.10.2
# ip route add 10.60.253.49/32 via 10.0.11.2
