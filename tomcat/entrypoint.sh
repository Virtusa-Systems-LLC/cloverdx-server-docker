#!/bin/bash

#default memory in MB
MINIMAL_MEMORY_SIZE=3072

available_memory() {
	local mem_file="/sys/fs/cgroup/memory/memory.limit_in_bytes"
	local mem_file_soft="/sys/fs/cgroup/memory/memory.soft_limit_in_bytes"
	if [[ -r "${mem_file}" && -r "${mem_file_soft}" ]]; then
		local max_mem_cgroup="$(cat ${mem_file})"
		local max_mem_cgroup_soft="$(cat ${mem_file_soft})"

		if [ ${max_mem_cgroup:-0} -lt ${max_mem_cgroup_soft:-0} ]; then
				echo $(bytes_to_megabytes "${max_mem_cgroup}")
		else
				echo ${MINIMAL_MEMORY_SIZE}
		fi
	else
		echo ${MINIMAL_MEMORY_SIZE}
	fi
}

bytes_to_megabytes() {
	local val=$(($1 / 1048576))
	echo "${val}"
}

#gets value from the given parameter and converts it to megabytes
#value can be a number (then it is considered as value in MB)
# or number with units (e.g. "1024m")
#supported units: 
#	megabytes (m)
#	gigabytes (g)
parse_to_get_megabytes() {
	local value=$1
	if [[ ${value} =~ ([0-9]+)[gG]{1} ]]; then
		value=$((${BASH_REMATCH[1]} * 1024))
	elif [[ ${value} =~ ([0-9]+)[mM]{1} ]]; then	
		value=${BASH_REMATCH[1]}
	fi
	echo ${value}
}

print_mem_info() {
	local info="Total available memory:\t ${CLOVER_AVAILABLE_MEM}MB\n
	OS memory:\t\t ${OS_MEM}MB\n
	Server memory:\t\t ${CLOVER_SERVER_HEAP_SIZE}MB\n
	Worker memory:\t\t ${CLOVER_WORKER_HEAP_SIZE}MB\n
	ReservedCodeCacheSize:\t ${RESERVED_CODE_CACHE_SIZE}MB"
	echo ${info}
}

compute() {
	local available_mem_mb=$(available_memory)
	export CLOVER_AVAILABLE_MEM=${available_mem_mb}
	local minimal_memory_size_mb=${MINIMAL_MEMORY_SIZE}

	if [[ $JAVA_OPTS =~ -Xmx([0-9]+[mMgG]?) ]]; then
		export CLOVER_SERVER_HEAP_SIZE=$(parse_to_get_megabytes "${BASH_REMATCH[1]}")
	fi
	
	if [ ${available_mem_mb} -lt ${minimal_memory_size_mb} ]; then
		>&2 echo "Insufficient memory set, expected at least ${MINIMAL_MEMORY_SIZE}MB, got ${available_mem_mb}MB."
    exit 1
	elif [ ${available_mem_mb} -eq ${MINIMAL_MEMORY_SIZE} ]; then
		local os_memory=896
		export MAX_CACHED_BUFFER_SIZE=65536
		export RESERVED_CODE_CACHE_SIZE=128
		if [ -z $CLOVER_SERVER_HEAP_SIZE ]; then
			export CLOVER_SERVER_HEAP_SIZE=1024
		fi
	elif [ ${available_mem_mb} -lt 4096 ]; then
		if [ $(($available_mem_mb/4)) -lt 896 ]; then
			local os_memory=896
		else
			local os_memory=$(($available_mem_mb/4))
		fi
		export MAX_CACHED_BUFFER_SIZE=65536
		export RESERVED_CODE_CACHE_SIZE=128
		if [ -z $CLOVER_SERVER_HEAP_SIZE ]; then
			export CLOVER_SERVER_HEAP_SIZE=1024
		fi
	elif [ ${available_mem_mb} -lt 8192 ]; then
		local os_memory=$(($available_mem_mb/4))
		export MAX_CACHED_BUFFER_SIZE=65536
		export RESERVED_CODE_CACHE_SIZE=128
		if [ -z $CLOVER_SERVER_HEAP_SIZE ]; then
			export CLOVER_SERVER_HEAP_SIZE=$(($available_mem_mb/4))
		fi
	elif [ ${available_mem_mb} -lt 16384 ]; then
		export RESERVED_CODE_CACHE_SIZE=256
		local os_memory=$((($available_mem_mb / 4) - $RESERVED_CODE_CACHE_SIZE))
		export MAX_CACHED_BUFFER_SIZE=65536
		if [ -z $CLOVER_SERVER_HEAP_SIZE ]; then
			export CLOVER_SERVER_HEAP_SIZE=$(($available_mem_mb/4))
		fi
	elif [ ${available_mem_mb} -lt 32768 ]; then
		export RESERVED_CODE_CACHE_SIZE=256
		local os_memory=$((($available_mem_mb / 4) - $RESERVED_CODE_CACHE_SIZE))
		export MAX_CACHED_BUFFER_SIZE=131072
		if [ -z $CLOVER_SERVER_HEAP_SIZE ]; then
			export CLOVER_SERVER_HEAP_SIZE=$(($available_mem_mb/4))
		fi
	elif [ ${available_mem_mb} -lt 65536 ]; then
	export RESERVED_CODE_CACHE_SIZE=256
		local os_memory=$((8192 - $RESERVED_CODE_CACHE_SIZE))
		export MAX_CACHED_BUFFER_SIZE=262144
		if [ -z $CLOVER_SERVER_HEAP_SIZE ]; then
			export CLOVER_SERVER_HEAP_SIZE=8192
		fi    
	else
		export RESERVED_CODE_CACHE_SIZE=512
		local os_memory=$((8192 - $RESERVED_CODE_CACHE_SIZE))
		export MAX_CACHED_BUFFER_SIZE=262144
		if [ -z $CLOVER_SERVER_HEAP_SIZE ]; then
			export CLOVER_SERVER_HEAP_SIZE=8192
		fi
	fi

	export OS_MEM=${os_memory}

	export CLOVER_SERVER_HEAP_SIZE=$(parse_to_get_megabytes "$CLOVER_SERVER_HEAP_SIZE")

	if [ -z $CLOVER_WORKER_HEAP_SIZE ]; then
		export CLOVER_WORKER_HEAP_SIZE=$(($available_mem_mb - (${os_memory} + ${CLOVER_SERVER_HEAP_SIZE} + ${RESERVED_CODE_CACHE_SIZE})))
	else
		export CLOVER_WORKER_HEAP_SIZE=$(parse_to_get_megabytes "$CLOVER_WORKER_HEAP_SIZE")	
	fi

	if [ ${CLOVER_SERVER_HEAP_SIZE} -lt 900 ]; then
		>&2 echo "Server's heap memory is too low. It must be at least 900MB."
		>&2 echo -e $(print_mem_info)
    exit 1
	fi

	if [ ${CLOVER_WORKER_HEAP_SIZE} -lt 1024 ]; then
		>&2 echo "Worker's heap memory is too low. It must be at least 1024MB."
		>&2 echo -e $(print_mem_info)
    exit 1
	fi

	if [ ${available_mem_mb} -lt $((${CLOVER_WORKER_HEAP_SIZE} + ${os_memory} + ${CLOVER_SERVER_HEAP_SIZE} + ${RESERVED_CODE_CACHE_SIZE})) ]; then
		>&2 echo "Insufficient memory set."
		>&2 echo -e $(print_mem_info)
    	exit 1
	fi
}

compute
#print info about memory settings
#echo -e $(print_mem_info)

#change permissions for the writable directories - CLO-16457
chmod -R o-x $CATALINA_HOME/work $CATALINA_HOME/webapps $CATALINA_HOME/logs $CATALINA_HOME/temp

USER=cloverdx
USER_ID=${LOCAL_USER_ID:-1000}

echo "Creating $USER user"
adduser \
	--disabled-password \
	--gecos "" \
	--home "/home/$USER" \
	--shell "/bin/bash" \
	--uid "$USER_ID" \
	"$USER"

echo "Changing ownership of $CATALINA_HOME"
chown -R $USER:$USER $CATALINA_HOME
chown -R $USER:$USER $CLOVER_HOME_DIR
chown -R $USER:$USER $CLOVER_DATA_DIR

#create empty folder for config files
if [ ! -d $CLOVER_HOME_CONF_DIR ]; then
	gosu $USER mkdir -p $CLOVER_HOME_CONF_DIR
fi	

#create empty configuration file if it does not exist
if [ ! -f $CUSTOM_CFG_FILE ]; then
	gosu $USER touch $CUSTOM_CFG_FILE
fi

#create empty JNDI config file
if [ ! -f $JNDI_CONF_FILE ]; then
	echo "Creating empty $JNDI_CONF_FILE"
	gosu $USER touch $JNDI_CONF_FILE
fi

#create empty HTTPS config file
if [ ! -f $HTTPS_CONF_FILE ]; then
	echo "Creating empty $HTTPS_CONF_FILE"
	gosu $USER touch $HTTPS_CONF_FILE
fi

if [ ! -d $CLOVER_HOME_DIR/tomcat-lib ]; then
	echo "Creating ${CLOVER_HOME_DIR}/tomcat-lib"
	gosu $USER mkdir $CLOVER_HOME_DIR/tomcat-lib
	echo "Copying JDBC drivers to ${CLOVER_HOME_DIR}/tomcat-lib"
	gosu $USER cp /var/dbdrivers/* ${CLOVER_HOME_DIR}/tomcat-lib/
fi

gosu $USER mkdir -p $CLOVER_HOME_DIR/worker-lib

#set SERVER_JAVA_OPTS to empty string if not set
if [ -z "$SERVER_JAVA_OPTS" ]; then
	export SERVER_JAVA_OPTS=""
fi

#set WORKER_JAVA_OPTS to empty string if not set
if [ -z "$WORKER_JAVA_OPTS" ]; then
	export WORKER_JAVA_OPTS=""
fi

#execute Tomcat
#save Tomcat standard output to catalina.out
echo "Starting Tomcat"
exec gosu $USER ./bin/catalina.sh run
