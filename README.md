# PVP-ppc64le
Setup Physical Virtual Physical env to test OVS and the DPDK

You are responsible for getting the .iso file to boot and changing XMl file in order to boot the guest.

### Warning
Ports of type vhost-user are currently deprecated and will be removed in a future release.
Use of vhost-user ports requires QEMU >= 2.2; vhost-user ports are deprecated.

Verify your version of qemu and use vhost-user-client (dpdkvhostuserclient) ports if possible.
