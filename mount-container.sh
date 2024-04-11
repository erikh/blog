#!/usr/bin/env bash

set -eou pipefail
set -x

unpack() {
  mkdir -p tmp
  export MOUNT_BASE=$(mktemp -d tmp/container.XXXXXX)
  export UNPACK_BASE=$(mktemp -d tmp/container_unpack.XXXXXX) 

  image="$1"

  docker pull $image
  docker save $image | tar -xa -C $UNPACK_BASE
}

list_layers() {
  jq -r '.[0].Layers[]' $UNPACK_BASE/manifest.json
}

unpack_layer() {
  mountpoint=$MOUNT_BASE/$(dirname $1) 
  mkdir -p $mountpoint
  tar -C $mountpoint -xaf "$UNPACK_BASE/$1"
  echo "$mountpoint"
}

translate_layer() {
  for dir in $(find $MOUNT_BASE/$(dirname $1) -name '.wh..wh..opq')
  do
    rm -r $dir
    setfattr -n trusted.overlay.opaque -v y $(dirname $dir)
  done

  for file in $(find $MOUNT_BASE/$(dirname $1) -name '.wh.*')
  do
    dir=$(dirname $file)
    mv $file $dir/$(echo $(basename $file) | sed -e 's/^.wh.//')
  done
}

mount_layers() { 
  writedir=$(mktemp -d $MOUNT_BASE/write.XXXXXX)
  workdir=$(mktemp -d $MOUNT_BASE/work.XXXXXX)
  mergeddir=$(mktemp -d $MOUNT_BASE/merged.XXXXXX)

  first="x"
  lowers=""

  for dir in $*
  do 
    if [ "$first" = "x" ]
    then
      lowers="$dir"
      first=""
    else
      lowers="${lowers}:${dir}"
    fi
  done

  mount -t overlay overlay "-orw,relatime,lowerdir=$lowers,upperdir=$writedir,workdir=$workdir" "$mergeddir"
  echo "$mergeddir"
}

walk_dir() {
  path="$1"
  shift

  for entry in $(find "$path" -maxdepth 1 | tail -n +2)
  do
    eval "$* $entry"
  done
}

teardown() {
  walk_dir $MOUNT_BASE umount
  rm -rf $MOUNT_BASE $UNPACK_BASE
}

trap teardown INT TERM

IMAGE="$1"
shift
COMMAND="$*"

unpack $IMAGE

layers=""

for layer in $(list_layers)
do
  layers="$layers $(unpack_layer $layer)"
  translate_layer $layer
done

echo $(mount_layers $layers)
