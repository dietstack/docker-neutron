FROM osmaster

MAINTAINER Kamil Madac (kamil.madac@t-systems.sk)

ENV http_proxy="http://172.27.10.114:3128"
ENV https_proxy="http://172.27.10.114:3128"
ENV no_proxy="localhost,127.0.0.1"

# Source codes to download
ENV neutron_repo="https://github.com/openstack/neutron"
ENV neutron_branch="stable/liberty"
ENV neutron_commit=""

# Download neutron source codes
RUN git clone $neutron_repo --single-branch --branch $neutron_branch;

# Checkout commit, if it was defined above
RUN if [ ! -z $neutron_commit ]; then cd neutron && git checkout $neutron_commit; fi

# Apply source code patches
RUN mkdir -p /patches
COPY patches/* /patches/
RUN /patches/patch.sh

# Install neutron with dependencies
RUN cd neutron; apt-get update; \
    apt-get install -y --no-install-recommends sudo openvswitch-switch dnsmasq dnsmasq-utils iptables; \
    pip install -r requirements.txt; \
    pip install supervisor mysql-python; \
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

# copy startup scripts
COPY scripts /app

# Define workdir
WORKDIR /app
RUN chmod +x /app/*

ENTRYPOINT ["/app/entrypoint.sh"]

# Define default command.
CMD ["/usr/local/bin/supervisord", "-c", "/etc/supervisord.conf"]
