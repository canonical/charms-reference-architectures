#!/usr/bin/env bash


K8S_USER="ubuntu"

snap alias microk8s.kubectl kubectl || true

usermod -a -G snap_microk8s "${K8S_USER}"

microk8s status --wait-ready

retry --times 3 --delay 5 -- microk8s enable dns
retry --times 3 --delay 5 -- microk8s enable hostpath-storage
retry --times 3 --delay 5 -- microk8s enable metallb

microk8s status --wait-ready

(retry --times 3 --delay 5 -- microk8s stop) || true
