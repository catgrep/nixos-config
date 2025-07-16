#!/bin/sh

set -ex

make check
for host in beelink firebat; do
   make dry-apply-"$host"
   make apply-"$host"
done
