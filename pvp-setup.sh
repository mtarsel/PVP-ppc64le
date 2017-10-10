#!/bin/bash
#Written by Mick Tarsel
#setup PVP for ppc64le to test dpdk with ovs
# Currently does not do anything with the guest but define it... must configure guest manually

#grubby  --args="hugepages=2048 isolcpus=8,16 numa=off intel_iommu=on" --update-kernel /boot/vmlinuz-3.10.0-675.el7.ppc64le 

# Pin all interrupts on CPU0 for better test results- I did not do this
# MASK=1 # hexadecimal mask value, 1 correspond to CPU0
# for I in `ls -d /proc/irq/[0-9]*` ; do echo $MASK > ${I}/smp_affinity ; done
is_OVS_running(){

	ovsstatus=$(systemctl is-active openvswitch)

	if [ $ovsstatus == 'inactive' ]; then
		echo -e "\n****ERROR**** OVS service is $ovsstatus"
		echo "EXITING NOW"
		exit 1
	fi
}

is_OVS_running
echo -e "\n Starting script now..."

systemctl stop irqbalance
echo -e "\n irqbalance stopped\n"

#TODO - check /proc/meminfo | grep Huge
sysctl -w vm.nr_hugepages=2048

echo -e "\n Hugepages set\n"

if ! getenforce | grep -q "Permissive\|Disabled";then
        echo "selinux is enabled"
	echo "Please change entry in /etc/selinux/config file and run:"
	echo -e "\t setenforce Permissive"
	echo "EXITING NOW"
	exit 0
fi

echo -e "\n selinux is ok\n"

modprobe vfio-pci

echo -e "\n vfio module loaded\n"

ppc64_cpu --smt=off

echo -e "\nsmt off\n"

echo 'DPDK_OPTIONS="-c 10101 -n 4 --socket-mem 1024,0"' >> /etc/sysconfig/openvswitch

echo -e "\n options written to ovs config. restarting now....\n"

systemctl restart openvswitch
sleep 2

is_OVS_running

if [ $(pgrep ovs | wc -l) -eq 0 ];then
	echo "****ERROR**** OVS processes not started"
	echo "EXITING NOW"
	exit 1
fi

echo -e "\nadding ovs options via cmdline\n"

ovs-vsctl set Open_vSwitch . other_config:pmd-cpu-mask=10101
ovs-vsctl --no-wait  set Open_vSwitch . other_config:dpdk-socket-mem="1024"

if ! ovs-vsctl get Open_vSwitch . iface_types | grep -q "dpdk"; then
	echo "****ERROR**** dpdk not configured in OVS."
	echo "EXITING NOW"
	exit 1
fi

echo -e "\ngetting pci slots and setting override\n"

#get PCI slot ids for Intel i40e XL710
pcis=$(lspci | grep XL | cut -d ' ' -f1 | cut -d$'\n' -f1)
pci1=$(echo $pcis | cut -d ' ' -f1)
pci2=$(echo $pcis | cut -d ' ' -f2)

#2 ways do the same. RH uses driverctl
#driverctl set-override $pci1 vfio-pci
#driverctl set-override $pci2 vfio-pci
#dpdk-devbind --bind=vfio-pci 0002:01:00.1
#or dpdk-devbind --bind=vfio-pci 0002:01:00.0
if [ $(driverctl list-devices | grep vfio-pci | wc -l) -eq 0 ]; then
	echo "****ERROR**** vfio not configured"
	echo "$pci1 and/or $pci2 are not configured with vfio"
	echo "EXITING NOW"
	exit 1
fi	

echo "\n adding bridges, ports, and flows to OVS\n"
#TODO before we configure this maybe grab the bridge test from runall

#setup ovs
ovs-vsctl add-br br0 -- set bridge br0 datapath_type=netdev
ovs-vsctl add-port br0 dpdk0 -- set Interface dpdk0 type=dpdk options:dpdk-devargs=$pci1 ofport_request=10 
ovs-vsctl add-port br0 dpdk1 -- set Interface dpdk1 type=dpdk options:dpdk-devargs=$pci2 ofport_request=11

#Delete default flow and add two flows to forward packets between the physical devices.
ovs-ofctl del-flows br0
#ovs-ofctl add-flow br0 in_port=10,action=11
#ovs-ofctl add-flow br0 in_port=11,action=10

#add some ports for otherside
ovs-vsctl add-port br0 vhost0 \
-- set interface vhost0 type=dpdkvhostuser ofport_request=20
ovs-vsctl add-port br0 vhost1 \
-- set interface vhost1 type=dpdkvhostuser ofport_request=21

#setup the guest
#RH uses .dsk but we need to upgrade qemu to >2.7 to use vhost-user-client ports
#TODO vim /etc/libvirt/qemu.conf 
	#user = "root"
	#group = "root"
echo -e "\ndefine gust via XML\n"

virsh define ./guest-pvp-rhel.xml

echo -e "\nadding more flowss\n"

#Single direction:
ovs-ofctl add-flow br0 in_port=10,actions=20
ovs-ofctl add-flow br0 in_port=21,actions=11
#The other direction:
ovs-ofctl add-flow br0 in_port=11,actions=21
ovs-ofctl add-flow br0 in_port=20,actions=10

echo -e "\ndone."
