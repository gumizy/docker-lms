#!/bin/bash

set -e

echo "[Entrypoint] MySQL Docker Image 5.7.22-1.1.5"
# Fetch value from server config
# We use mysqld --verbose --help instead of my_print_defaults because the
# latter only show values present in config files, and not server defaults
_get_config() {
	local conf="$1"; shift
        mysqld --verbose --help 2>/dev/null | grep "^$conf" | awk '$1 == "'"$conf"'" { print $2; exit }'
	#"$@" --verbose --help 2>/dev/null | grep "^$conf" | awk '$1 == "'"$conf"'" { print $2; exit }'
}

# If command starts with an option, prepend mysqld
# This allows users to add command-line options without
# needing to specify the "mysqld" command
if [ "${1:0:1}" = '-' ]; then
	set -- mysqld "$@"
fi

#if [ "$1" = 'mysqld' ]; then
	# Test that the server can start. We redirect stdout to /dev/null so
	# only the error messages are left.
	result=0
	output=$(mysqld --verbose --help 2>&1 > /dev/null) || result=$?
	if [ ! "$result" = "0" ]; then
		echo >&2 '[Entrypoint] ERROR: Unable to start MySQL. Please check your configuration.'
		echo >&2 "[Entrypoint] $output"
		exit 1
	fi

	# Get config
	DATADIR="$(_get_config 'datadir' 'mysqld')"
	SOCKET="$(_get_config 'socket' 'mysqld')"

	if [ -n "$MYSQL_LOG_CONSOLE" ] || [ -n "" ]; then
		# Don't touch bind-mounted config files
		if ! cat /proc/1/mounts | grep "etc/my.cnf"; then
			sed -i 's/^log-error=/#&/' /etc/my.cnf
		fi
	fi

	if [ ! -d "$DATADIR/mysql" ]; then
		# If the password variable is a filename we use the contents of the file. We
		# read this first to make sure that a proper error is generated for empty files.
		if [ -f "$MYSQL_ROOT_PASSWORD" ]; then
			MYSQL_ROOT_PASSWORD="$(cat $MYSQL_ROOT_PASSWORD)"
			if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
				echo >&2 '[Entrypoint] Empty MYSQL_ROOT_PASSWORD file specified.'
				exit 1
			fi
		fi
		if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_ALLOW_EMPTY_PASSWORD" -a -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
			echo >&2 '[Entrypoint] No password option specified for new database.'
			echo >&2 '[Entrypoint]   A random onetime password will be generated.'
			MYSQL_RANDOM_ROOT_PASSWORD=true
		fi
		mkdir -p "$DATADIR"
		chown -R mysql:mysql "$DATADIR"

		echo '[Entrypoint] Initializing database'
		mysqld --initialize-insecure
		echo '[Entrypoint] Database initialized'

		mysqld --daemonize --skip-networking --socket="$SOCKET"

		# To avoid using password on commandline, put it in a temporary file.
		# The file is only populated when and if the root password is set.
		PASSFILE=$(mktemp -u /var/lib/mysql-files/XXXXXXXXXX)
		install /dev/null -m0600 -omysql -gmysql "$PASSFILE"
		# Define the client command used throughout the script
		# "SET @@SESSION.SQL_LOG_BIN=0;" is required for products like group replication to work properly
		mysql=( mysql --defaults-extra-file="$PASSFILE" --protocol=socket -uroot -hlocalhost --socket="$SOCKET" --init-command="SET @@SESSION.SQL_LOG_BIN=0;")

		if [ ! -z "" ];
		then
			for i in {30..0}; do
				if mysqladmin --socket="$SOCKET" ping &>/dev/null; then
					break
				fi
				echo '[Entrypoint] Waiting for server...'
				sleep 1
			done
			if [ "$i" = 0 ]; then
				echo >&2 '[Entrypoint] Timeout during MySQL init.'
				exit 1
			fi
		fi

		mysql_tzinfo_to_sql /usr/share/zoneinfo | "${mysql[@]}" mysql

		if [ ! -z "$MYSQL_RANDOM_ROOT_PASSWORD" ]; then
			MYSQL_ROOT_PASSWORD="$(pwmake 128)"
			echo "[Entrypoint] GENERATED ROOT PASSWORD: $MYSQL_ROOT_PASSWORD"
		fi
		if [ -z "$MYSQL_ROOT_HOST" ]; then
			ROOTCREATE="ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';"
		else
			ROOTCREATE="ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}'; \
			CREATE USER 'root'@'${MYSQL_ROOT_HOST}' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}'; \
			GRANT ALL ON *.* TO 'root'@'${MYSQL_ROOT_HOST}' WITH GRANT OPTION ; \
			GRANT ALL ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION ; \
			GRANT PROXY ON ''@'' TO 'root'@'${MYSQL_ROOT_HOST}' WITH GRANT OPTION ;"
		fi

		if [ ! -z "$MYSQL_ROOT_PASSWORD" ]; then
			# Put the password into the temporary config file
			cat >"$PASSFILE" <<EOF
[client]
password="${MYSQL_ROOT_PASSWORD}"
EOF
			#mysql+=( -p"${MYSQL_ROOT_PASSWORD}" )
		fi

		if [ "$MYSQL_DATABASE" ]; then
			echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;" | "${mysql[@]}"
			mysql+=( "$MYSQL_DATABASE" )
		fi

		if [ "$MYSQL_USER" -a "$MYSQL_PASSWORD" ]; then
			echo "CREATE USER '"$MYSQL_USER"'@'%' IDENTIFIED BY '"$MYSQL_PASSWORD"' ;" | "${mysql[@]}"

			if [ "$MYSQL_DATABASE" ]; then
				echo "GRANT ALL ON \`"$MYSQL_DATABASE"\`.* TO '"$MYSQL_USER"'@'%' ;" | "${mysql[@]}"
			fi

			echo 'FLUSH PRIVILEGES ;' | "${mysql[@]}"
		elif [ "$MYSQL_USER" -a ! "$MYSQL_PASSWORD" -o ! "$MYSQL_USER" -a "$MYSQL_PASSWORD" ]; then
			echo '[Entrypoint] Not creating mysql user. MYSQL_USER and MYSQL_PASSWORD must be specified to create a mysql user.'
		fi
		echo
		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh)  echo "[Entrypoint] running $f"; . "$f" ;;
				*.sql) echo "[Entrypoint] running $f"; "${mysql[@]}" < "$f" && echo ;;
				*)     echo "[Entrypoint] ignoring $f" ;;
			esac
			echo
		done

		# When using a local socket, mysqladmin shutdown will only complete when the server is actually down
		mysqladmin --defaults-extra-file="$PASSFILE" shutdown -uroot --socket="$SOCKET"
		rm -f "$PASSFILE"
		unset PASSFILE
		echo "[Entrypoint] Server shut down"


		echo
		echo '[Entrypoint] MySQL init process done. Ready for start up.'
		echo
	fi

	touch /mysql-init-complete
	chown -R mysql:mysql "$DATADIR"
	echo "[Entrypoint] Starting MySQL 5.7.22-1.1.5"
#fi

mysqld --daemonize

for i in {30..0}; do
    if mysqladmin --socket="$SOCKET" ping &>/dev/null; then
        echo "ok"
	break
    fi
    echo '[Entrypoint] Waiting for server...'
    sleep 1
done
if [ "$i" = 0 ]; then
    echo >&2 '[Entrypoint] Timeout during MySQL init.'
    exit 1
fi
sleep 1
java -jar /usr/local/base-0.0.1-SNAPSHOT.jar

#exec "$@"
