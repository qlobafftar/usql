#!/bin/bash

# podman-run.sh: starts or restarts podman containers.
#
# Usage: podman-run.sh <TARGET> [-u]
#
# Where <target> is a name of a subdirectory containing podman-config,
# 'all', or 'test'.
#
# all  -- starts all available database images.
# test -- starts the primary testing images. The testing images are cassandra,
#         mysql, postgres, sqlserver, and oracle [if available].
# -u   -- perform podman pull for images prior to start.
#
# Will stop any running podman container prior to starting.

DIR=$1

SRC=$(realpath $(cd -P "$(dirname "${BASH_SOURCE[0]}" )" && pwd))

if [ -z "$DIR" ]; then
  echo "usage: $0 <TARGET> [-u]"
  exit 1
fi

shift

UPDATE=0

OPTIND=1
while getopts "u" opt; do
case "$opt" in
  u) UPDATE=1 ;;
esac
done

podman_run() {
  TARGET=$1
  BASE=$SRC/$TARGET
  if [ ! -e $BASE/podman-config ]; then
    echo "error: $BASE/podman-config doesn't exist"
    exit 1
  fi
  # load parameters from docer-config
  unset IMAGE NAME PUBLISH ENV VOLUME NETWORK PRIVILEGED PARAMS
  source $BASE/podman-config
  if [[ "$TARGET" != "$NAME" ]]; then
    echo "error: $BASE/podman-config is invalid"
    exit 1
  fi
  # setup params
  PARAMS=()
  for k in NAME PUBLISH ENV VOLUME NETWORK PRIVILEGED; do
    n=$(tr 'A-Z' 'a-z' <<< "$k")
    v=$(eval echo "\$$k")
    if [ ! -z "$v" ]; then
      for p in $v; do
        PARAMS+=("--$n=$p")
      done
    fi
  done
  # determine if image exists
  EXISTS=$(podman image ls -q $IMAGE)
  if [[ "$UPDATE" == "0" && -z "$EXISTS" ]]; then
    UPDATE=1
  fi
  # show parameters
  echo "-------------------------------------------"
  echo "NAME:       $NAME"
  echo "IMAGE:      $IMAGE (update: $UPDATE)"
  echo "PUBLISH:    $PUBLISH"
  echo "ENV:        $ENV"
  echo "VOLUME:     $VOLUME"
  echo "NETWORK:    $NETWORK"
  echo "PRIVILEGED: $PRIVILEGED"
  # update
  if [[ "$UPDATE" == "1" && "$TARGET" != "oracle" ]]; then
    if [ ! -f $BASE/Dockerfile ]; then
      (set -ex;
        podman pull $IMAGE
      )
    else
      pushd $BASE &> /dev/null
      (set -ex;
        podman build --pull -t $IMAGE:latest .
      )
      popd &> /dev/null
    fi
    REF=$(awk -F: '{print $1}' <<< "$IMAGE")
    REMOVE=$(podman image list --filter=dangling=true --filter=reference=$IMAGE -q)
    if [ ! -z "$REMOVE" ]; then
      (set -ex;
        podman image rm -f $REMOVE
      )
    fi
  fi
  # stop any running images
  if [ ! -z "$(podman ps -q --filter "name=$NAME")" ]; then
    (set -x;
      podman stop $NAME
    )
  fi

  if [ ! -z "$(podman ps -q -a --filter "name=$NAME")" ]; then
    (set -x;
      podman rm -f $NAME
    )
  fi
  (set -ex;
    podman run --detach --rm ${PARAMS[@]} $IMAGE
  )
}

pushd $SRC &> /dev/null
TARGETS=()
case $DIR in
  all)
    TARGETS+=($(find . -type f -name podman-config|awk -F'/' '{print $2}'|grep -v oracle|grep -v db2))
    if [[ "$(podman image ls -q --filter 'reference=localhost/oracle/database')" != "" ]]; then
      TARGETS+=(oracle)
    fi
    if [[ "$(podman image ls -q --filter 'reference=docker.io/ibmcom/db2')" != "" ]]; then
      TARGETS+=(db2)
    fi
  ;;
  test)
    TARGETS+=(mysql postgres sqlserver cassandra)
    if [[ "$(podman image ls -q --filter 'reference=localhost/oracle/database')" != "" ]]; then
      TARGETS+=(oracle)
    fi
  ;;
  *)
    TARGETS+=($DIR)
  ;;
esac

for TARGET in ${TARGETS[@]}; do
  podman_run $TARGET
done
popd &> /dev/null
