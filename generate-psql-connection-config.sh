#!/bin/bash
set -e
## This script just renders psql config in json format according to the docker ps output

function getServerConnectionString() {
  cat << EOF
  "${1//-}": {
  "psql_host":"127.0.0.1",
  "psql_user":"postgres",
  "psql_database":"postgres",
  "psql_password":"$(cat postgrespass.secret)",
  "psql_port":"$(docker inspect $1 -f '{{index .NetworkSettings.Ports "5432/tcp" 0 "HostPort"}}')"
  }
  ,
EOF
}

containers=$(docker ps --format "{{.Names}}" | grep "trfrmtestdatabase"| sort -n)

echo '{"psql_connections":{'

for db_container in $containers; do
  getServerConnectionString $db_container
done | head -n -1 # remove the last comma

echo '}}'
