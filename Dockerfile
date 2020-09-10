# NETCONF/YANG interoperability testing container with NSO
#
# We use the standard ubuntu bas image.
FROM ubuntu:20.04
LABEL description="Docker image for NETCONF and YANG interop testing with NSO." maintainer="jojohans@cisco.com"

# Install the extra packages we need to run NSO, pioneer and DrNED
# Examiner. Only libssl is actually necessary for NSO itself, the
# python packages and xsltproc and libxml2-utils are needed by DrNED
# Examiner and DrNED.
        ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
        apt-utils  \
        default-jre-headless \
        git \
        libssl-dev \
        make \
        openssh-client \
        python-is-python3 \
        python3-lxml \
        python3-paramiko \
        python3-pexpect \
        python3-pytest \
        libxml2-utils \
        vim \
        xsltproc

RUN ln -sv /usr/bin/pytest-3 /usr/bin/pytest

# Default to latest NSO version.  Override on the command line with
# --build-arg ver=<version>.
#
# Note: host.docker.internal is the only way to get to the host (the
# Mac) when running Docker Desktop on macOS. In a more realistic
# setting dev_ip should be set to the IP of the device.
ARG dev_ip=host.docker.internal
ARG dev_name=nc0
ARG dev_pass=admin
ARG dev_port=2022
ARG dev_user=admin
ARG ned_name=router
ARG ned_vendor=cisco
ARG ned_ver=1.0
ARG nso_ver=5.4

# What ncsrc usually does...
ENV NCS_DIR=/nso LD_LIBRARY_PATH=/nso/lib PATH=/nso/bin:$PATH PYTHONPATH=/nso/src/ncs/pyapi
ENV PACKAGES=/packages

# Install NSO in the container and create a workspace.
COPY resources/NSO-$nso_ver/nso-$nso_ver.linux.x86_64.signed.bin /tmp
RUN (cd /tmp && ./nso-$nso_ver.linux.x86_64.signed.bin)
RUN /tmp/nso-$nso_ver.linux.x86_64.installer.bin $NCS_DIR

RUN echo 'export PS1="$ "' >> /root/.profile

# Create a NETCONF NED based on the YANG-models we supply
COPY resources/yangs/ /tmp
RUN ncs-make-package --netconf-ned /tmp $ned_name --dest $PACKAGES/$ned_name-nc-$ned_ver --no-java --no-python --no-netsim --vendor $ned_vendor --package-version $ned_ver
RUN make -C $PACKAGES/$ned_name-nc-$ned_ver/src clean all

### Create a netsim network
##RUN ncs-netsim --dir /interop create-network /interop/neds/$ned_name-nc-$ned_ver 1 nc

# Install pioneer and drned-xmnr
RUN (cd $PACKAGES && git clone -q https://github.com/NSO-developer/drned-xmnr.git)
RUN make -C $PACKAGES/drned-xmnr/src clean all

# Support mounting workspace directory from the host.
RUN ncs-setup --dest /interop --package $PACKAGES/drned-xmnr --package $PACKAGES/$ned_name-nc-$ned_ver

# Allow connections to the NSO IPC-port from any IP-address
RUN sed -i 's/  <load-path>/  <ncs-ipc-address>\n    <ip>0.0.0.0<\/ip>\n  <\/ncs-ipc-address>\n\n  <load-path>/' interop/ncs.conf

# DrNED Examiner configuration state directory
RUN mkdir interop/xmnr

# Expose logs and xmnr directories to simplify troubleshooting
VOLUME interop/logs interop/xmnr

# Enable verbose logging
COPY resources/init.xml interop/ncs-cdb

# Copy parameters to init file
RUN sed -i "s/DEVUSER/$dev_user/; \
            s/DEVPASS/$dev_pass/; \
            s/DEVNAME/$dev_name/; \
            s/DEVIP/$dev_ip/;     \
            s/DEVPORT/$dev_port/; \
            s/NEDNAME/$ned_name/; \
            s/NEDVER/$ned_ver/;   \
            s/NEDVENDOR/$ned_vendor/" interop/ncs-cdb/init.xml

# Set working directory for NSO to the top directory of the mounted
# example.
WORKDIR interop

# Initially we only expose NETCONF (over ssh) and IPC ports.
# Uncomment to expose ports for other northbound protocols as
# necessary.
EXPOSE 2022 2023 2024 4569 8008 8088

# Cleanup
RUN apt-get autoremove -y && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Finally, start NSO
CMD ["/nso/bin/ncs", "--foreground", "-v", "--addloadpath", "/nso/interop"]
