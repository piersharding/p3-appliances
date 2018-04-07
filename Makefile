LIMIT ?=
DOCKER_USER := piers@catalyst.net.nz
DOCKER_PASSWORD := secret
SIGNING_KEY := B81C8942C09FC231708FED9479C7D4D5AE8B8DAE


# http://docs.ceph.com/ceph-ansible/master/
# http://tracker.ceph.com/projects/ceph/wiki/Benchmark_Ceph_Cluster_Performance

all: build

build_hosts:
	ansible-playbook -e @config/shared.yml -i ansible/inventory ansible/cluster-infra.yml
	cd os  && ansible -i ../ansible/inventory_shared_services cluster -b -m shell -a 'apt update'

add_common:
	@echo "@@@@@@@@@@@@@"
	@echo "@@@@@@@@@@@@@"
	@echo "@@@@@@@@@@@@@"
	@echo "temporary hack out of Ceph mount - broken barbican vars: ceph.client.alaska.key"
	@echo "@@@@@@@@@@@@@"
	@echo "@@@@@@@@@@@@@"
	@echo "@@@@@@@@@@@@@"
	cd os && ansible -i ../ansible/inventory_shared_services cluster -b -m shell -a "mkdir -p /alaska"
	ansible-playbook -e @config/shared.yml -i ansible/inventory_shared_services ansible/shared.yml

build_os:
	cd os && ansible-playbook -i ../ansible/inventory_shared_services -i ./inventory $(LIMIT) playbooks/os.yml --extra-vars="docker_user=$(DOCKER_USER) docker_password=$(DOCKER_PASSWORD) local_repo_signing_key=$(SIGNING_KEY)"

second_interface:
	cd os  && ansible -i ../ansible/inventory_shared_services cluster -b -m shell -a 'ifconfig p3p1 up; dhclient p3p1'

set_iface:
	cd os  && ansible -i ../ansible/inventory_shared_services cluster -b -m shell -a 'echo "auto p3p1\niface p3p1 inet dhcp\n    gateway 10.60.210.1" | tee /etc/network/interfaces.d/90-p3p1.cfg'

fix_iface:
	cd os && ansible -i ../ansible/inventory_shared_services cluster -b -m shell -a 'route del default gw 10.1.0.1 p3p1; route add default gw 10.60.210.1 em1; route -n'
	cd os  && ansible -i ../ansible/inventory_shared_services cluster -b -m shell -a 'ip link set p3p1 up; ip link set p3p1 mtu 1500; ethtool -s p3p1 speed 25000 duplex full'

check_os:
	cd os && ansible -i ../ansible/inventory_shared_services -i ./inventory --limit=shared-nodes cluster -b -m shell -a 'systemctl status docker; docker ps -a; uptime'
	cd os && ansible -i ../ansible/inventory_shared_services cluster -m shell -a "hostname -f; hostname -s; hostnamectl"

# ssh-keygen -y -f piers-p3.pem > piers-p3.pub
shared_ssh_keys:
	cd shared && ansible-playbook -i ../ansible/inventory_shared_services playbooks/ssh-keys.yml

reboot:
	cd shared && ansible-playbook -i ../ansible/inventory_shared_services playbooks/restart-hosts.yml

set_perf:
	cd os && ansible -i ../ansible/inventory_shared_services cluster -b -m shell -a 'cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; for CPUFREQ in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do [ -f $$CPUFREQ ] || continue; echo -n performance > $$CPUFREQ; done; cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'
	cd os && ansible -i ../ansible/inventory_shared_services cluster -b -m shell -a 'for i in a b c d ; do echo "8192" > /sys/block/sd$$i/queue/read_ahead_kb; echo "1024" > /sys/block/sd$$i/queue/nr_requests; echo 2 > /sys/block/sd$$i/queue/rq_affinity; echo "cfq" > /sys/block/sd$$i/queue/scheduler; cat /sys/block/sd$$i/queue/read_ahead_kb; done'

fix: fix_iface set_perf

# http://tracker.ceph.com/projects/ceph/wiki/Tuning_for_All_Flash_Deployments
# https://xiaoquqi.github.io/blog/2015/06/28/ceph-performance-optimization-summary/
# https://wiki.mikejung.biz/Ubuntu_Performance_Tuning#read_ahead_kb

copy_fio_test:
	cd os && ansible -i ../ansible/inventory_shared_services cluster -b -m copy -a "src=../fio_test.sh dest=/home/ubuntu/fio_test.sh owner=ubuntu group=ubuntu mode=0755"

run_fio_test:
	cd os && ansible -i ../ansible/inventory_shared_services cluster -b -m shell -a "cd /home/ubuntu; ./fio_test.sh"

fetch_fio_test:
	cd os && ansible -i ../ansible/inventory_shared_services cluster -b -m synchronize -a "src=/home/ubuntu/fiologs dest=/tmp/{{ inventory_hostname }} mode=pull"

fio: copy_fio_test run_fio_test fetch_fio_test

# os_ssh_key:
# 	cd shared && ansible -i ../ansible/inventory_shared_services shared_services_controller -m copy -a "src=playbooks/tmp/id_rsa dest=/home/ubuntu/genconf/ssh_key"

copy_key:
	cd os && ansible -i ../ansible/inventory_shared_services shared_services_controller -m copy -a "src=../repo-key.asc dest=/home/ubuntu/repo-key.asc owner=ubuntu group=ubuntu mode=0644"
	cd os && ansible -i ../ansible/inventory_shared_services shared_services_controller -m shell -a 'gpg --import /home/ubuntu/repo-key.asc || true'

os: build_hosts add_common copy_key build_os set_iface shared_ssh_keys
# os: copy_key build_os set_iface shared_ssh_keys

iface: second_interface set_iface fix_iface

dnsmasq:
	# cd os  && ansible -i ../ansible/inventory_shared_services cluster -b -m shell -a 'export DEBIAN_FRONTEND=noninteractive; apt install -y dnsmasq'
	cd os  && ansible -i ../ansible/inventory_shared_services cluster -b -m shell -a 'dig shared-services-controller-0'

rados_client:
	cd os && ansible -i ../ansible/inventory_shared_services shared_services_controller -m copy -a "src=../rados_client.py dest=/home/ubuntu/rados_client.py owner=ubuntu group=ubuntu mode=0755"


# fix interfaces 
# route del default gw 10.1.0.1 p3p1
# route add default gw 10.60.210.1 em1


run_repo:
	cd os && ansible -i ../ansible/inventory_shared_services shared_services_controller -m shell -a 'docker run -d --restart always --name nginx -p 88:80 -v /home/ubuntu/default.conf:/etc/nginx/conf.d/default.conf:ro -v /var/tmp/release/Ubuntu:/usr/share/nginx/html:ro nginx'
	cd os && ansible -i ../ansible/inventory_shared_services shared_services_controller -m shell -a 'curl http://localhost:88'
	# cd os && ansible -i ../ansible/inventory_shared_services shared_services_controller -b -m shell -a 'export DEBIAN_FRONTEND=noninteractive; apt-get update; apt-get install -y python3-rados'

tools:
	cd os && ansible -i ../ansible/inventory_shared_services cluster -b -m shell -a 'export DEBIAN_FRONTEND=noninteractive; apt-get install -y linux-headers-generic; cd /tmp; rm -rf mft-4.9.0-38-x86_64-deb.tgz mft-4.9.0-38-x86_64-deb; wget -q http://www.mellanox.com/downloads/MFT/mft-4.9.0-38-x86_64-deb.tgz; tar -xzf mft-4.9.0-38-x86_64-deb.tgz; cd /tmp/mft-4.9.0-38-x86_64-deb/; ./install.sh; mst start'

check_mellanox:
	cd os && ansible -i ../ansible/inventory_shared_services cluster -b -m shell -a 'mlxconfig -d /dev/mst/mt4115_pciconf0 q | grep LINK_TYPE '

set_mellanox:
	cd os && ansible -i ../ansible/inventory_shared_services cluster -b -m shell -a 'mlxconfig -y -d /dev/mst/mt4115_pciconf0 set LINK_TYPE_P1=1 LINK_TYPE_P2=2 '


purge_lvols:
	cd shared && ansible-playbook -i ../ansible/inventory_shared_services playbooks/purge-vols.yml


# Infiniband tools
# https://community.mellanox.com/docs/DOC-2377
# Mellanox tools
# http://www.mellanox.com/downloads/MFT/mft-4.9.0-38-x86_64-deb.tgz
# Mellanox drivers
# http://www.mellanox.com/downloads/ofed/MLNX_EN-4.3-1.0.1.0/mlnx-en-4.3-1.0.1.0-ubuntu16.04-x86_64.tgz

# https://github.com/Mellanox/libvma/wiki/VMA-over-Ubuntu-16.04-and-inbox-driver
# echo mlx4_ib >> /etc/modules
# echo ib_umad >> /etc/modules
# echo ib_cm >> /etc/modules
# echo ib_ucm >> /etc/modules
# echo rdma_ucm >> /etc/modules

# Config IPoIB
# https://community.mellanox.com/docs/DOC-2294

# os_ssh_key:
# 	cd shared && ansible -i ../ansible/inventory_shared_services shared_services_controller -m copy -a "src=playbooks/tmp/id_rsa dest=/home/ubuntu/genconf/ssh_key"

# find pools
# for i in `rados lspools`; do  ceph osd pool application get $i; done

ceph_test_setup:
	cd os && ansible -i ../ansible/inventory_shared_services shared_services_controller -b -m shell -a 'ceph -s; ceph osd pool create scbench 256 256; ceph osd pool stats; ceph osd pool get scbench size; ceph osd pool application enable scbench librados'
# ceph osd pool create scbench 256 256
# ceph osd pool get scbench size
# ceph osd pool rm scbench scbench --yes-i-really-really-mean-it

# rados bench -p scbench 60 write --no-cleanup
# -b block size
# -o object size
# -t concurrent ops

 # rados bench -p scbench -t 16 -b 4M  30 write --no-cleanup | tee write.log
 # rados bench -p scbench -t 16 -b 4M  30 seq | tee seq.log
 # rados bench -p scbench -t 16 -b 4M  30 rand | tee seq.log

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

# edit debian/rules add:
# # add jemalloc
# extraopts += -DALLOCATOR=jemalloc
# git submodule update --init --recursive && ./install-deps.sh && sudo apt install reprepro -y
# after ./make-debs.sh /var/tmp/release B81C8942C09FC231708FED9479C7D4D5AE8B8DAE
# cd /var/tmp/release/Ubuntu && vim conf/distributions
# add SignWith: B81C8942C09FC231708FED9479C7D4D5AE8B8DAE
# gpg --export-secret-keys $ID > my-private-key.asc
# gpg --import my-private-key.asc
# remove all old files: cd /var/tmp/release/Ubuntu; for i in db dists pool; do rm `find $i -type f`; done
# reprepro --basedir $(pwd) include xenial WORKDIR/*.changes
# docker run -d --name nginx -p 88:80 -v /home/ubuntu/default.conf:/etc/nginx/conf.d/default.conf:ro -v /var/tmp/release/Ubuntu:/usr/share/nginx/html:ro nginx
# apt-key adv --keyserver keyserver.ubuntu.com --recv 79C7D4D5AE8B8DAE
# source list is: deb http://shared-services-controller-0:88/ xenial main
# apt-get update

# iperf3 -c 10.60.100.17 -b 45000M -w 256K -l 50000B -f m
