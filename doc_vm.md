# How to set up local services for dev VMs

*Note: replace USERNAME with your own username below.*

## Install dependencies

`apt-get install bridge-utils uml-utilities dnsmasq qemu-system-x86`

## Configure networking

1. Global bridge interface

In `/etc/network/interfaces`:

`source-directory /etc/network/interfaces.d`

In `/etc/network/interfaces.d/vm`:

```
auto vmbr0
iface vmbr0 inet static
        address 172.16.0.254
        netmask 255.255.0.0
        pre-up brctl addbr $IFACE
        bridge_stp off
        bridge_fd 0
        bridge_maxwait 0
```

Start it:

`ifup vmbr0`

2. Host interfaces for VMs

Make the qemu bridge helper setuid root:
```
chown :kvm /usr/lib/qemu/qemu-bridge-helper
chmod u+s,o= /usr/lib/qemu/qemu-bridge-helper
```

In `/etc/qemu/bridge.conf`:

```
allow vmbr0
```


3. DHCP+DNS

In `/etc/default/dnsmasq`:

```
DNSMASQ_EXCEPT="lo"
```

In `/etc/dnsmasq.d/vm`:

```
bind-interfaces
interface=vmbr0

dhcp-range=172.16.0.129,172.16.0.253,0h

dhcp-host=DE:AD:BE:EF:00:01,172.16.1.33,12h
dhcp-host=DE:AD:BE:EF:00:02,172.16.2.33,12h
dhcp-host=DE:AD:BE:EF:00:03,172.16.3.33,12h
dhcp-host=DE:AD:BE:EF:00:04,172.16.4.33,12h
```

Start it:

`systemctl restart dnsmasq.service`

4. For Internet access

In `/etc/rc.local`, one line per external interface (so, e.g. include
`wlan0` on a laptop):

`iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE`

5. For easy names

In `/etc/hosts`:

```
172.16.1.33		vm1 vm
172.16.2.33		vm2
172.16.3.33		vm3
172.16.4.33		vm4
```

## Qemu/KVM

1. Permissions

`adduser USERNAME kvm`

2. Profit

### Debian cloud

`wget https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-nocloud-amd64.qcow2`

`runvm.sh -d debian-12-nocloud-amd64.qcow2`

### Debian netinst

`wget https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.2.0-amd64-netinst.iso`

`qemu-img create -f qcow2 -o compression_type=zstd debian.qcow2 20G`

`runvm.sh -w -d debian.qcow2 -- -cdrom debian-12.2.0-amd64-netinst.iso`
