#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later

DEPLOY_YAML=${DEPLOY_YAML:-deploy.yaml}

# Helper functions to parse host metadata
get_ip() {
    yq -e eval ".hosts.$1.targetHost" "$DEPLOY_YAML"
}

get_user() {
    yq -e eval ".hosts.$1.targetUser" "$DEPLOY_YAML"
}

# NOTE: always true, so not using this
get_buildontarget() {
    yq -e eval ".hosts.${1}.buildOnTarget" "$DEPLOY_YAML"
}

# NOTE: don't have a need for this yet
get_tags() {
    yq -e eval ".hosts.$1.tags[]" "$DEPLOY_YAML"
}

list_hosts() {
    yq -e eval ".hosts | keys | .[]" "$DEPLOY_YAML"
}

print_yaml() {
    yq -e eval -P "$1"
}
