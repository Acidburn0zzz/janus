#!/bin/bash

#
# Create all the necessary scripts, keys, configurations etc. to run
# a cluster of N Quorum nodes with Raft consensus.
#
# The nodes will be in Docker containers. List the IP addresses that
# they will run at below (arbitrary addresses are fine).
#
# Run the cluster with "docker-compose up -d"
#
# Run a console on Node N with "geth attach qdata_N/dd/geth.ipc"
# (assumes Geth is installed on the host.)
#
# Geth and Constellation logfiles for Node N will be in qdata_N/logs/
#

# TODO: check file access permissions, especially for keys.


#### Configuration options #############################################

# These (currently) need to be in the subnet 172.13.0.0/16 since it is
# hardcoded into the docker-compose file. Change it below if you like.
ips=("172.13.0.2" "172.13.0.3" "172.13.0.4")

# Docker image name
image=quorum

########################################################################

if [[ ${#ips[@]} < 2 ]]
then
    echo "ERROR: There must be more than one node IP address."
    exit 1
fi
   
./cleanup.sh

uid=`id -u`
gid=`id -g`
pwd=`pwd`

#### Create directories for each node's configuration ##################

n=1
for ip in ${ips[*]}
do
    qd=qdata_$n
    mkdir -p $qd/{logs,keys}
    mkdir -p $qd/dd/geth
    touch $qd/passwords.txt

    let n++
done


#### Make static-nodes.json and store keys #############################

echo "[" > static-nodes.json
n=1
for ip in ${ips[*]}
do
    qd=qdata_$n

    # Generate the node's Enode and key
    enode=`docker run -v $pwd/$qd:/qdata $image sudo -u \#$uid -g \#$gid /usr/local/bin/bootnode -genkey /qdata/dd/nodekey -writeaddress`

    # Add the enode to static-nodes.json
    sep=`[[ $ip != ${ips[-1]} ]] && echo ","`
    echo '  "enode://'$enode'@'$ip':30303?discport=0"'$sep >> static-nodes.json

    let n++
done
echo "]" >> static-nodes.json


#### Create accounts, keys and genesis.json file #######################

cat > genesis.json <<EOF
{
  "alloc": {
EOF

n=1
for ip in ${ips[*]}
do
    qd=qdata_$n

    # Generate an Ether account for the node
    account=`docker run -v $pwd/$qd:/qdata $image sudo -u \#$uid -g \#$gid /usr/local/bin/geth --datadir=/qdata/dd --password /qdata/passwords.txt account new | cut -c 11-50`

    # Add the account to the genesis block so it has some Ether at start-up
    sep=`[[ $ip != ${ips[-1]} ]] && echo ","`
    cat >> genesis.json <<EOF
    "${account}": {
      "balance": "1000000000000000000000000000"
    }${sep}
EOF

    let n++
done

cat >> genesis.json <<EOF
  },
  "coinbase": "0x0000000000000000000000000000000000000000",
  "config": {
    "homesteadBlock": 0
  },
  "difficulty": "0x0",
  "extraData": "0x",
  "gasLimit": "0x2FEFD800",
  "mixhash": "0x00000000000000000000000000000000000000647572616c65787365646c6578",
  "nonce": "0x0",
  "parentHash": "0x0000000000000000000000000000000000000000000000000000000000000000",
  "timestamp": "0x00"
}
EOF


#### Make node list for tm.conf ########################################

nodelist=
n=1
for ip in ${ips[*]}
do
    sep=`[[ $ip != ${ips[0]} ]] && echo ","`
    nodelist=${nodelist}${sep}'"http://'${ip}':9000/"'
    let n++
done


#### Complete each node's configuration ################################

n=1
for ip in ${ips[*]}
do
    qd=qdata_$n

    cat templates/tm.conf \
        | sed s/_NODEIP_/${ips[$((n-1))]}/g \
        | sed s%_NODELIST_%$nodelist%g \
              > $qd/tm.conf

    cp genesis.json $qd/genesis.json
    cp static-nodes.json $qd/dd/static-nodes.json

    # Generate Quorum-related keys (used by Constellation)
    docker run -v $pwd/$qd:/qdata $image sudo -u \#$uid -g \#$gid /usr/local/bin/constellation-enclave-keygen /qdata/keys/tm /qdata/keys/tma < /dev/null > /dev/null
    echo 'Node '$n' public key: '`cat $qd/keys/tm.pub`

    # Embed the user's host machine permissions in the start script
    # So that the nodes run under the right UID/GID
    cat templates/start-node.sh \
        | sed s/_UID_/$uid/g \
        | sed s/_GID_/$gid/g \
        > $qd/start-node.sh
    chmod 755 $qd/start-node.sh

    let n++
done
rm -rf genesis.json static-nodes.json


#### Create the docker-compose file ####################################

cat > docker-compose.yml <<EOF
version: '2'
services:
EOF

n=1
for ip in ${ips[*]}
do
    qd=qdata_$n

    cat >> docker-compose.yml <<EOF
  node_$n:
    image: $image
    volumes:
      - './$qd:/qdata'
    networks:
      quorum_net:
        ipv4_address: '$ip'
    ports:
      - $((n+22000)):8545
EOF

    let n++
done

cat >> docker-compose.yml <<EOF

networks:
  quorum_net:
    driver: bridge
    ipam:
      driver: default
      config:
      - subnet: 172.13.0.0/16
EOF


#### Create pre-populated contracts ####################################

# Private contract - insert Node 2 as the recipient
cat templates/contract_pri.js \
    | sed s:_NODEKEY_:`cat qdata_2/keys/tm.pub`:g \
          > contract_pri.js

# Public contract - no change required
cp templates/contract_pub.js ./
