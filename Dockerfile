FROM osmaster

MAINTAINER Kamil Madac (kamil.madac@t-systems.sk)

ENV http_proxy="http://172.27.10.114:3128"
ENV https_proxy="http://172.27.10.114:3128"
ENV no_proxy="locahost,127.0.0.1"

# Source codes to download
ENV neutron_repo="https://github.com/openstack/neutron"
ENV neutron_branch="stable/liberty"
ENV neutron_commit=""

# some cleanup
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/*

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
    apt-get install -y --no-install-recommends \
    pip install -r requirements.txt; \
    pip install supervisor mysql-python; \
    python setup.py install

# prepare directories for supervisor
RUN mkdir -p /etc/supervisor.d /var/log/supervisord

# prepare necessary stuff
RUN mkdir -p /var/log/neutron && \
    useradd -M -s /sbin/nologin neutron

# copy neutron configs
COPY configs/neutron/* /etc/neutron/

# copy supervisor configs
COPY configs/supervisord/supervisord.conf /etc
COPY configs/supervisord/supervisor.d/* /etc/supervisor.d/

# external volume
VOLUME /neutron-override

# copy startup scripts
COPY scripts /app

# Define workdir
WORKDIR /app
RUN chmod +x /app/*

ENTRYPOINT ["/app/entrypoint.sh"]

# Define default command.
CMD ["/usr/local/bin/supervisord", "-c", "/etc/supervisord.conf"]
