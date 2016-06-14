## Neutron docker

### Using

```
git clone git@172.27.10.10:openstack/docker-neutron.git
cd docker-neutron
./build.sh
```
Result will be neutron image in a local image registry.

### Services
This image can be run in two roles. Either as controller or as compute. This two roles differs in a services which are exectuted by supervisor.

### Controller role
Following services are exectuted when variable `NEUTRON_CONTROLLER` is set to `true` (default):

  * neutron-server
  * ...

### Compute role
When `NEUTRON_CONTROLLER` set to `false` only one service is executed:

  * neutron-openvswitch-agent

### Communication with Openvswitch Database

Neutron server communicates with OpenvSwitch on host by reading/writing to ovs database. This database is located in `/var/lib/openvswitch/conf.db` on Debian. Therefore we need to make this file accessible for docker container:
We do it by using `-v` volume option in `docker run` command:

```
docker run -d --net=host -v /var/lib/openvswitch:/var/lib/openvswitch -it neutron:latest
```

