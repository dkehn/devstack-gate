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

set -o errexit

PROG=$(basename $0)
BASE=${BASE:-"/opt/stack"}
REDDWARF_INTEGRATION_CONF_DIR=${REDDWARF_INTEGRATION_CONF_DIR:-"/tmp/reddwarf-integration/"}
DEVSTACK_DIR=${DEVSTACK_DIR:-"$BASE/new/devstack"}
DEST=${DEST:-"$BASE/new"}


#export OS_SERVICE_ENDPOINT=$OS_AUTH_URL


# ###############################################################
# MUST REMOVE AFTE#R DEBUGGED
# ###############################################################
STAND_ALONE="False"
if [ "$STAND_ALONE" == "True" ]; then
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

fi

USERHOME=$HOME
# ##################################################################
# -- command setups
PS_CMD="/bin/ps -eaf"
CP_CMD="/bin/cp"
RM_CMD="/bin/rm -rf"
ROOT_DIR=$(dirname $0)
VERSION="1.0"
TRACE="no"
GLANCE="/usr/local/bin/glance"
NOVA="/usr/local/bin/nova"
KEYSTONE="/usr/local/bin/keystone"

VERBOSE="True"
XTRACE=$(set +o | grep xtrace)
OP_CMD="add"
set +o xtrace
set -x

##################################################################
#                           FUNCTIONS                            #
##################################################################
BMOD="<--"
EMOD="-->"
SPACE=" "
MSGOUT_IND=0
# msgout() - prints message with severity and time to stdout.
function msgout() {
    local level=$1
    local str=$2
    local tm=`date +"%Y-%m-%d %H:%M:%S"`
    if [ "$level" == "DEBUG" ] && [ "$VERBOSE" == "False" ]; then
            return 0
    else
        echo "$tm: $PROG [$$]: $1: $str"
    fi

    return 0
}

function func_out() {
    local level=$1
    local func=$2
    local str=$3
    local iodir=$4
    local ind=0
    local m=""
    local im1=""

    if [ "$iodir" = "$BMOD" ]; then
	MSGOUT_IND="$((MSGOUT_IND + 1))"     
	ind="$((MSGOUT_IND * 2))" 
    else
	ind="$((MSGOUT_IND * 2))" 
	MSGOUT_IND="$((MSGOUT_IND - 1))"     
    fi 

    if [ $ind = 0 ]; then
	im1=""
    else
	for (( i=0; i<$ind; i++ )); do im1+=" "; done 
	im1+='|'
    fi

    m="$func $im1$iodir $str"
    msgout "$level" "$m"
    return 0
}

function func_begin() {
#    func_out "DEBUG" $1 $2 $BMOD 
    msgout "DEBUG" "$1$BMOD: $2"
}

function func_end() {
#    func_out "DEBUG" $1 $2 $EMOD 
    msgout "DEBUG" "$1$EMOD: $2"
}

# *****************************************************************************
# usage()
#
function usage {
  echo "Usage: $0 [OPTION]..."
  echo "Run $PROG with"
  echo ""
  echo "  -x, --trace              Turn on the script tracing option"
  echo "  -a, --add-users          Add the redstack users to keystone"
  echo "  -d, --del-users          Delete the redstack users to keystone"
  echo "  -h, --help               Print this usage message"
  echo "  -v, --version            Prints the script version"
  echo "  --hide-elapsed           Don't print the elapsed time for each test along with slow test list"
  echo ""
  exit
}

function process_option {
    local mod="process_options"

    func_begin "$mod" "($1)"
  
    case "$1" in
	-h|--help) usage;;
	-v|--version) echo "$PROG: Vers=$VERSION"; exit 0;;
	-x|--trace) TRACE="yes";;
	-a|--add-users) OP_CMD="add";;
	-d|--del-users) OP_CMD="delete";;
	-*) testropts="$testropts $1";;
	*) testrargs="$testrargs $1"
    esac
}
# ******************************************************************************
# mod_test_conf() - modifies the test.conf file in user $HOME directory.
# 
# params: N/A
# returns: None
#
function mod_test_conf() {
    local mod="mod_test_conf"
    func_begin "$mod" ""

    PATH_REDDWARF="$DEST/reddwarf"
    REDSTACK_SCRIPTS="$REDDWARF_INTEGRATION_CONF_DIR/scripts"
    ESCAPED_PATH_REDDWARF=`echo $PATH_REDDWARF | sed 's/\//\\\\\//g'`
    ESCAPED_REDSTACK_SCRIPTS=`echo $REDSTACK_SCRIPTS | sed 's/\//\\\\\//g'`

    msgout "DEBUG" "cp $REDSTACK_SCRIPTS/conf/test_begin.conf $USERHOME/TEST.CONF"

    cp $REDSTACK_SCRIPTS/conf/test_begin.conf $USERHOME/test.conf
    sed -i "s/\/integration\/report/$ESCAPED_REDSTACK_SCRIPTS\/\.\.\/report/" $USERHOME/test.conf
    EXTRA_CONF=$REDSTACK_SCRIPTS/conf/test.extra.conf
    if [ -e $EXTRA_CONF ]; then
        cat $EXTRA_CONF >> $USERHOME/test.conf
    fi
    cat $REDSTACK_SCRIPTS/conf/test_end.conf >> $USERHOME/test.conf
    func_end "$mod" ""
}

# ******************************************************************************
# get_user_id() - return the user_id based upon the provided user
# 
# params: $1 token
#         $2 user name for which the user_id is associated.
# returns: tennat_id code.
#
function get_user_id() {
    echo `$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $1 \
	user-list| grep $2 | get_field 1`
}

# ******************************************************************************
# get_role_id() - return the role_id based upon the provided user
# 
# params: $1 token
#         $2 user name for which the role_id is associated.
# returns: tennat_id code.
#
function get_role_id() {
    echo `$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $1 \
	role-list| grep $2 | get_field 1`
}

# ******************************************************************************
# get_tenant_id() - return the tenant_id based upon the provided user
# 
# params: $1 token
#         $2 user name for which the tenant_id is associated.
# returns: tennat_id code.
#
function get_tenant_id() {
    echo `$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $1 \
	tenant-list| grep $2 | get_field 1`
}

# ******************************************************************************
# create_redstack_users() Setups up the users necessary for redstack testing.
# 
# params: $1 token
#
function create_redstack_users() {
    local mod="create_redstack_users"
    local tok=$1
    local RS=""

    func_begin "$mod" ""

    # Create the tenant "reddwarf".       
    # First we should check if these exist
    REDDWARF_TENANT=`get_tenant_id $tok "reddwarf"`
    ADMIN_ROLE=`get_role_id $tok "admin"`

    if [ -z $REDDWARF_TENANT ]; then
	$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok \
	    tenant-create --name=reddwarf
        REDDWARF_TENANT=`get_tenant_id $tok "reddwarf"`
    fi

    REDDWARF_ROLE=`get_role_id $tok "reddwarf"`
    if [ -z "$REDDWARF_ROLE" ]; then
        $KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok \
	    role-create --name=reddwarf
	REDDWARF_ROLE=`get_role_id $tok "reddwarf"`
    fi

    DAFFY_TENANT=`get_tenant_id $tok "daffy"`
    if [ -z $DAFFY_TENANT ]; then
	$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok \
	    tenant-create --name=daffy
	DAFFY_TENANT=`get_tenant_id $tok "daffy"`
    fi

    DAFFY_ROLE=`get_role_id $tok "daffy"`
    if [ -z "$DAFFY_ROLE" ]; then
        $KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok \
	    role-create --name=daffy
	DAFFY_ROLE=`get_role_id $tok "daffy"`
    fi

    $KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-create \
	--name="reddwarf" --pass="REDDWARF-PASS" --email="reddwarf@example.com"
    REDDWARF_USER=`get_user_id $tok "reddwarf"`


    #TODO(tim.simpson): Write some code here that removes the roles so these                                        
    #                   command won't fail if you run them twice.                                                   
    #                   That way we will still catch errors if our calls to                                         
    #                   keystone fail, but can run kickstart twice w/o install.                                     
    # set +e

    echo "$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-role-add \
          --tenant_id $REDDWARF_TENANT --user-id $REDDWARF_USER --role-id $REDDWARF_ROLE"
    $KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-role-add \
        --tenant_id $REDDWARF_TENANT --user-id $REDDWARF_USER --role-id $REDDWARF_ROLE

    # TODO: Restrict permissions.
    #$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok --user-create \
    #	--name="radmin" --pass="radmin" --email="radmin@example.com"

    # -- radmin user
    new_user="radmin"
    msgout "INFO" "$mod: adding $new_user user"
    RADMIN_USER=`get_user_id $tok $new_user`
    if [ -z "$RADMIN" ]; then
	$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-create \
	    --name="$new_user" --pass="$new_user" --email="$new_user@example.com"
    fi
    RADMIN_USER=`get_user_id $tok $new_user`
    $KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-role-add \
	--tenant_id $REDDWARF_TENANT --user-id $RADMIN_USER --role-id $REDDWARF_ROLE
    $KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-role-add \
	--tenant_id $REDDWARF_TENANT --user-id $RADMIN_USER --role-id $ADMIN_ROLE


    # -- Boss user
    new_user="Boss"
    msgout "INFO" "$mod: adding $new_user user"
    BOSS_USER=`$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-list| grep $new_user | get_field 1`
    if [ -z "$BOSS_USER" ]; then 
	$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-create \
	    --name="$new_user" --pass="admin" --email="$new_user@example.com"
    fi
    BOSS_USER=`$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-list| grep $new_user | get_field 1`
    $KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-role-add \
	--tenant_id $REDDWARF_TENANT --user-id $BOSS_USER --role-id $REDDWARF_ROLE
    $KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-role-add \
	--tenant_id $REDDWARF_TENANT --user-id $BOSS_USER --role-id $ADMIN_ROLE

    # -- chunk user
    new_user="chunk"
    msgout "INFO" "$mod: adding $new_user user"
    CHUNK_USER=`$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-list| grep $new_user | get_field 1`
    if [ -z "$CHUNK_USER" ]; then 
	$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-create \
	    --name="$new_user" --pass="$new_user" --email="$new_user@example.com"
    fi
    CHUNK_USER=`$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-list| grep $new_user | get_field 1`
    $KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-role-add \
	--tenant_id $REDDWARF_TENANT --user-id $CHUNK_USER --role-id $REDDWARF_ROLE


    # -- daffy user
    new_user="daffy"
    msgout "INFO" "$mod: adding $new_user user"
    DAFFY_USER=`$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-list| grep $new_user | get_field 1`
    if [ -z "$DAFFY_USER" ]; then 
	$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-create \
	    --name="$new_user" --pass="$new_user" --email="$new_user@example.com"
    fi
    DAFFY_USER=`$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-list| grep $new_user | get_field 1`
    $KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-role-add \
	--tenant_id $DAFFY_TENANT --user-id $DAFFY_USER --role-id $DAFFY_ROLE

    # -- examples user
    new_user="examples"
    msgout "INFO" "$mod: adding $new_user user"
    EXP_USER=`$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-list| grep $new_user | get_field 1`
    if [ -z "$EXP_USER" ]; then 
	$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-create \
	    --name="$new_user" --pass="$new_user" --email="$new_user@example.com"
    fi
    EXP_USER=`$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-list| grep $new_user | get_field 1`
    $KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-role-add \
	--tenant_id $REDDWARF_TENANT --user-id $EXP_USER --role-id $REDDWARF_ROLE


    # set -e

    # check if we have the test.conf file?
    if [ ! -f $USERHOME/test.conf ]; then
	mod_test_conf
    fi
    # Add the tenant id's into test.conf                                                                            
    DEMO_TENANT=`get_tenant_id 'demo'`
    sed -i "s/%reddwarf_tenant_id%/$REDDWARF_TENANT/g" $USERHOME/test.conf
    sed -i "s/%daffy_tenant_id%/$DAFFY_TENANT/g" $USERHOME/test.conf
    sed -i "s/%demo_tenant_id%/$DEMO_TENANT/g" $USERHOME/test.conf

#    echo "                                                                                                          
#REDDWARF_TENANT=$REDDWARF_TENANT                                                                                    
#REDDWARF_USER=$REDDWARF_USER                                                                                        
#REDDWARF_ROLE=$REDDWARF_ROLE                                                                                        
#" > $PATH_ENV_CONF

#    echo "                                                                                                          
## REDDWARF_TENANT=$REDDWARF_TENANT                                                                                  
## REDDWARF_USER=$REDDWARF_USER                                                                                      
## REDDWARF_ROLE=$REDDWARF_ROLE"

    msgout "DEBUG" "Checking login..."
    # Now attempt a login                                                                                           
    curl -d '{"auth":{"passwordCredentials":{"username": "reddwarf", "password": "REDDWARF-PASS"},"tenantName":"reddwarf"}}' \
     -H "Content-type: application/json" http://localhost:35357/v2.0/tokens

    func_end "$mod" ""
}

# ******************************************************************************
# delete_redstack_users() removes all the redstack users.
# 
# params: $1 token
#
function delete_redstack_users() {
    local mod="delete_redstack_users"
    local tok=$1
    local RS=""

    func_begin "$mod" ""
    user_list=$($KEYSTONE user-list | get_field 2)
    redstack_user_list="reddwarf Boss daffy radmin chunk examples"
    reddwarf_tenant_id=`get_tenant_id $tok "reddwarf"`
    daffy_tenant_id=`get_tenant_id $tok "daffy"`

    for u in $redstack_user_list; do
	msgout "DEBUG" "user=$u"
	u_presence=`$KEYSTONE user-list | grep $u | get_field 2`
	if [ -n "$u_presence" ]; then
	    uid=`get_user_id $tok $u`
	    role_id=`get_role_id $tok $u`
	    msgout "INFO" "$mod: deleting user=$u:$uid role=$role_id"
	    if [ -n "$uid" ]; then
		rs=`$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok user-delete $uid`
	    fi
	    if [ -n "$role_id" ]; then
		rs=`$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok role-delete $role_id`
	    fi
	fi
    done
    if [ -n "$reddwarf_tenant_id" ]; then
	msgout "INFO" "$mod: deleting tenant reddwarf:$reddwarf_tenant_id"
	$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok \
	    tenant-delete $reddwarf_tenant_id
    fi
    if [ -n "$daffy_tenant_id" ]; then
	msgout "INFO" "$mod: deleting tenant daffy:$daffy_tenant_id"
	$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $tok \
	    tenant-delete $daffy_tenant_id
    fi

    func_end "$mod" ""
}

# ******************************************************************************
# dump_keystone_user_info() dumps the tenant, user, and rols lists.
# 
# params: $1 token
#
function dump_keystone_user_info() {
    local mod="dump_keystone_user_info"
    local tok=$1
    local RS=""

    func_begin "$mod" ""
    msgout "INFO" "Dumping keystone info:"
    RS=`$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $TOKEN tenant-list`
    msgout "INFO" "****** TENANT INFO: ***************\n$RS"
    RS=`$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $TOKEN user-list`
    msgout "INFO" "****** USER INFO: ***************\n$RS"
    RS=`$KEYSTONE --endpoint http://localhost:35357/v2.0 --token $TOKEN role-list`
    msgout "INFO" "****** ROLE INFO: ***************\n$RS"

    func_end "$mod" ""
}

#############################################################
#                           MAIN                            #
#############################################################
retc=0
for arg in "$@"; do
    echo "arg=$arg"
    process_option $arg
done

#export OS_SERVICE_TOKEN=$SERVICE_TOKEN
# source $DEVSTACK_DIR/localrc
export OS_USERNAME="admin" 
export OS_TENANT_NAME="admin"
export OS_AUTH_URL="http://localhost:5000/v2.0/"
export OS_PASSWORD=`grep ADMIN_PASSWORD $DEVSTACK_DIR/localrc | awk '{split($0, a,"="); print a[2];}'`

# echo "parms: $@"


# -- validate args
# -- Setup the Debugging option, if present
if [ "$TRACE" = "yes" ]; then
    msgout "INFO" "xtrace ON"
    XTRACE=$(set +o | grep xtrace)
    set +o xtrace
    $XTRACE
    set -x
fi
if [ -z "$DEVSTACK_DIR" ]; then
    msgout "ERROR" "The DEVSTACK_DIR must be set"
    exit -1
else
   if [ -d "$DEVSTACK_DIR" ]; then
       if [ ! -f "$DEVSTACK_DIR/functions" ]; then
	   msgout "ERROR" "Can't locate $DEVSTACK_DIR/functions"
	   exit 1
       else
	   msgout "INFO" "loading $DEVSTACK_DIR/functions"
	   source "$DEVSTACK_DIR/functions"
       fi
   else
       msgout "ERROR" "Can't locate $DEVSTACK_DIR"
       exit 1
   fi
fi
if [ -z "$REDDWARF_INTEGRATION_CONF_DIR" ]; then
    msgout "ERROR" "The REDDWARF_INTEGRATION_CONF_DIR variable must be set"
    exit -2
else
    REDSTACK_SCRIPTS="$REDDWARF_INTEGRATION_CONF_DIR\scripts"
fi

msgout "INFO" "$PROG: Starting -- using operation-->$OP_CMD devstack-->$DEVSTACK_DIR, redstack-->$REDDWARF_INTEGRATION_CONF_DIR"

# Make sure the users required for redstack are created.
msgout "INFO" "Setup the redstack users, Delete them if they exists 1st"
TOKEN=$($KEYSTONE token-get | grep ' id ' | get_field 2)

if [ -z "$TOKEN" ]; then
    msgout "ERROR" "$PROG: We could not get a token for authentication"
    exit -1
fi

# We are doing this because at the time of this writing redstack user are being
# created in the devstack/lib/reddwarf code.
delete_redstack_users $TOKEN
dump_keystone_user_info $TOKEN

# Create the users necessary for redstack.
if [ "$OP_CMD" == "add" ]; then
    create_redstack_users $TOKEN
    dump_keystone_user_info $TOKEN
fi

msgout "INFO" "Finished"
exit 0


