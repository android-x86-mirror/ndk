# Copyright (C) 2009 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# A collection of shell function definitions used by various build scripts
# in the Android NDK (Native Development Kit)
#

# Get current script name into PROGNAME
PROGNAME=`basename $0`

# Put location of Android NDK into ANDROID_NDK_ROOT and
# perform a tiny amount of sanity check
#
if [ -z "$ANDROID_NDK_ROOT" ] ; then
    # Try to auto-detect the NDK root by walking up the directory
    # path to the current script.
    PROGDIR=`dirname $0`
    while [ -n "1" ] ; do
        if [ -d $PROGDIR/build/core ] ; then
            break
        fi
        if [ -z $PROGDIR -o $PROGDIR = '.' ] ; then
            echo "Please define ANDROID_NDK_ROOT to point to the root of your"
            echo "Android NDK installation."
            exit 1
        fi
        PROGDIR=`dirname $PROGDIR`
    done
    ANDROID_NDK_ROOT=`cd $PROGDIR && pwd`
fi

echo "$ANDROID_NDK_ROOT" | grep -q -e " "
if [ $? = 0 ] ; then
    echo "ERROR: The Android NDK installation path contains a space !"
    echo "Please install to a different location."
    exit 1
fi

if [ ! -d $ANDROID_NDK_ROOT ] ; then
    echo "ERROR: Your ANDROID_NDK_ROOT variable does not point to a directory."
    exit 1
fi

if [ ! -f $ANDROID_NDK_ROOT/build/core/ndk-common.sh ] ; then
    echo "ERROR: Your ANDROID_NDK_ROOT variable does not point to a valid directory."
    exit 1
fi

## Logging support
##
VERBOSE=${VERBOSE-yes}
VERBOSE2=${VERBOSE2-no}

TMPLOG=

# Setup a log file where all log() and log2() output will be sent
#
# $1: log file path  (optional)
#
setup_log_file ()
{
    if [ -n "$1" ] ; then
        TMPLOG="$1"
    else
        TMPLOG=/tmp/ndk-log-$$.log
    fi
    rm -f $TMPLOG && touch $TMPLOG
    echo "To follow build in another terminal, please use: tail -F $TMPLOG"
}

dump ()
{
    if [ -n "$TMPLOG" ] ; then
        echo "$@" >> $TMPLOG
    fi
    echo "$@"
}

log ()
{
    if [ "$VERBOSE" = "yes" ] ; then
        echo "$@"
    else
        if [ "$TMPLOG" ] ; then
            echo "$@" >> $TMPLOG
        fi
    fi
}

log2 ()
{
    if [ "$VERBOSE2" = "yes" ] ; then
        echo "$@"
    else
        if [ -n "$TMPLOG" ] ; then
            echo "$@" >> $TMPLOG
        fi
    fi
}

run ()
{
    if [ "$VERBOSE" = "yes" ] ; then
        echo "##### NEW COMMAND"
        echo "$@"
        $@ 2>&1
    else
        if [ -n "$TMPLOG" ] ; then
            echo "##### NEW COMMAND" >> $TMPLOG
            echo "$@" >> $TMPLOG
            $@ >>$TMPLOG 2>&1
        else
            $@ > /dev/null 2>&1
        fi
    fi
}

## Utilities
##

# return the value of a given named variable
# $1: variable name
#
# example:
#    FOO=BAR
#    BAR=ZOO
#    echo `var_value $FOO`
#    will print 'ZOO'
#
var_value ()
{
    # find a better way to do that ?
    eval echo "$`echo $1`"
}

# convert to uppercase
# assumes tr is installed on the platform ?
#
to_uppercase ()
{
    echo $1 | tr "[:lower:]" "[:upper:]"
}

## Normalize OS and CPU
##
HOST_ARCH=`uname -m`
case "$HOST_ARCH" in
    i?86) HOST_ARCH=x86
    ;;
    *64) HOST_ARCH=x86 # x86_64 is not supported, fall back to x86
    ;;
    powerpc) HOST_ARCH=ppc
    ;;
esac

log2 "HOST_ARCH=$HOST_ARCH"

# at this point, the supported values for CPU are:
#   x86
#   x86_64
#   ppc
#
# other values may be possible but haven't been tested
#
HOST_EXE=""
HOST_OS=`uname -s`
case "$HOST_OS" in
    Darwin)
        HOST_OS=darwin
        ;;
    Linux)
        # note that building  32-bit binaries on x86_64 is handled later
        HOST_OS=linux
        ;;
    FreeBsd)  # note: this is not tested
        HOST_OS=freebsd
        ;;
    CYGWIN*|*_NT-*)
        HOST_OS=windows
        HOST_EXE=.exe
        if [ "x$OSTYPE" = xcygwin ] ; then
            HOST_OS=cygwin
        fi
        ;;
esac

log2 "HOST_OS=$HOST_OS"
log2 "HOST_EXE=$HOST_EXE"

# at this point, the value of HOST_OS should be one of the following:
#   linux
#   darwin
#    windows (MSys)
#    cygwin
#
# Note that cygwin is treated as a special case because it behaves very differently
# for a few things. Other values may be possible but have not been tested
#

# define HOST_TAG as a unique tag used to identify both the host OS and CPU
# supported values are:
#
#   linux-x86
#   linux-x86_64
#   darwin-x86
#   darwin-ppc
#   windows
#
# other values are possible but were not tested.
#
compute_host_tag ()
{
    case "$HOST_OS" in
        windows|cygwin)
            HOST_TAG="windows"
            ;;
        *)  HOST_TAG="${HOST_OS}-${HOST_ARCH}"
    esac
    log2 "HOST_TAG=$HOST_TAG"
}

compute_host_tag

# Compute the number of host CPU cores an HOST_NUM_CPUS
#
case "$HOST_OS" in
    linux)
        HOST_NUM_CPUS=`cat /proc/cpuinfo | grep processor | wc -l`
        ;;
    darwin|freebsd)
        HOST_NUM_CPUS=`sysctl -n hw.ncpu`
        ;;
    windows|cygwin)
        HOST_NUM_CPUS=$NUMBER_OF_PROCESSORS
        ;;
    *)  # let's play safe here
        HOST_NUM_CPUS=1
esac

log2 "HOST_NUM_CPUS=$HOST_NUM_CPUS"

# If BUILD_NUM_CPUS is not already defined in your environment,
# define it as the double of HOST_NUM_CPUS. This is used to
# run Make commends in parralles, as in 'make -j$BUILD_NUM_CPUS'
#
if [ -z "$BUILD_NUM_CPUS" ] ; then
    BUILD_NUM_CPUS=`expr $HOST_NUM_CPUS \* 2`
fi

log2 "BUILD_NUM_CPUS=$BUILD_NUM_CPUS"


##  HOST TOOLCHAIN SUPPORT
##

# force the generation of 32-bit binaries on 64-bit systems
#
FORCE_32BIT=no
force_32bit_binaries ()
{
    if [ "$HOST_ARCH" = x86_64 ] ; then
        log2 "Forcing generation of 32-bit host binaries on $HOST_ARCH"
        FORCE_32BIT=yes
        HOST_ARCH=x86
        log2 "HOST_ARCH=$HOST_ARCH"
        compute_host_tag
    fi
}

# On Windows, cygwin binaries will be generated by default, but
# you can force mingw ones that do not link to cygwin.dll if you
# call this function.
#
disable_cygwin ()
{
    if [ $OS = cygwin ] ; then
        log2 "Disabling cygwin binaries generation"
        CFLAGS="$CFLAGS -mno-cygwin"
        LDFLAGS="$LDFLAGS -mno-cygwin"
        OS=windows
        HOST_OS=windows
        compute_host_tag
    fi
}

# Various probes are going to need to run a small C program
TMPC=/tmp/android-$$-test.c
TMPO=/tmp/android-$$-test.o
TMPE=/tmp/android-$$-test$EXE
TMPL=/tmp/android-$$-test.log

# cleanup temporary files
clean_temp ()
{
    rm -f $TMPC $TMPO $TMPL $TMPE
}

# cleanup temp files then exit with an error
clean_exit ()
{
    clean_temp
    exit 1
}

# this function will setup the compiler and linker and check that they work as advertised
# note that you should call 'force_32bit_binaries' before this one if you want it to
# generate 32-bit binaries on 64-bit systems (that support it).
#
setup_toolchain ()
{
    if [ -z "$CC" ] ; then
        CC=gcc
    fi

    log2 "Using '$CC' as the C compiler"

    # check that we can compile a trivial C program with this compiler
    cat > $TMPC <<EOF
int main(void) {}
EOF

    if [ "$FORCE_32BIT" = yes ] ; then
        CFLAGS="$CFLAGS -m32"
        LDFLAGS="$LDFLAGS -m32"
        compile
        if [ $? != 0 ] ; then
            # sometimes, we need to also tell the assembler to generate 32-bit binaries
            # this is highly dependent on your GCC installation (and no, we can't set
            # this flag all the time)
            CFLAGS="$CFLAGS -Wa,--32"
            compile
        fi
    fi

    compile
    if [ $? != 0 ] ; then
        echo "your C compiler doesn't seem to work:"
        cat $TMPL
        clean_exit
    fi
    log "CC         : compiler check ok ($CC)"

    # check that we can link the trivial program into an executable
    if [ -z "$LD" ] ; then
        LD=$CC
    fi
    link
    if [ $? != 0 ] ; then
        OLD_LD=$LD
        LD=gcc
        compile
        link
        if [ $? != 0 ] ; then
            LD=$OLD_LD
            echo "your linker doesn't seem to work:"
            cat $TMPL
            clean_exit
        fi
    fi
    log2 "Using '$LD' as the linker"
    log "LD         : linker check ok ($LD)"

    # check the C++ compiler
    if [ -z "$CXX" ] ; then
        CXX=g++
    fi
    if [ -z "$CXXFLAGS" ] ; then
        CXXFLAGS=$CFLAGS
    fi

    log2 "Using '$CXX' as the C++ compiler"

    cat > $TMPC <<EOF
#include <iostream>
using namespace std;
int main()
{
  cout << "Hello World!" << endl;
  return 0;
}
EOF

    compile_cpp
    if [ $? != 0 ] ; then
        echo "your C++ compiler doesn't seem to work"
        cat $TMPL
        clean_exit
    fi

    log "CXX        : C++ compiler check ok ($CXX)"

    # XXX: TODO perform AR checks
    AR=ar
    ARFLAGS=
}

# try to compile the current source file in $TMPC into an object
# stores the error log into $TMPL
#
compile ()
{
    log2 "Object     : $CC -o $TMPO -c $CFLAGS $TMPC"
    $CC -o $TMPO -c $CFLAGS $TMPC 2> $TMPL
}

compile_cpp ()
{
    log2 "Object     : $CXX -o $TMPO -c $CXXFLAGS $TMPC"
    $CXX -o $TMPO -c $CXXFLAGS $TMPC 2> $TMPL
}

# try to link the recently built file into an executable. error log in $TMPL
#
link()
{
    log2 "Link      : $LD -o $TMPE $TMPO $LDFLAGS"
    $LD -o $TMPE $TMPO $LDFLAGS 2> $TMPL
}

# run a command
#
execute()
{
    log2 "Running: $*"
    $*
}

# perform a simple compile / link / run of the source file in $TMPC
compile_exec_run()
{
    log2 "RunExec    : $CC -o $TMPE $CFLAGS $TMPC"
    compile
    if [ $? != 0 ] ; then
        echo "Failure to compile test program"
        cat $TMPC
        cat $TMPL
        clean_exit
    fi
    link
    if [ $? != 0 ] ; then
        echo "Failure to link test program"
        cat $TMPC
        echo "------"
        cat $TMPL
        clean_exit
    fi
    $TMPE
}

pattern_match ()
{
    echo "$2" | grep -q -E -e "$1"
}

# Let's check that we have a working md5sum here
check_md5sum ()
{
    A_MD5=`echo "A" | md5sum | cut -d' ' -f1`
    if [ "$A_MD5" != "bf072e9119077b4e76437a93986787ef" ] ; then
        echo "Please install md5sum on this machine"
        exit 2
    fi
}

# Find if a given shell program is available.
# We need to take care of the fact that the 'which <foo>' command
# may return either an empty string (Linux) or something like
# "no <foo> in ..." (Darwin). Also, we need to redirect stderr
# to /dev/null for Cygwin
#
# $1: variable name
# $2: program name
#
# Result: set $1 to the full path of the corresponding command
#         or to the empty/undefined string if not available
#
find_program ()
{
    local PROG
    PROG=`which $2 2>/dev/null`
    if [ -n "$PROG" ] ; then
        if pattern_match '^no ' "$PROG"; then
            PROG=
        fi
    fi
    eval $1="$PROG"
}

prepare_download ()
{
    find_program CMD_WGET wget
    find_program CMD_CURL curl
    find_program CMD_SCRP scp
}

# Download a file with either 'curl', 'wget' or 'scp'
#
# $1: source URL (e.g. http://foo.com, ssh://blah, /some/path)
# $2: target file
download_file ()
{
    # Is this HTTP, HTTPS or FTP ?
    if pattern_match "^(http|https|ftp):.*" "$1"; then
        if [ -n "$CMD_WGET" ] ; then
            run $CMD_WGET -O $2 $1 
        elif [ -n "$CMD_CURL" ] ; then
            run $CMD_CURL -o $2 $1
        else
            echo "Please install wget or curl on this machine"
            exit 1
        fi
        return
    fi

    # Is this SSH ?
    # Accept both ssh://<path> or <machine>:<path>
    #
    if pattern_match "^(ssh|[^:]+):.*" "$1"; then
        if [ -n "$CMD_SCP" ] ; then
            scp_src=`echo $1 | sed -e s%ssh://%%g`
            run $CMD_SCP $scp_src $2
        else
            echo "Please install scp on this machine"
            exit 1
        fi
        return
    fi

    # Is this a file copy ?
    # Accept both file://<path> or /<path>
    #
    if pattern_match "^(file://|/).*" "$1"; then
        cp_src=`echo $1 | sed -e s%^file://%%g`
        run cp -f $cp_src $2
        return
    fi
}
