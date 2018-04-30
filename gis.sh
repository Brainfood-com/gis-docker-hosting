#!/bin/bash

export MSYS_NO_PATHCONV=1

TOP_DIR="$(cd "$(dirname "$0")"; echo "$PWD")"
t_flag=
tty -s && t_flag=-t

exec docker exec \
	-e MAP_TERM="$([[ $TERM ]] && tput cols):$([[ $TERM ]] && tput lines):$TERM" \
	-e MAP_TOP_DIR="$TOP_DIR" \
	-e MAP_PWD="$PWD" \
	-e MAP_USER="$(id)" \
	-e MAP_UMASK="$(umask)" \
	-i $t_flag localdev_control_1 \
	/srv/localdev/scripts/run \
	"$@"

exit 1
