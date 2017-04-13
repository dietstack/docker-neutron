FROM osmaster
MAINTAINER Kamil Madac (kamil.madac@t-systems.sk)

ARG http_proxy
ARG https_proxy
ARG no_proxy

# Source codes to download
ENV repo="https://github.com/openstack/neutron" branch="stable/newton" commit=""

# Download neutron source codes
RUN if [ -z $commit ]; then \
       git clone $repo --single-branch --depth=1 --branch $branch; \
    else \
       git clone $repo --single-branch --branch $branch; \
       cd neutron && git checkout $commit; \
    fi

# Apply source code patches
RUN mkdir -p /patches
COPY patches/* /patches/
RUN /patches/patch.sh

# Install neutron with dependencies
RUN cd neutron; apt-get update; \
    apt-get install -y --no-install-recommends sudo bridge-utils openvswitch-switch dnsmasq dnsmasq-utils iptables ipset ebtables; \
    pip install -r requirements.txt -c /requirements/upper-constraints.txt; \
    pip install supervisor python-memcached py2-ipaddress; \
    python setup.py install; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# prepare directories for supervisor
RUN mkdir -p /etc/supervisor.d /var/log/supervisord

# prepare necessary stuff
RUN mkdir -p /var/log/neutron /var/run/neutron; \
    useradd -M -s /sbin/nologin neutron

# copy neutron local image configs
COPY configs/neutron /etc/neutron/

# copy supervisor configs
COPY configs/supervisord/supervisord.conf /etc
COPY configs/supervisord/supervisor.d/* /etc/supervisor.d/

# external volumes
VOLUME /neutron-override
VOLUME  /lib/modules

# copy startup scripts
COPY scripts /app

# Define workdir
WORKDIR /app
RUN chmod +x /app/*

ENTRYPOINT ["/app/entrypoint.sh"]

# Define default command.
CMD ["/usr/local/bin/supervisord", "-c", "/etc/supervisord.conf"]
