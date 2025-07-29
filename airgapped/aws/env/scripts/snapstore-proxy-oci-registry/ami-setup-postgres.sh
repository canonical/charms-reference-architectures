#!/usr/bin/env bash

# Copyright 2025 Canonical Ltd.
# See LICENSE file for licensing details.


systemctl enable postgresql
systemctl start postgresql

sudo -u postgres psql -c "CREATE ROLE \"snapproxy-user\" LOGIN CREATEROLE PASSWORD 'snapproxy-password';"
sudo -u postgres psql -c "CREATE DATABASE \"snapproxy-db\" OWNER \"snapproxy-user\";"
sudo -u postgres psql -d "snapproxy-db" -c "CREATE EXTENSION \"btree_gist\";"
