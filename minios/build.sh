#!/bin/sh

set -ex

docker build --output=type=local,dest=$PWD -f Dockerfile .

cp -f initrd.img ../assets/initrd.img

