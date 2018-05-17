LIMIT ?=
DOCKER_USER := gitlab+deploy-token-3
DOCKER_PASSWORD := gLkxdzzKMr5LMJT8JdVH
PROVIDER_USERNAME ?= piers
PROVIDER_PASSWORD ?= password

all: build

build_hosts:
	ansible-playbook -e @config/k8s.yml -i ansible/inventory ansible/cluster-infra.yml
	cd k8s  && ansible -i ../ansible/inventory_k8s cluster -b -m shell -a 'apt update'

add_common:
	@echo "@@@@@@@@@@@@@"
	@echo "@@@@@@@@@@@@@"
	@echo "@@@@@@@@@@@@@"
	@echo "temporary hack out of Ceph mount - broken barbican vars: ceph.client.alaska.key"
	@echo "@@@@@@@@@@@@@"
	@echo "@@@@@@@@@@@@@"
	@echo "@@@@@@@@@@@@@"
	ansible-playbook -e @config/k8s.yml -i ansible/inventory_k8s ansible/k8s.yml

build_k8s:
	cd k8s && ansible-playbook -i ../ansible/inventory_k8s -i ./inventory $(LIMIT) playbooks/k8s.yml --extra-vars="docker_user=$(DOCKER_USER) docker_password=$(DOCKER_PASSWORD) provider_username=$(PROVIDER_USERNAME) provider_password=$(PROVIDER_PASSWORD)"

second_interface:
	cd k8s  && ansible -i ../ansible/inventory_k8s cluster -b -m shell -a 'ifconfig p3p1 up; dhclient p3p1'

set_iface:
	cd k8s  && ansible -i ../ansible/inventory_k8s cluster -b -m shell -a 'echo "auto p3p1\niface p3p1 inet dhcp\n    gateway 10.60.210.1" | tee /etc/network/interfaces.d/90-p3p1.cfg'

fix_iface:
	cd k8s && ansible -i ../ansible/inventory_k8s cluster -b -m shell -a 'route del default gw 10.1.0.1 p3p1; route add default gw 10.60.210.1 em1; route -n'
	# cd k8s  && ansible -i ../ansible/inventory_k8s cluster -b -m shell -a 'ip link set p3p1 up; ip link set p3p1 mtu 1500; ethtool -s p3p1 speed 25000 duplex full'
	# cd k8s  && ansible -i ../ansible/inventory_k8s cluster -b -m shell -a 'ip link set p3p1 up; ip link set p3p1 mtu 9000; ethtool -s p3p1 speed 25000 duplex full; ibv_devinfo p3p1'
	cd k8s  && ansible -i ../ansible/inventory_k8s cluster -b -m shell -a 'ip link set p3p1 up; ip link set p3p1 mtu 9000; ethtool -s p3p1 speed 25000 duplex full'

# for i in mlx5_core mlx5_ib ib_core ib_uverbs ib_ipoib rdma_cm rdma_ucm; do modprobe $i; done
# ifdown ib0
# ifup ib0


check_k8s:
	cd k8s && ansible -i ../ansible/inventory_k8s -i ./inventory --limit=shared-nodes cluster -b -m shell -a 'systemctl status docker; docker ps -a; uptime'
	cd k8s && ansible -i ../ansible/inventory_k8s cluster -m shell -a "hostname -f; hostname -s; hostnamectl"

# ssh-keygen -y -f piers-p3.pem > piers-p3.pub
shared_ssh_keys:
	cd k8s && ansible-playbook -i ../ansible/inventory_k8s playbooks/ssh-keys.yml

reboot:
	cd k8s && ansible-playbook -i ../ansible/inventory_k8s playbooks/restart-hosts.yml

# https://accelazh.github.io/ceph/Ceph-Performance-Tuning-Checklist
# https://xiaoquqi.github.io/blog/2015/06/28/ceph-performance-optimization-summary/
set_perf:
	cd k8s && ansible -i ../ansible/inventory_k8s cluster -b -m shell -a 'cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; for CPUFREQ in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do [ -f $$CPUFREQ ] || continue; echo -n performance > $$CPUFREQ; done; cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'
	cd k8s && ansible -i ../ansible/inventory_k8s cluster -b -m shell -a 'for i in a b c d ; do echo "8192" > /sys/block/sd$$i/queue/read_ahead_kb; echo "1024" > /sys/block/sd$$i/queue/nr_requests; echo 2 > /sys/block/sd$$i/queue/rq_affinity; echo "cfq" > /sys/block/sd$$i/queue/scheduler; cat /sys/block/sd$$i/queue/read_ahead_kb; done'

# sudo route del default gw 10.60.210.1 dev p3p1
# sudo route del -net 10.0.0.0 netmask 255.0.0.0 gw 0.0.0.0 dev ib0

# cat /sys/class/net/ib0/mode
# sudo echo "connected" > /sys/class/net/ib0/mode
# cat /sys/class/net/ib0/mode
# sudo ifconfig ib0 mtu 65520

fix: second_interface fix_iface set_perf


k8s: build_hosts add_common set_iface fix build_k8s shared_ssh_keys

iface: second_interface set_iface fix_iface


# fix interfaces 
# route del default gw 10.1.0.1 p3p1
# route add default gw 10.60.210.1 em1

#
# CINDER
#
# https://thenewstack.io/deploying-cinder-stand-alone-storage-service/
# build docker images with blockbox using loci
# ./build.sh && ./push.sh
#
# Must fiddle the API version to get detach to work
# cinder --os-auth-type=noauth --bypass-url=http://127.0.0.1:8776/v3 --os-project-id=admin --os-volume-api-version=3.44 create  --name blockbox-vol1 1
# sudo -E cinder local-attach 01bf2a96-c1e5-4c2a-a155-6bdbb826692f
# sudo -E OS_VOLUME_API_VERSION=3.43 cinder local-detach 01bf2a96-c1e5-4c2a-a155-6bdbb826692f
# cinder --os-auth-type=noauth --bypass-url=http://127.0.0.1:8776/v3 --os-project-id=admin --os-volume-api-version=3.44 delete 01bf2a96-c1e5-4c2a-a155-6bdbb826692f

run_repo:
	cd os && ansible -i ../ansible/inventory_k8s shared_services_controller -m shell -a 'docker run -d --restart always --name nginx -p 88:80 -v /home/ubuntu/default.conf:/etc/nginx/conf.d/default.conf:ro -v /var/tmp/release/Ubuntu:/usr/share/nginx/html:ro nginx'
	cd os && ansible -i ../ansible/inventory_k8s shared_services_controller -m shell -a 'curl http://localhost:88'
	# cd os && ansible -i ../ansible/inventory_k8s shared_services_controller -b -m shell -a 'export DEBIAN_FRONTEND=noninteractive; apt-get update; apt-get install -y python3-rados'

tools:
	cd os && ansible -i ../ansible/inventory_k8s cluster -b -m shell -a 'export DEBIAN_FRONTEND=noninteractive; apt-get install -y linux-headers-generic; cd /tmp; rm -rf mft-4.9.0-38-x86_64-deb.tgz mft-4.9.0-38-x86_64-deb; wget -q http://www.mellanox.com/downloads/MFT/mft-4.9.0-38-x86_64-deb.tgz; tar -xzf mft-4.9.0-38-x86_64-deb.tgz; cd /tmp/mft-4.9.0-38-x86_64-deb/; ./install.sh; mst start'

check_mellanox:
	cd os && ansible -i ../ansible/inventory_k8s cluster -b -m shell -a 'mlxconfig -d /dev/mst/mt4115_pciconf0 q | grep LINK_TYPE '

set_mellanox:
	cd os && ansible -i ../ansible/inventory_k8s cluster -b -m shell -a 'mlxconfig -y -d /dev/mst/mt4115_pciconf0 set LINK_TYPE_P1=1 LINK_TYPE_P2=2 '


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
# https://www.servethehome.com/configure-ipoib-mellanox-hcas-ubuntu-12041-lts/
# https://wiki.archlinux.org/index.php/InfiniBand#Over_IPoIB

# os_ssh_key:
# 	cd shared && ansible -i ../ansible/inventory_k8s shared_services_controller -m copy -a "src=playbooks/tmp/id_rsa dest=/home/ubuntu/genconf/ssh_key"


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
#https://serverfault.com/questions/472099/static-route-without-knowing-the-nexthop-linux

# sudo /usr/sbin/pppd updetach noauth silent nodeflate pty "/usr/bin/ssh ubuntu@10.60.253.41 sudo /usr/sbin/pppd nodetach notty noauth" ipparam vpn 10.0.8.1:10.0.8.2
# sudo ip route add 10.1.0.7/32 via 10.0.8.2

# ensure export OS_DOMAIN_NAME="default"
# for kubectl - see config https://github.com/kubernetes/cloud-provider-openstack/blob/master/docs/using-keystone-webhook-authenticator-and-authorizer.md
# create p2p tunnel for kubernetes api
# sudo /usr/sbin/pppd updetach noauth silent nodeflate pty "/usr/bin/ssh ubuntu@10.60.253.41 sudo /usr/sbin/pppd nodetach notty noauth" ipparam vpn 10.100.1.1:10.100.1.2
# route for k8s
# sudo ip route add 10.1.0.7/32  dev ppp0
# route for OpenStack keystone 
# sudo ip route add 10.60.253.1/32  dev ppp0



# sudo ip route add 10.1.0.7/32 via 10.100.1.2


# sudo /usr/sbin/pppd updetach noauth silent nodeflate pty "/usr/bin/ssh ubuntu@10.60.253.26 sudo /usr/sbin/pppd nodetach notty noauth" ipparam vpn 10.0.9.1:10.0.9.2
# sudo /usr/sbin/pppd updetach noauth silent nodeflate pty "/usr/bin/ssh ubuntu@10.60.253.47 sudo /usr/sbin/pppd nodetach notty noauth" ipparam vpn 10.0.10.1:10.0.10.2
# sudo /usr/sbin/pppd updetach noauth silent nodeflate pty "/usr/bin/ssh ubuntu@10.60.253.49 sudo /usr/sbin/pppd nodetach notty noauth" ipparam vpn 10.0.11.1:10.0.11.2
# ip route add 10.60.253.26/32 via 10.0.9.2
# ip route add 10.60.253.47/32 via 10.0.10.2
# ip route add 10.60.253.49/32 via 10.0.11.2

# iperf3 -c 10.60.x.x -b 45000M -w 256K -l 50000B -f m

# doesn't work
# ssh \
#   -o PermitLocalCommand=yes \
#   -o LocalCommand="sudo ifconfig tun5 192.168.244.2 pointopoint 192.168.244.1 netmask 255.255.255.0" \
#   -o ServerAliveInterval=60 \
#   -w 5:5 ubuntu@10.60.253.41 \
#   'sudo ifconfig tun5 192.168.244.1 pointopoint 192.168.244.2 netmask 255.255.255.0; echo tun0 ready'


# init_k8s:
# 	cd k8s && ansible-playbook -i ../ansible/inventory_k8s -i ./inventory $(LIMIT) playbooks/init_cluster.yml


# test DNS against busybox
test_dns:
	cd k8s && ansible -i ../ansible/inventory_k8s -i ./inventory k8s_master -m shell -a "kubectl describe pod busybox"
	cd k8s && ansible -i ../ansible/inventory_k8s -i ./inventory k8s_master -m shell -a "kubectl exec busybox -- cat /etc/resolv.conf"
	cd k8s && ansible -i ../ansible/inventory_k8s -i ./inventory k8s_master -m shell -a "kubectl exec busybox -- nslookup kubernetes.default.svc.cluster.local"
	cd k8s && ansible -i ../ansible/inventory_k8s -i ./inventory k8s_master -m shell -a "kubectl exec busybox -- nslookup busybox"
	cd k8s && ansible -i ../ansible/inventory_k8s -i ./inventory k8s_master -m shell -a "kubectl exec busybox -- nslookup www.ibm.com"

# kubectl run iperf3-server --rm -it --image networkstatic/iperf3 -- -s
# kubectl describe pod iperf3-server | grep -e 'Node:|IP:'
# kubectl run iperf3-client --rm -it --image networkstatic/iperf3 -- -c 192.168.65.64 -t 180
# kubectl describe pod iperf3-client | grep -e 'Node:|IP:'
# kubectl delete deployment iperf3-server


# do all the following sequentially!!!
# https://medium.com/@arthur.souzamiranda/kubernetes-with-openstack-cloud-provider-current-state-and-upcoming-changes-part-1-of-2-48b161ea449a
openstack_config:
	ansible -i ../inventory master -b -m shell -a  "kubectl --kubeconfig=/home/ubuntu/admin.conf get nodes"
	ansible-playbook -i ../inventory playbooks/docker.yml --tags "k8s_cloud_provider" \
	--extra-vars='provider_username=$(PROVIDER_USERNAME) provider_password=$(PROVIDER_PASSWORD)'

	ansible-playbook -i inventory/static playbooks/restart-hosts.yml \
	-e @playbooks/group_vars/master

	ansible-playbook -i ../inventory playbooks/restart-hosts.yml \
	-e @playbooks/group_vars/worker

	sleep 20
	#ansible -i ../inventory master -b -m shell -a  "kubectl  --kubeconfig=/home/ubuntu/admin.conf describe po kube-controller-manager -n kube-system"

# reboot the nodes and add the master label back in

label_master:
	ansible -i ../inventory master -m shell -a  "kubectl label node master1 node-role.kubernetes.io/master= --overwrite"

add_openstack: openstack_config label_master


# volume: eefaa82f-77d1-46a0-bc70-32cf02e074f4
# kubectl run my-shell --rm -i --tty --image mysql -- bash
# mysql -h 192.168.235.128 -u root -pyourpassword
cinder_mysql:
	ansible -i ../inventory master -m copy -a "src=./mysql.yaml dest=/home/ubuntu/mysql.yaml"
	ansible -i ../inventory master -b -m shell -a  "kubectl --kubeconfig=/home/ubuntu/admin.conf apply -f /home/ubuntu/mysql.yaml"
	sleep 5
	ansible -i ../inventory master -b -m shell -a  "kubectl --kubeconfig=/home/ubuntu/admin.conf describe pod mysql"

delete_mysql:
	ansible -i ../inventory master -b -m shell -a  "kubectl --kubeconfig=/home/ubuntu/admin.conf delete -f /home/ubuntu/mysql.yaml"

reset:
	for i in `ansible -i ../inventory master -b -m shell -a "kubectl --kubeconfig=/home/ubuntu/admin.conf get nodes" | grep -v NAME | awk '{print $$1}'`; \
	do \
	echo "draining $${i}"; \
    ansible -i ../inventory master -b -m shell -a "kubectl --kubeconfig=/home/ubuntu/admin.conf drain $${i} --delete-local-data --force --ignore-daemonsets"; \
    ansible -i ../inventory master -b -m shell -a "kubectl --kubeconfig=/home/ubuntu/admin.conf delete node $${i}"; \
	done
	ansible -i ../inventory master,workers -b -m shell -a  "/usr/bin/kubeadm reset"
	# nuclear options follow
	ansible -i ../inventory master,workers -b -m shell -a  "rm -rf /var/lib/kubelet /etc/kubernetes/* /var/lib/etcd /etc/cni /var/lib/kubelet/*; systemctl restart kubelet" || true
	ansible -i ../inventory master,workers -b -m shell -a  "systemctl stop docker; rm -rf /var/lib/docker/*; systemctl restart docker" || true

# run a test pod shell
# kubectl --kubeconfig=/home/ubuntu/admin.conf run my-shell --rm -i --tty --image ubuntu -- bash

delete_busybox:
	ansible -i ../inventory master -b -m shell -a  "kubectl --kubeconfig=/home/ubuntu/admin.conf delete -f /home/ubuntu/busybox.yaml"

# kubectl describe pod busybox
# kubectl exec busybox -- cat /etc/resolv.conf
# kubectl exec busybox -- nslookup kubernetes.default.svc.cluster.local
# kubectl exec busybox -- nslookup busybox
# kubectl exec busybox -- nslookup www.ibm.com


# node drain and drop out of cluster
# for node in $(kubectl --kubeconfig=/home/ubuntu/admin.conf get nodes | grep -v NAME | awk '{print $1}')
# do
#     kubectl --kubeconfig=/home/ubuntu/admin.conf drain $node --delete-local-data --force --ignore-daemonsets
#     kubectl --kubeconfig=/home/ubuntu/admin.conf delete node $node
# done

# net speed test
# kubectl --kubeconfig=/home/ubuntu/admin.conf run iperf3-server --rm -it --image networkstatic/iperf3 -- -s
# kubectl --kubeconfig=/home/ubuntu/admin.conf run iperf3-client --rm -it --image networkstatic/iperf3 -- -c 192.168.236.1 -t 30
# kubectl --kubeconfig=/home/ubuntu/admin.conf get pod -o wide

# https://rexray.readthedocs.io/en/stable/user-guide/schedulers/docker/plug-ins/openstack/#cinder
# docker plugin install --alias cinder rexray/cinder \
#   CINDER_AUTHURL="https://api.cloud.catalyst.net.nz:5000/v3" \
#   CINDER_USERNAME="piers@catalyst.net.nz" \
#   CINDER_PASSWORD="pass" \
#   CINDER_TENANTID="9bb82640b7bc403c8f25d3c0e6709978" \
#   CINDER_DOMAINNAME="Default" \
#   CINDER_REGIONNAME="nz-por-1"

# create a volume - docker volume create --driver=cinder --opt=size=2 demovol2
# run using a volume - https://rexray.readthedocs.io/en/stable/user-guide/schedulers/docker/
# docker run --rm --name voltest --mount source=demovol2,target=/mnt -d ubuntu:latest sleep 3600
# NOTE!!!  it keeps track of which volumes you create and you can't disable the
#   plugin until they are deleted!:
# docker plugin disable cinder; docker plugin rm cinder

