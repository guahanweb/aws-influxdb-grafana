#!/usr/bin/env bash

# Define ANSI color escape code
# color <ansi_color_code>

color() { printf "\033[${1}m"; }

# No Color
NO_COLOR=$(color "0")
NC=${NO_COLOR}
RESET_ALL='\033[0m'

# Stiles
BOLD='\e[1m'
ITALIC='\e[3m'
UNDERLINE='\e[4m'

# Black        0;30
# Dark Gray    1;30
BLACK=$(color "0;30")
DARK_GRAY=$(color "1;30")
LIGHT_BLACK=${DARK_GRAY}

# Red          0;31
# Light Red    1;31
RED=$(color "0;31")
BOLD_RED=$(color "1;31")

# Green        0;32
# Light Green  1;32
GREEN=$(color "0;32")
BOLD_GREEN=$(color "1;32")
# Brown/Orange 0;33
# Yellow       1;33
BROWN=$(color "0;33")
ORANGE=${BROWN}
YELLOW=$(color "0;33")
BOLD_BROWN=${YELLOW}
LIGHT_ORANGE=${YELLOW}

# Blue         0;34
# Light Blue   1;34
BLUE=$(color "0;34")
BOLD_BLUE=$(color "1;34")

# Purple       0;35
# Light Purple 1;35
PURPLE=$(color "0;35")
BOLD_PURPLE=$(color "1;35")

# Cyan         0;36
# Light Cyan   1;36
CYAN=$(color "0;36")
BOLD_CYAN=$(color "1;36")

# Light Gray   0;37
# White        1;37
GRAY=$(color "0;37")
BOLD_WHITE=$(color "1;37")
STANDARD=${LIGTH_GRAY}
LIGHT_STANDARD=${WHITE}

function fail() {
    local message=${1}
    local status=${2:-1}
    echo "${RED}[error]${NC} ${message}"
    exit ${status}
}

function ok() {
    local message=${1}
    echo "${GREEN}[ok]${NC} ${message}"
}

function info() {
    local message=${1}
    echo "${BLUE}[info]${NC} ${message}"
}

function in_use() {
    local port=${1}
    lsof -i:${port} > /dev/null 2>&1
    return $?
}

# generalied installation script to verify installation of commands
# usage: assure_installed <command> <install_command> [prefix]
function assure_installed() {
    local cmd=${1}
    local install_command=${2}
    local prefix=${3:-install}
    local skip_install=${4:-false}

    if ! command -v ${cmd} &> /dev/null 
    then
        if $skip_install = true 
        then
            echo "${1} not installed... skipping"
        else
            echo "${CYAN}${prefix}:${NC} installing ${BOLD_WHITE}jq${NC}..."
            if command -v brew &> /dev/null
            then
                eval ${install_command}
                echo "${CYAN}${prefix}:${NC} ${BOLD_WHITE}${cmd}${NC} installed."
            else
                echo "${CYAN}${prefix}:${NC} ${BOLD_WHITE}Brew${NC} not installed"
            fi
        fi
    else
        echo "${CYAN}${prefix}:${NC} ${BOLD_WHITE}${cmd}${NC} already installed, skipping..."
    fi
}

function get_index() {
    local arr=("$@")
    ((last_idx=${#arr[@]} - 1))
    local query=${arr[last_idx]}
    unset arr[last_idx]

    for i in "${!arr[@]}"; do
        if [[ "${arr[$i]}" = "${query}" ]]; then
            echo "${i}"
        fi
    done
}

function appendPathPart() {
    local apiId=${1}
    local parentId=${2}
    local pathPart=${3}

    aws ${ENDPOINT} apigateway create-resource \
        --region ${AWS_REGION} \
        --rest-api-id ${apiId} \
        --parent-id ${parentId} \
        --path-part ${pathPart} \
        > /dev/null 2>&1

    [ $? == 0 ] || fail "failed to create resource: ${BOLD_WHITE}${pathPart}${NC}"
    aws ${ENDPOINT} apigateway get-resources --rest-api-id ${apiId} --query 'items[?pathPart==`'${pathPart}'`].id' --output text --region ${AWS_REGION} | xargs
}