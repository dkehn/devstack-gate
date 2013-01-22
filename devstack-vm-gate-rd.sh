#!/bin/bash

# Script that is run on the devstack vm; configures and
# invokes devstack.

# Copyright (C) 2011-2012 OpenStack LLC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
#
# See the License for the specific language governing permissions and
# limitations under the License.

# ##############################################################################
# Stuff for testing purposes only
# ##############################################################################
set -o xtrace

TRACE="no"
DEV_BASE="/home/stack/reddwarf"
export DEVSTACK_DIR="$DEV_BASE/devstack"
export REDSTACK_DIR="$DEV_BASE/reddwarf/reddwarf-integration"

# NOTE: Tese are normally set in devstack-vm-gate-wrap.sh
export DEVSTACK_GATE_REDDWARF=${DEVSTACK_GATE_REDDWARF:-1}
export DEVSTACK_GATE_TEMPEST=${DEVSTACK_GATE_TEMPEST:-0}
export DEVSTACK_GATE_POSTGRES=${DEVSTACK_GATE_POSTGRES:-0}
export DEVSTACK_GATE_TEMPEST_COVERAGE=${DEVSTACK_GATE_TEMPEST_COVERAGE:-0}
export DEVSTACK_GATE_CINDER=${DEVSTACK_GATE_CINDER:-0}
export DEVSTACK_CINDER_SECURE_DELETE=${DEVSTACK_CINDER_SECURE_DELETE:-0}
export DEVSTACK_GATE_QUANTUM=${DEVSTACK_GATE_QUANTUM:-0}
export DEVSTACK_GATE_GRENADE=${DEVSTACK_GATE_GRENADE:-""}
export DEVSTACK_GATE_VIRT_DRIVER=${DEVSTACK_GATE_VIRT_DRIVER:-libvirt}
export DEVSTACK_GATE_TEMPEST_FULL=${DEVSTACK_GATE_TEMPEST_FULL:-0}

BASE="/opt/stack"
DEST="$BASE/new"
PROG=$(basename $0)
echo "Debug version of $PROG, Starting....."

source $DEVSTACK_DIR/functions

# move the last run to $BASE/old
echo "Moving the last run $BASE/new to $BASE/old"
if [ -d "$BASE/new" ]; then
    if [ -d $BASE/old ]; then
	sudo rm -rf $BASE/old
    fi
    sudo mv $BASE/new $BASE/old
    # sudo rm -rf $BASE/new
fi
if [ -d $BASE/data ]; then
    if [ -d $BASE/data-old ]; then
	sudo rm -rf $BASE/data-old
    fi
    sudo mv $BASE/data $BASE/data-old
fi

# -- this is to deal with the temporary state of the devstack/reddwarf.
# TODO - the local.sh in here should have mods on it.
echo "Creating $BASE/new/devstack"
mkdir -p $BASE/new/devstack
echo "Coping the $DEVSTACK_DIR to $BASE/new/devstack"
cp -rf $DEVSTACK_DIR $BASE/new
# make sure we are coping the right lcoal.sh over
rm -f $DEVSTACK_DIR $BASE/new/local.sh

# ##############################################################
set -o errexit

cd $BASE/new/devstack

rm -f localrc

ENABLED_SERVICES=g-api,g-reg,key,n-api,n-crt,n-obj,n-cpu,n-sch,horizon,mysql,rabbit

if [ "$DEVSTACK_GATE_TEMPEST" -eq "1" ]; then
    ENABLED_SERVICES=$ENABLED_SERVICES,tempest
fi

if [ "$ZUUL_BRANCH" == "stable/diablo" ]; then
    export DEVSTACK_GATE_TEMPEST=0
fi

if [ "$DEVSTACK_GATE_REDDWARF" -eq "1" ]; then
    ENABLED_SERVICES=$ENABLED_SERVICES,reddwarf
    # given that the change in reddwarf to run from local.sh
    # we nned to pull the reddwarf & reddwarf-client repos 
    # and get it into the right place. In addition, setup the 
    # reddwarf-integration/local.sh script into the devstack dir.
    REDDWARF_DIR=$DEST/reddwarf/
    REDDWARFCLIENT_DIR=$DEST/python-reddwarfclient/
    cdir="$PWD"

    # reddwarf service git paths     
    GIT_BASE=https://github.com
    REDDWARF_REPO=${GIT_BASE}/stackforge/reddwarf.git
    REDDWARF_BRANCH=master
    REDDWARFCLIENT_REPO=${GIT_BASE}/stackforge/python-reddwarfclient.git
    REDDWARF_INTEGRATION_BRANCH=master
    REDDWARF_INTEGRATION_REPO=${GIT_BASE}/stackforge/reddwarf-integration.git
    REDDWARFCLIENT_BRANCH=master
    
    git_clone $REDDWARFCLIENT_REPO $REDDWARFCLIENT_DIR $REDDWARFCLIENT_BRANCH
    git_clone $REDDWARF_REPO $REDDWARF_DIR $REDDWARF_BRANCH

    # now to get the local.sh file from the reddwarf-integration repo
    if [ -d $REDSTACK_DIR ]; then
	rm -rf $REDSTACK_DIR
    fi
    git_clone $REDDWARF_INTEGRATION_REPO $REDSTACK_DIR "refs/changes/50/19150/3"
    cp $REDSTACK_DIR/scripts/local.sh /$BASE/new/devstack
    cd "$cdir"
fi


SKIP_EXERCISES=boot_from_volume,client-env

if [ "$ZUUL_BRANCH" == "stable/diablo" ] ||
   [ "$ZUUL_BRANCH" == "stable/essex" ]; then
    ENABLED_SERVICES=$ENABLED_SERVICES,n-vol,n-net
    SKIP_EXERCISES=$SKIP_EXERCISES,swift
elif [ "$ZUUL_BRANCH" == "stable/folsom" ]; then
    ENABLED_SERVICES=$ENABLED_SERVICES,n-net,swift
    if [ "$DEVSTACK_GATE_CINDER" -eq "1" ]; then
	ENABLED_SERVICES=$ENABLED_SERVICES,cinder,c-api,c-vol,c-sch
    else
	ENABLED_SERVICES=$ENABLED_SERVICES,n-vol
    fi
else # master
    ENABLED_SERVICES=$ENABLED_SERVICES,swift,cinder,c-api,c-vol,c-sch,n-cond
    if [ "$DEVSTACK_GATE_QUANTUM" -eq "1" ]; then
	ENABLED_SERVICES=$ENABLED_SERVICES,quantum,q-svc,q-agt,q-dhcp,q-l3,q-meta
	cat <<EOF >>localrc
Q_USE_DEBUG_COMMAND=True
NETWORK_GATEWAY=10.1.0.1
EOF
    else
	ENABLED_SERVICES=$ENABLED_SERVICES,n-net
    fi
fi
if [ "$DEVSTACK_GATE_REDDWARF" -eq "1" ]; then
    SKIP_EXERCISES=$SKIP_EXERCISES,euca,volumes,floating_ips,quantum-adv-test
fi

echo "Creating $PWD/localrc file"
# ENABLED_SERVICES=g-api,g-reg,key,n-api,n-crt,n-obj,n-cpu,n-sch,horizon,mysql,rabbit,tempest,swift,cinder,c-api,c-vol,c-sch,n-cond,n-net
cat <<EOF >>localrc
DEST=/opt/stack/new
ACTIVE_TIMEOUT=60
BOOT_TIMEOUT=90
ASSOCIATE_TIMEOUT=60
TERMINATE_TIMEOUT=60
MYSQL_PASSWORD=secret
RABBIT_PASSWORD=secret
ADMIN_PASSWORD=secret
SERVICE_PASSWORD=secret
SERVICE_TOKEN=111222333444
SWIFT_HASH=1234123412341234
ROOTSLEEP=0
ERROR_ON_CLONE=False
ENABLED_SERVICES=g-api,g-reg,key,n-api,n-crt,n-obj,n-cpu,n-sch,horizon,mysql,rabbit,swift,cinder,c-api,c-vol,c-sch,n-cond,n-net
#ENABLED_SERVICES=g-api,g-reg,key,n-api,n-crt,n-obj,n-cpu,n-sch,horizon,mysql,rabbit,tempest,swift,cinder,c-api,c-vol,c-sch,n-cond,n-net
SKIP_EXERCISES=boot_from_volume,client-env
SERVICE_HOST=127.0.0.1
SYSLOG=True
SCREEN_LOGDIR=/opt/stack/new/screen-logs
LOGFILE=/opt/stack/new/devstacklog.txt
VERBOSE=True
FIXED_RANGE=10.1.0.0/24
FIXED_NETWORK_SIZE=32
VIRT_DRIVER=libvirt
SWIFT_REPLICAS=1
export OS_NO_CACHE=True
CINDER_SECURE_DELETE=False
API_RATE_LIMIT=False
VOLUME_BACKING_FILE_SIZE=5G
EOF

if [ "$DEVSTACK_CINDER_SECURE_DELETE" -eq "0" ]; then
   cat <<\EOF >>localrc
CINDER_SECURE_DELETE=False
EOF
fi

if [ "$DEVSTACK_GATE_POSTGRES" -eq "1" ]; then
        cat <<\EOF >>localrc
use_database postgresql
EOF
fi

if [ "$DEVSTACK_GATE_VIRT_DRIVER" == "openvz" ]; then
   cat <<\EOF >>localrc
SKIP_EXERCISES=${SKIP_EXERCISES},volumes
DEFAULT_INSTANCE_TYPE=m1.small
DEFAULT_INSTANCE_USER=root
EOF
   cat <<EOF >>exerciserc
DEFAULT_INSTANCE_TYPE=m1.small
DEFAULT_INSTANCE_USER=root
EOF
fi

if [ "$DEVSTACK_GATE_REDDWARF" -eq "1" ]; then
    # need to add a few items for the reddwarf & local.sh
    echo "DATABASE_USER=root" >>localrc
    # NOTE: the MUST match the MYSQL_PASSWORD variable.
    echo "DATABASE_PASSWORD=secret" >>localrc
fi

if [ "$DEVSTACK_GATE_TEMPEST" -eq "1" ]; then
    # We need to disable ratelimiting when running
    # Tempest tests since so many requests are executed
    echo "API_RATE_LIMIT=False" >> localrc
    # Volume tests in Tempest require a number of volumes
    # to be created, each of 1G size. Devstack's default
    # volume backing file size is 2G, so we increase to 5G
    # (apparently 4G is not always enough).
    echo "VOLUME_BACKING_FILE_SIZE=5G" >> localrc
fi

# Make the workspace owned by the stack user
sudo chown -R stack:stack $BASE/new
if [ -d $BASE/old ]; then
    sed -e 's|$BASE/new|$BASE/old|' < $BASE/new/devstack/localrc \
      > $BASE/old/devstack/localrc
    sed -e 's|$BASE/new|$BASE/old|' < $BASE/new/devstack/exerciserc \
      > $BASE/old/devstack/exerciserc

    sudo chown -R stack:stack $BASE/old
fi

if [ "$DEVSTACK_GATE_GRENADE" != "" ]; then
    sudo echo "GRENADE_PHASE=work"  >>$BASE/old/devstack/localrc
    sudo echo "GRENADE_PHASE=trunk" >>$BASE/new/devstack/localrc
    cat <<EOF >$BASE/new/grenade/localrc
WORK_DEVSTACK_DIR=$BASE/old/devstack
TRUNK_DEVSTACK_DIR=$BASE/new/devstack
EOF

    cd $BASE
    sudo -H -u stack ./grenade.sh
else
    echo "Running devstack"
    sudo -H -u stack ./stack.sh

    echo "Removing sudo privileges for devstack user"
    sudo rm /etc/sudoers.d/50_stack_sh

    echo "Running devstack exercises"
    #sudo -H -u stack ./exercise.sh
fi

if [ "$DEVSTACK_GATE_REDDWARF" -eq "1" ]; then
    echo "Configuring reddwarf for redstack testing"
    cd $BASE/new/devstack
    sudo -H -u stack $REDSTACK_DIR/scripts/redstack post-devstack mysql

    # TODO - this is where the call to the redstack testing should be 
    #        implemented.
    echo "Running redstack tests suite."
    sudo -H -u stack $REDSTACK_DIR/scripts/redstack simple-tests

    echo "Cleanup, post reddwarf testing"
    sudo -H -u stack $DEV_BASE/gate-t/testing_configure_reddwarf.sh --del-users

fi

echo "DEBUG ********* FINISHED"
sleep 4
exit 0

if [ "$DEVSTACK_GATE_TEMPEST" -eq "1" ]; then
    if [ ! -f "$BASE/new/tempest/etc/tempest.conf" ]; then
        echo "Configuring tempest"
        cd $BASE/new/devstack
        sudo -H -u stack ./tools/configure_tempest.sh
    fi
    cd $BASE/new/tempest
    echo "Running tempest smoke tests"
    sudo -H -u stack NOSE_XUNIT_FILE=nosetests-smoke.xml nosetests --with-xunit -sv --attr=type=smoke tempest
    RETVAL=$?
    if [[ $RETVAL = 0 && "$DEVSTACK_GATE_TEMPEST_FULL" -eq "1" ]]; then
      echo "Running tempest full test suite"
      sudo -H -u stack NOSE_XUNIT_FILE=nosetests-full.xml nosetests --with-xunit -sv -a '!smoke' tempest
    fi
else
    # Jenkins expects at least one nosetests file.  If we're not running
    # tempest, then write a fake one that indicates the tests pass (since
    # we made it past exercise.sh.
    cat > $WORKSPACE/nosetests-fake.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?><testsuite name="nosetests" tests="0" errors="0" failures="0" skip="0"></testsuite>
EOF
fi
