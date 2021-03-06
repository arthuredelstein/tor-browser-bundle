#!/bin/bash
#
# GNU/Linux does not really require something like RelativeLink.c
# However, we do want to have the same look and feel with similar features.
#
# To run in debug mode simply pass --debug
#
# Copyright 2015 The Tor Project.  See LICENSE for licensing information.

complain_dialog_title="Tor Browser"

# First, make sure DISPLAY is set.  If it isn't, we're hosed; scream
# at stderr and die.
if [ "x$DISPLAY" = "x" ]; then
    echo "$complain_dialog_title must be run within the X Window System." >&2
    echo "Exiting." >&2
    exit 1
fi

# Second, make sure this script wasn't started as 'sh start-tor-browser' or
# similar.
if [ "x$BASH" = "x" ]; then
    echo "$complain_dialog_title should be started as './start-tor-browser'"
    echo "Exiting." >&2
    exit 1;
fi

# Do not (try to) connect to the session manager
unset SESSION_MANAGER

# Determine whether we are running in a terminal.  If we are, we
# should send our error messages to stderr...
ARE_WE_RUNNING_IN_A_TERMINAL=0
if [ -t 1 -o -t 2 ]; then
	ARE_WE_RUNNING_IN_A_TERMINAL=1
fi

# ...unless we're running in the same terminal as startx or xinit.  In
# that case, the user is probably running us from a GUI file manager
# in an X session started by typing startx at the console.
#
# Hopefully, the local ps command supports BSD-style options.  (The ps
# commands usually used on Linux and FreeBSD do; do any other OSes
# support running Linux binaries?)
ps T 2>/dev/null |grep startx 2>/dev/null |grep -v grep 2>&1 >/dev/null
not_running_in_same_terminal_as_startx="$?"
ps T 2>/dev/null |grep xinit 2>/dev/null |grep -v grep 2>&1 >/dev/null
not_running_in_same_terminal_as_xinit="$?"

# not_running_in_same_terminal_as_foo has the value 1 if we are *not*
# running in the same terminal as foo.
if [ "$not_running_in_same_terminal_as_startx" -eq 0 -o \
     "$not_running_in_same_terminal_as_xinit" -eq 0 ]; then
	ARE_WE_RUNNING_IN_A_TERMINAL=0
fi

# Complain about an error, by any means necessary.
# Usage: complain message
# message must not begin with a dash.
complain () {
	# Trim leading newlines, to avoid breaking formatting in some dialogs.
	complain_message="`echo "$1" | sed '/./,$!d'`"

	# If we're being run in a terminal, complain there.
	if [ "$ARE_WE_RUNNING_IN_A_TERMINAL" -ne 0 ]; then
		echo "$complain_message" >&2
		return
	fi

	# Otherwise, we're being run by a GUI program of some sort;
	# try to pop up a message in the GUI in the nicest way
	# possible.
	#
	# In mksh, non-existent commands return 127; I'll assume all
	# other shells set the same exit code if they can't run a
	# command.  (xmessage returns 1 if the user clicks the WM
	# close button, so we do need to look at the exact exit code,
	# not just assume the command failed to display a message if
	# it returns non-zero.)

	# First, try zenity.
	zenity --error \
		--title="$complain_dialog_title" \
		--text="$complain_message"
	if [ "$?" -ne 127 ]; then
		return
	fi

	# Try kdialog.
	kdialog --title "$complain_dialog_title" \
		--error "$complain_message"
	if [ "$?" -ne 127 ]; then
		return
	fi

	# Try xmessage.
	xmessage -title "$complain_dialog_title" \
		-center \
		-buttons OK \
		-default OK \
		-xrm '*message.scrollVertical: Never' \
		"$complain_message"
	if [ "$?" -ne 127 ]; then
		return
	fi

	# Try gxmessage.  This one isn't installed by default on
	# Debian with the default GNOME installation, so it seems to
	# be the least likely program to have available, but it might
	# be used by one of the 'lightweight' Gtk-based desktop
	# environments.
	gxmessage -title "$complain_dialog_title" \
		-center \
		-buttons GTK_STOCK_OK \
		-default OK \
		"$complain_message"
	if [ "$?" -ne 127 ]; then
		return
	fi
}

if [ "`id -u`" -eq 0 ]; then
	complain "The Tor Browser Bundle should not be run as root.  Exiting."
	exit 1
fi

debug=0
usage_message="usage: $0 [--debug]"
# !!! We may have more than one argument, changed -eq to -ge in if & elif clauses below
if [ "$#" -ge 1 -a \( "x$1" = "x--debug" -o "x$1" = "x-debug" \) ]; then
	debug=1
	shift # pop the debug argument
	printf "\nDebug enabled.\n\n"
elif [ "$#" -ge 1 -a \( "x$1" = "x--help" -o "x$1" = "x-help" \) ]; then
	echo "$usage_message"
	exit 0
fi

# If the user hasn't requested 'debug mode', close whichever of stdout
# and stderr are not ttys, to keep Firefox and the stuff loaded by/for
# it (including the system's shared-library loader) from printing
# messages to $HOME/.xsession-errors .  (Users wouldn't have seen
# messages there anyway.)
#
# If the user has requested 'debug mode', don't muck with the FDs.
if [ "$debug" -ne 1 ]; then
  if [ '!' -t 1 ]; then
    # stdout is not a tty
    exec >/dev/null
  fi
  if [ '!' -t 2 ]; then
    # stderr is not a tty
    exec 2>/dev/null
  fi
fi

# If XAUTHORITY is unset, set it to its default value of $HOME/.Xauthority
# before we change HOME below.  (See xauth(1) and #1945.)  XDM and KDM rely
# on applications using this default value.
if [ -z "$XAUTHORITY" ]; then
	XAUTHORITY=~/.Xauthority
	export XAUTHORITY
fi

# If this script is being run through a symlink, we need to know where
# in the filesystem the script itself is, not where the symlink is.
myname="$0"
if [ -L "$myname" ]; then
	# XXX readlink is not POSIX, but is present in GNU coreutils
	# and on FreeBSD.  Unfortunately, the -f option (which follows
	# a whole chain of symlinks until it reaches a non-symlink
	# path name) is a GNUism, so we have to have a fallback for
	# FreeBSD.  Fortunately, FreeBSD has realpath instead;
	# unfortunately, that's also non-POSIX and is not present in
	# GNU coreutils.
	#
	# If this launcher were a C program, we could just use the
	# realpath function, which *is* POSIX.  Too bad POSIX didn't
	# make that function accessible to shell scripts.

	# If realpath is available, use it; it Does The Right Thing.
	possibly_my_real_name="`realpath "$myname" 2>/dev/null`"
	if [ "$?" -eq 0 ]; then
		myname="$possibly_my_real_name"
	else
		# realpath is not available; hopefully readlink -f works.
		myname="`readlink -f "$myname" 2>/dev/null`"
		if [ "$?" -ne 0 ]; then
			# Ugh.
			complain "start-tor-browser cannot be run using a symlink on this operating system."
		fi
	fi
fi

# Try to be agnostic to where we're being started from, chdir to where
# the script is.
mydir="`dirname "$myname"`"
test -d "$mydir" && cd "$mydir"

# This is a fix for an ibus issue on some Linux systems. See #9353 for more
# details. The symlink needs to be created before we change HOME.
if [ ! -d ".config/ibus" ]; then
  mkdir -p .config/ibus
  ln -nsf ~/.config/ibus/bus .config/ibus
fi

# If ${PWD} results in a zero length HOME, we can try something else...
if [ ! "${PWD}" ]; then
	# "hacking around some braindamage"
	HOME="`pwd`"
	export HOME
	surveysays="This system has a messed up shell.\n"
else
	HOME="${PWD}"
	export HOME
fi

SYSARCHITECTURE=$(getconf LONG_BIT)
TORARCHITECTURE=$(expr "$(file TorBrowser/Tor/tor)" : '.*ELF \([[:digit:]]*\)')

if [ $SYSARCHITECTURE -ne $TORARCHITECTURE ]; then
   complain "Wrong architecture? 32-bit vs. 64-bit."
   exit 1
fi

LD_LIBRARY_PATH="${HOME}/TorBrowser/Tor/"
export LD_LIBRARY_PATH

function setControlPortPasswd() {
    local ctrlPasswd=$1

    if test -z "$ctrlPasswd" -o "$ctrlPasswd" = $'\"secret\"' ; then
        unset TOR_CONTROL_PASSWD
        return
    fi

    if test "${ctrlPasswd:0:1}" = $'\"'; then  # First 2 chars were '"
        printf "Using system Tor process.\n"
        export TOR_CONTROL_PASSWD
    else
        complain "There seems to have been a quoting problem with your \
TOR_CONTROL_PASSWD environment variable."
        cat <<EOF

The Tor ControlPort password should be given inside double quotes, inside single
quotes, i.e. if the ControlPort password is “secret” (without curly quotes) then
we must start this script after setting the environment variable exactly like
this:

  \$ TOR_CONTROL_PASSWD='"secret"' $myname

EOF
    fi
}

# Using a system-installed Tor process with Tor Browser:
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# The Tor ControlPort password should be given inside double quotes, inside
# single quotes, i.e. if the ControlPort password is “secret” (without
# curly quotes) then we must set the environment variable *exactly* like
# this:
#
# TOR_CONTROL_PASSWD='"secret"'
#
# Yes, the variable MUST be double-quoted, then single-quoted, exactly as
# shown. This is used by TorButtom to authenticate to Tor's ControlPort, and
# is necessary for using TBB with a with a system-installed Tor.
#
# Additionally, if using a system-installed Tor, the following about:config
# options should be set (values in <> mean they are the value taken from your
# torrc):
#
# SETTING NAME                            VALUE
# extensions.torbutton.banned_ports       [...],<SocksPort>,<ControlPort>
# extensions.torbutton.block_disk         false
# extensions.torbutton.custom.socks_host  127.0.0.1
# extensions.torbutton.custom.socks_port  <SocksPort>
# extensions.torbutton.inserted_button    true
# extensions.torbutton.launch_warning     false
# extensions.torbutton.loglevel           2
# extensions.torbutton.logmethod          0
# extensions.torbutton.settings_method    custom
# extensions.torbutton.socks_port         <SocksPort>
# extensions.torbutton.use_privoxy        false
# extensions.torlauncher.control_port      <ControlPort>
# extensions.torlauncher.loglevel          2
# extensions.torlauncher.logmethod         0
# extensions.torlauncher.prompt_at_startup false
# extensions.torlauncher.start_tor         false
#
# where the '[...]' in the banned_ports option means "leave anything that was
# already in the preference alone, just append the things specified after it".

# Either set `TOR_CONTROL_PASSWD` before running ./start-tor-browser, or put
# your password in the following line where the word “secret” is:
setControlPortPasswd ${TOR_CONTROL_PASSWD:='"secret"'}

# XXX: Debug mode for Firefox??

# not in debug mode, run proceed normally
printf "Launching Tor Browser for Linux in ${HOME}...\n"
cd "${HOME}"
# XXX Someday we should pass whatever command-line arguments we got
# (probably filenames or URLs) to Firefox.
# !!! Dash above comment! Now we pass command-line arguments we got (except --debug) to Firefox.
# !!! Use at your own risk!
# Adding --class for fixing bug 11102.
TOR_CONTROL_PASSWD=${TOR_CONTROL_PASSWD} ./firefox  --class "Tor Browser" \
    -profile TorBrowser/Data/Browser/profile.default "${@}"
exitcode="$?"
if [ "$exitcode" -ne 0 ]; then
	complain "Tor Browser exited abnormally.  Exit code: $exitcode"
	exit "$exitcode"
else
	printf '\nTor Browser exited cleanly.\n'
fi
