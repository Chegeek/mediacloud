#!/bin/bash

# Die on error
set -e

PWD="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

QUERY_CONFIG="$PWD/../script/run_with_carton.sh $PWD/../script/mediawords_query_config.pl"

# 'cd' to Media Cloud's root (assuming that this script is stored in './script/')
cd "$PWD/../"

# RabbitMQ recommends at least 65536 max. open files
# (https://www.rabbitmq.com/install-debian.html#kernel-resource-limits)
MIN_OPEN_FILES_LIMIT=65536


log() {
    # to STDERR
    echo "$@" 1>&2
}

rabbitmq_is_enabled() {
    local rabbitmq_is_enabled=`$QUERY_CONFIG "//job_manager/rabbitmq/server/enabled"`
    if [ "$rabbitmq_is_enabled" == "yes" ]; then
        return 0    # "true" in Bash
    else
        return 1    # "false" in Bash
    fi
}

rabbitmq_is_installed() {
    local path_to_rabbitmq_server=$(which rabbitmq-server)
    if [ -x "$path_to_rabbitmq_server" ]; then
        return 0    # "true" in Bash
    else
        return 1    # "false" in Bash
    fi
}

gearmand_version() {
    local gearmand_version=`gearmand --version | perl -e '
        while (<>) {
            chomp;
            $version_string .= $_;
        }
        @parts = split(/ /, $version_string);
        print $parts[1]'`
        
    if [ -z "$gearmand_version" ]; then
        log "Unable to determine gearmand version"
        exit 1
    fi
    echo "$gearmand_version"
}

rabbitmq_is_up_to_date() {
    local rabbitmq_version=$(dpkg -s rabbitmq-server | grep Version | awk '{ print $2 }')
    echo "$rabbitmq_version" | perl -e '
        use version 0.77;
        $current_version = version->parse(<>);
        $required_version = version->parse("3.6.0");
        unless ($current_version >= $required_version) {
            die "Current RabbitMQ version $current_version is older than required version $required_version\n";
        } else {
            print "Current RabbitMQ version $current_version is up-to-date.\n";
        }' || {

        return 1    # "false" in Bash
    }
    return 0    # "true" in Bash
}

max_fd_limit_is_big_enough() {
    if [ `ulimit -S -n` -ge "$MIN_OPEN_FILES_LIMIT" ]; then
        return 0    # "true" in Bash
    else
        return 1    # "false" in Bash
    fi
}

print_rabbitmq_installation_instructions() {
    log "Please install RabbitMQ by running:"
    log ""
    log "    # Erlang (outdated on Ubuntu 12.04)"
    log "    sudo apt-get -y remove esl-erlang* erlang*"
    log "    curl http://packages.erlang-solutions.com/ubuntu/erlang_solutions.asc | sudo apt-key add -"
    log "    echo \"deb http://packages.erlang-solutions.com/ubuntu precise contrib\" | sudo tee -a /etc/apt/sources.list.d/erlang-solutions.list"
    log ""
    log "    # RabbitMQ (outdated on all Ubuntu versions)"
    log "    sudo apt-get -y remove rabbitmq-server"
    log "    curl -s https://packagecloud.io/install/repositories/rabbitmq/rabbitmq-server/script.deb.sh | sudo bash"
    log ""    
    log "    sudo apt-get -y update"
    log "    sudo apt-get -y install rabbitmq-server"
    log ""
}

#
# ---
#

echo "Testing environment..."
if ! rabbitmq_is_enabled; then
    log "RabbitMQ is not enabled."
    log "Please enable it in 'mediawords.yml' by setting /job_manager/rabbitmq/server/enabled to 'yes'."
    exit 0
fi

if ! rabbitmq_is_installed; then
    log "'rabbitmq-server' was not found in your PATH."
    print_rabbitmq_installation_instructions
    exit 1
fi

if [ `uname` == 'Darwin' ]; then
    # Mac OS X -- trust that Homebrew has the latest version, don't mind the open files limit
    :
else
    # Ubuntu

    if ! rabbitmq_is_up_to_date; then
        log "'rabbitmq-server' was found in your PATH, but is too old."
        print_rabbitmq_installation_instructions
        exit 1
    fi

    if ! max_fd_limit_is_big_enough; then
        log "Open file limit is less than $MIN_OPEN_FILES_LIMIT."
        log "Please rerun ./install_scripts/set_kernel_parameters.sh"
        exit 1
    fi
fi

echo "Reading configuration..."

# (scope of the following exports is local)

export RABBITMQ_NODE_IP_ADDRESS=`$QUERY_CONFIG "//job_manager/rabbitmq/server/listen"`
export RABBITMQ_NODE_PORT=`$QUERY_CONFIG "//job_manager/rabbitmq/server/port"`
export RABBITMQ_NODENAME=`$QUERY_CONFIG "//job_manager/rabbitmq/server/node_name"`

export RABBITMQ_BASE="$PWD/data/rabbitmq"
if [ ! -d "$RABBITMQ_BASE" ]; then
    log "RabbitMQ base directory '$RABBITMQ_BASE' does not exist."
    exit 1
fi

export RABBITMQ_CONFIG_FILE="$RABBITMQ_BASE/rabbitmq"   # sans ".config" extension
if [ ! -f "${RABBITMQ_CONFIG_FILE}.config" ]; then
    log "RabbitMQ configuration file '$RABBITMQ_CONFIG_FILE' does not exist."
    exit 1
fi

export RABBITMQ_MNESIA_BASE="${RABBITMQ_BASE}/mnesia"
if [ ! -d "$RABBITMQ_MNESIA_BASE" ]; then
    log "RabbitMQ Mnesia directory '$RABBITMQ_MNESIA_BASE' does not exist."
    exit 1    
fi

export RABBITMQ_LOG_BASE="${RABBITMQ_BASE}/logs"
if [ ! -d "$RABBITMQ_LOG_BASE" ]; then
    log "RabbitMQ log directory '$RABBITMQ_LOG_BASE' does not exist."
    exit 1    
fi

echo "Starting rabbitmq-server..."
exec rabbitmq-server
