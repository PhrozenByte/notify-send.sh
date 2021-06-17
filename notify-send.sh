#!/bin/sh
# @file - notify-send.sh
# @brief - drop-in replacement for notify-send with more features
###############################################################################
# Copyright (C) 2015-2020 notify-send.sh authors (see AUTHORS file)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# NOTE: Desktop Notifications Specification
# https://developer.gnome.org/notification-spec/

################################################################################
## Globals (Comprehensive)

# Symlink script resolution via coreutils (exists on 95+% of linux systems.)
SELF=$(readlink -n -f $0);
PROCDIR="$(dirname "$SELF")"; # Process direcotry.
APP_NAME="$(basename "$SELF")";
TMP="${XDG_RUNTIME_DIR:-/tmp}";
VERSION="2.0.0-rc.m3tior"; # Changed to semantic versioning.
EXPIRE_TIME=-1;
ID=0;
URGENCY=1;
PRINT_ID=false;
EXPLICIT_CLOSE=false;
#positional=false;
SUMMARY=; BODY=;
AKEYS=; ACMDS=; ACTION_COUNT=0;
HINTS=;

################################################################################
## Functions

abrt () { echo "Error in '$SELF': $*" >&2; exit 1; }

# @describe - Prints the simplest primitive type of a value.
# @usage - typeof [-g] VALUE
# @param "-g" - Toggles the numerical return values which increase in order of inclusivity.
# @param VALUE - The value you wish to check.
# @prints (5|'string') - When no other primitive can be coerced from the input.
# @prints (4|'filename') - When a string primitive is safe to use as a filename.
# @prints (3|'alphanum') - When a string primitive only contains letters and numbers.
# @prints (2|'double') - When the input can be coerced into a floating number.
# @prints (1|'int') - When the input can be coerced into a regular integer.
# @prints (0|'uint') - When the input can be coereced into an unsigned integer.
typeof() {
	local SIGNED=false FLOATING=false GROUP=false in='' f='' b='';

	# Check for group return parameter.
	if test "$1" = "-g"; then GROUP=true; shift; fi;

	in="$*";

	# Check for negation sign.
	test "$in" = "${b:=${in#-}}" || SIGNED=true;
	in="$b"; b='';

	# Check for floating point.
	if test "$in" != "${b:=${in#*.}}" -a "$in" != "${f:=${in%.*}}"; then
		if test "$in" != "$f.$b"; then
			$GROUP && echo "5" || echo "string"; return;
		fi;
		FLOATING=true;
	fi;

	case "$in" in
		''|*[!0-9\.]*)
			if test "$in" != "${in#*[~\`\!@\#\$%\^\*()\+=\{\}\[\]|:;\"\'<>,?\/]}"; then
				$GROUP && echo "5" || echo "string";
			else
				if test "$in" != "${1#*[_\-.\\ ]}"; then
					$GROUP && echo "4" || echo "filename";
				else
					$GROUP && echo "3" || echo "alphanum";
				fi;
			fi;;
		*)
			if $FLOATING; then $GROUP && echo "2" || echo "double"; return; fi;
			if $SIGNED; then $GROUP && echo "1" || echo "int"; return; fi;
			$GROUP && echo "0" || echo "uint";
		;;
	esac;
}

# @describe - Ensures any characters that are embeded inside quotes can
#             be `eval`ed without worry of XSS / Parameter Injection.
# @usage [-p COUNT] sanitize_quote_escapes STRING('s)...
# @param STRING('s) - The string or strings you wish to sanitize.
# @param COUNT - The number of passes to run sanitization, default is 1.
sanitize_quote_escapes(){
	local ESCAPES="\\\"\$" TODO= DONE= PASSES=1 l=0 f= b= c=;

	if test "$1" = '-p'; then PASSES="$2"; shift 2; fi;

	TODO="$*"; # must be set after the conditional shift.

	while test "$l" -lt "$PASSES"; do
		# Ensure we cycle TODO after the first pass.
		if test "$l" -gt 0; then TODO="$DONE"; DONE=; fi;

		while test -n "$TODO"; do
			f="${TODO%%[$ESCAPES]*}"; # front of delimeter.
			b="${TODO#*[$ESCAPES]}"; # back of delimeter.

			# Only need to test one of the directions since $b and $f will be the same
			# if this is true.
			if test "$f" = "$TODO"; then break 2; fi;

			# Capture chracter by removing front
			test -z "$f" && c="$TODO" || c="${TODO#$f}";
			# and rear segments if they exist.
			test -z "$b"              || c="${c%$b}";

			DONE="$DONE$f\\$c";
			# Subtract front segment from TODO.
			TODO="${TODO#$f$c}";
		done;
		l="$((l + 1))"; # Increment loop counter.
	done;

	# If we haven't done anything, then just pass through the input.
	if test -z "$DONE"; then DONE="$TODO"; fi;
	printf '%s' "$DONE";
}


help () {
	echo -e 'Usage:';
	echo -e '\tnotify-send.sh [OPTION...] <SUMMARY> [BODY] - create a notification';
	echo -e '';
	echo -e 'Help Options:';
	echo -e '\t-h|--help                      Show help options.';
	echo -e '\t-v|--version                   Print version number.';
	echo -e '';
	echo -e 'Application Options:';
	echo -e '\t-u, --urgency=LEVEL            Specifies the urgency level (low, normal, critical).';
	echo -e '\t-t, --expire-time=TIME         Specifies the timeout in milliseconds at which to expire the notification.';
	echo -e '\t-f, --force-expire             Forcefully closes the notification when the notification has expired.';
	echo -e '\t-a, --app-name=APP_NAME        Specifies the app name for the icon.';
	echo -e '\t-i, --icon=ICON[,ICON...]      Specifies an icon filename or stock icon to display.';
	echo -e '\t-c, --category=TYPE[,TYPE...]  Specifies the notification category.';
	echo -e '\t-H, --hint=TYPE:NAME:VALUE     Specifies basic extra data to pass. Valid types are int, double, string and byte.';
	echo -e "\t-o, --action=LABEL:COMMAND     Specifies an action. Can be passed multiple times. LABEL is usually a button's label.";
	echo -e "\t                               COMMAND is a shell command executed when action is invoked.";
	echo -e '\t-d, --default-action=COMMAND   Specifies the default action which is usually invoked by clicking the notification.';
	echo -e '\t-l, --close-action=COMMAND     Specifies the action invoked when notification is closed.';
	echo -e '\t-p, --print-id                 Print the notification ID to the standard output.';
	echo -e '\t-r, --replace=ID               Replace existing notification.';
	echo -e '\t-R, --replace-file=FILE        Store and load notification replace ID to/from this file.';
	echo -e '\t-s, --close=ID                 Close notification.';
	echo -e '';
}

starts_with(){
	local STR="$1" QUERY="$2";
	test "${STR#$QUERY}" != "$STR"; # implicit exit code return.
}

notify_close () {
	test "$2" -lt 1 || sleep "$(expr substr "$2" 0 $((${#2} - 3)))";
	gdbus call $NOTIFY_ARGS --method org.freedesktop.Notifications.CloseNotification "$1" >&-;
}

process_urgency () {
	case "$1" in
		0|low) URGENCY=0 ;;
		1|normal) URGENCY=1 ;;
		2|critical) URGENCY=2 ;;
		*) abrt "urgency values are ( 0 => low; 1 => normal; 2 => critical )" ;;
	esac;
}

process_category () {
	local todo="$@" c=;
	while test -n "$todo"; do
		c="${todo%%,*}";
		process_hint "string:category:$c";
		test "$todo" = "${todo#*,}" && break || todo="${todo#*,}";
	done;
}

process_hint () {
	local l=0 todo="$@" field= t= n= v=;

	# Split argument into it's fields.
	while test -n "$todo"; do
		field="${todo%%:*}";
		case "$l" in
			0) t="$field";;
			1) n="$field";;
			2) v="$field";;
		esac;
		l=$((l+1));
		if test "$todo" = "${todo#*:}"; then todo=; else todo="${todo#*:}"; fi;
	done;
	test "$l" -eq 3 || abrt "hint syntax is \"TYPE:NAME:VALUE\".";

	case "$t" in
		byte|int32|double|string) true;;
		*) abrt "hint types must be one of (byte, int32, double, string).";;
	esac;

	test -n "$n" || abrt "hint name cannot be empty.";

	# Extra hint value typechecking
	if test "$t" = 'int32' -a "$(typeof -g "$v")" -gt 1; then
		abrt "hint type 'int32' expects whole numbers, Ex. (-Infinity... -1,0,1 ...Infinity).";
	elif test "$t" = 'byte'; then
		if test "$(typeof "$v")" != "uint"; then
			abrt "hint type 'byte' expects unsigned number, Ex. (0,1,2 ...Infinity).";
		elif test "$v" -gt 255; then
			abrt "hint type 'byte' overflow, number must be (0-255).";
		fi;
	elif test "$t" = 'double' && test "$(typeof -g "$v")" -gt 2; then
		abrt "hint type 'double'";
	elif test "$t" = 'string'; then
		# Add quote buffer to string values
		v="\"$(sanitize_quote_escapes "$2")\"";
	fi;

	HINTS="$HINTS,\"$n\":<$t $v>";
}

process_action () {
	local l=0 todo="$@" field= s= c=;

	# Split argument into it's fields.
	while test -n "$todo"; do
		field="${todo%%:*}";
		case "$l" in
			0) s="$field";;
			1) c="$field";;
		esac;
		l=$((l+1));
		test "$todo" = "${todo#*:}" && break || todo="${todo#*:}";
	done;
	test "$l" -eq 2 || abrt "action syntax is \"NAME:COMMAND\"";

	test -n "$s" || abrt "action name cannot be empty.";

	# The user isn't intended to be able to interact with our notifications
	# outside this application, so keep the API simple and use numbers
	# for each custom action.
	ACTION_COUNT="$((ACTION_COUNT + 1))";
	AKEYS="$AKEYS,\"$ACTION_COUNT\",\"$s\"";
	ACMDS="$ACMDS \"$ACTION_COUNT\" \"$(sanitize_quote_escapes "$c")\"";
}

# key=default: key:command and key:label, with empty label
# key=close:   key:command, no key:label (no button for the on-close event)
process_special_action () {
	test -n "$2" || abrt "Command must not be empty";
	if test "$1" = 'default'; then
		# That documentation is really hard to read, yes this is correct.
		AKEYS="$AKEYS,\"default\",\"Okay\"";
	fi;

	ACMDS="$ACMDS \"$1\" \"$(sanitize_quote_escapes "$2")\"";
}

process_posargs () {
	if test "$1" != "${1#-}" ; then
		abrt "unknown option $1";
	fi;

	# TODO: Ensure these exist where necessary. Maybe extend functionality.
	#       Could include some more verbose logging when a user's missing an arg.
	BODY="$1";
	SUMMARY="$2"; # This can be empty, so a null param is fine.

	# Alert the user we weren't expecting any more arguments.
	if test -n "$3"; then
		abrt "unexpected positional argument \"$3\". See \"notify-send.sh --help\".";
	fi;
}

################################################################################
## Main Script

${DEBUG_NOTIFY_SEND:=false} && {
	exec 2>"$TMP/.$APP_NAME.$$.errlog";
	set -x;
	trap "set >&2" 0;
}

while test "$#" -gt 0; do
	case "$1" in
		#--) positional=true;;
		-h|--help) help; exit 0;;
		-v|--version) echo "v$VERSION"; exit 0;;
		-f|--force-expire) export EXPLICIT_CLOSE=true;;
		-p|--print-id) PRINT_ID=true;;
		-u|--urgency|--urgency=*)
			starts_with "$1" '--urgency=' && s="${1#*=}" || { shift; s="$1"; };
			process_urgency "$s";
		;;
		-t|--expire-time|--expire-time=*)
			starts_with "$1" '--expire-time=' && s="${1#*=}" || { shift; s="$1"; };
			EXPIRE_TIME="$s";
		;;
		-a|--app-name|--app-name=*)
			starts_with "$1" '--app-name=' && s="${1#*=}" || { shift; s="$1"; };
			export APP_NAME="$s";
		;;
		-i|--icon|--icon=*)
			starts_with "$1" '--icon=' && s="${1#*=}" || { shift; s="$1"; };
			ICON="$s";
		;;
		-c|--category|--category=*)
			starts_with "$1" '--category=' && s="${1#*=}" || { shift; s="$1"; };
			process_category "$s";
		;;
		-H|--hint|--hint=*)
			starts_with "$1" '--hint=' && s="${1#*=}" || { shift; s="$1"; };
			process_hint "$s";
		;;
		-o|--action|--action=*)
			starts_with "$1" '--action=' && s="${1#*=}" || { shift; s="$1"; };
			process_action "$s";
		;;
		-d|--default-action|--default-action=*)
			starts_with "$1" '--default-action=' && s="${1#*=}" || { shift; s="$1"; };
			process_special_action default "$s";
		;;
		-l|--close-action|--close-action=*)
			starts_with "$1" '--close-action=' && s="${1#*=}" || { shift; s="$1"; };
			process_special_action close "$s";
		;;
		-r|--replace|--replace=*)
			starts_with "$1" '--replace=' && s="${1#*=}" || { shift; s="$1"; };

			test "$(typeof "$s")" = "uint" -a "$s" -gt 0 || \
				abrt "ID must be a positive integer greater than 0, but was provided \"$s\".";

			ID="$s";
		;;
		-R|--replace-file|--replace-file=*)
			starts_with "$1" '--replace-file=' && s="${1#*=}" || { shift; s="$1"; };

			ID_FILE="$s"; ! test -s "$ID_FILE" || read ID < "$ID_FILE";
		;;
		-s|--close|--close=*)
			starts_with "$1" '--close=' && s="${1#*=}" || { shift; s="$1"; };

			test "$(typeof "$s")" = "uint" -a "$s" -gt 0 || \
				abrt "ID must be a positive integer greater than 0, but was provided \"$s\".";

			ID="$s";

			notify_close "$ID" "$EXPIRE_TIME";
			exit $?;
		;;
		*)
			# NOTE: breaking change from master. Will need to be reflected in
			#       versioning. Before, the postitionals were mobile, but per the
			#       reference, they aren't supposed to be. This simplifies the
			#       application.
			process_posargs "$*";
			s="$#"; # Reuse for temporary storage of shifts remaining.
			shift "$((s - 1))"; # Clear remaining arguments - 1 so the loop stops.
		;;
	esac;
	shift;
done;

# send the dbus message, collect the notification ID
OLD_ID="$ID";
NEW_ID=0;
s="$(gdbus call --session \
	--dest org.freedesktop.Notifications \
	--object-path /org/freedesktop/Notifications \
	--method org.freedesktop.Notifications.Notify \
	"$APP_NAME" "uint32 $ID" "$ICON" "$SUMMARY" "$BODY" \
	"[${AKEYS#,}]" "{\"urgency\":<byte $URGENCY>$HINTS}" \
	"int32 ${EXPIRE_TIME}")";

# process the ID
s="${s%,*}"; NEW_ID="${s#* }";


if ! ( test "$(typeof "$NEW_ID")" = "uint" && test "$NEW_ID" -gt 1 ); then
	abrt "invalid notification ID from gdbus.";
fi;

test "$OLD_ID" -gt 1 || ID=${NEW_ID};

if test -n "$ID_FILE" -a "$OLD_ID" -lt 1; then
	echo "$ID" > "$ID_FILE";
fi;

if $PRINT_ID; then
	echo "$ID";
fi;

if test -n "$ACMDS"; then
	# bg task to monitor dbus and perform the actions
	# Uses field expansion to form string based array.
	# Also, use deterministic execution for the rare instance where
	# the filesystem doesn't support linux executable permissions bit,
	# or it's been left unset by a package manager.
	eval "/bin/sh $PROCDIR/notify-action.sh $ID $ACMDS &";
fi;

# bg task to wait expire time and then actively close notification
if $EXPLICIT_CLOSE && test "$EXPIRE_TIME" -gt 0; then
	setsid -f /bin/sh "$SELF" -t "$EXPIRE_TIME" -s "$ID" & # >&- 2>&- <&-
fi;
