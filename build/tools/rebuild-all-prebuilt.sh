#!/bin/sh
#
# Copyright (C) 2010 The Android Open Source Project
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

# Download and rebuild all prebuilt binaries for the Android NDK
# This includes:
#    - cross toolchains (gcc, ld, gdb, etc...)
#    - target-specific gdbserver
#    - host ccache
#

. `dirname $0`/prebuilt-common.sh
PROGDIR=`dirname $0`

prepare_host_flags

NDK_DIR=
register_var_option "--ndk-dir=<path>" NDK_DIR "Don't package, copy binaries to target NDK directory"

BUILD_DIR=`random_temp_directory`
register_var_option "--build-dir=<path>" BUILD_DIR "Specify temporary build directory" "/tmp/<random>"

GDB_VERSION=6.6
register_var_option "--gdb-version=<version>" GDB_VERSION "Specify gdb version"

OPTION_TOOLCHAIN_SRC_PKG=
register_var_option "--toolchain-src-pkg=<file>" OPTION_TOOLCHAIN_SRC_PKG "Use toolchain source package."

OPTION_TOOLCHAIN_SRC_DIR=
register_var_option "--toolchain-src-dir=<path>" OPTION_TOOLCHAIN_SRC_DIR "Use toolchain source directory."

RELEASE=`date +%Y%m%d`
PACKAGE_DIR=/tmp/ndk-prebuilt/prebuilt-$RELEASE
register_var_option "--package-dir=<path>" PACKAGE_DIR "Put prebuilt tarballs into <path>."

OPTION_TRY_X86=no
register_var_option "--try-x86" OPTION_TRY_X86 "Build experimental x86 toolchain too."

OPTION_GIT_HTTP=no
register_var_option "--git-http" OPTION_GIT_HTTP "Download sources with http."

register_mingw_option

PROGRAM_PARAMETERS=
PROGRAM_DESCRIPTION=\
"Download and rebuild from scratch all prebuilt binaries for the Android NDK.
By default, this will create prebuilt binary tarballs in: $PACKAGE_DIR

You can however use --ndk-dir=<path> to instead copy the binaries directly
to an existing NDK installation.

By default, the script will download the toolchain sources from the Internet,
but you can override this using either --toolchain-src-dir or
--toolchain-src-pkg.

Please read docs/DEVELOPMENT.TXT for more usage information about this
script.
"

extract_parameters $@

if [ -n "$PACKAGE_DIR" -a -n "$NDK_DIR" ] ; then
    echo "ERROR: You cannot use both --package-dir and --ndk-dir at the same time!"
    exit 1
fi

if [ -z "$NDK_DIR" ] ; then
    mkdir -p "$PACKAGE_DIR"
    if [ $? != 0 ] ; then
        echo "ERROR: Could not create directory: $PACKAGE_DIR"
        exit 1
    fi
    NDK_DIR=/tmp/ndk-toolchain/ndk-prebuilt-$$
    mkdir -p $NDK_DIR
else
    if [ ! -d "$NDK_DIR" ] ; then
        echo "ERROR: NDK directory does not exists: $NDK_DIR"
        exit 1
    fi
    PACKAGE_DIR=
fi

if [ -n "$PARAMETERS" ]; then
    dump "ERROR: Too many parameters. See --help for proper usage."
    exit 1
fi

mkdir -p $BUILD_DIR
if [ $? != 0 ] ; then
    dump "ERROR: Could not create build directory: $BUILD_DIR"
    exit 1
fi
setup_default_log_file "$BUILD_DIR/log.txt"

if [ -n "$OPTION_TOOLCHAIN_SRC_DIR" ] ; then
    if [ -n "$OPTION_TOOLCHAIN_SRC_PKG" ] ; then
        dump "ERROR: You can't use both --toolchain-src-dir and --toolchain-src-pkg"
        exi t1
    fi
    SRC_DIR="$OPTION_TOOLCHAIN_SRC_DIR"
    if [ ! -d "$SRC_DIR/gcc" ] ; then
        dump "ERROR: Invalid toolchain source directory: $SRC_DIR"
        exit 1
    fi
else
    SRC_DIR="$BUILD_DIR/src"
    mkdir -p "$SRC_DIR"
fi

FLAGS=""
if [ $VERBOSE = yes ] ; then
    FLAGS="--verbose"
fi

if [ -z "$OPTION_TOOLCHAIN_SRC_DIR" ] ; then
    if [ -n "$OPTION_TOOLCHAIN_SRC_PKG" ] ; then
        # Unpack the toolchain sources
        if [ ! -f "$OPTION_TOOLCHAIN_SRC_PKG" ] ; then
            dump "ERROR: Invalid toolchain source package: $OPTION_TOOLCHAIN_SRC_PKG"
            exit 1
        fi
        TARFLAGS="xf"
        if [ $VERBOSE2 = yes ] ; then
            TARFLAGS="v$TARFLAGS"
        fi
        if pattern_match '\.tar\.gz$' "$OPTION_TOOLCHAIN_SRC_PKG"; then
            TARFLAGS="z$TARFLAGS"
        fi
        if pattern_match '\.tar\.bz2$' "$OPTION_TOOLCHAIN_SRC_PKG"; then
            TARFLAGS="j$TARFLAGS"
        fi
        dump "Unpack sources from $OPTION_TOOLCHAIN_SRC_PKG"
        mkdir -p $SRC_DIR && tar $TARFLAGS $OPTION_TOOLCHAIN_SRC_PKG -C $SRC_DIR
        if [ $? != 0 ] ; then
            dump "ERROR: Could not unpack toolchain sources!"
            exit 1
        fi
    else
        # Download the toolchain sources
        dump "Download sources from android.git.kernel.org"
        DOWNLOAD_FLAGS="$FLAGS"
        if [ $OPTION_GIT_HTTP = "yes" ] ; then
            DOWNLOAD_FLAGS="$DOWNLOAD_FLAGS --git-http"
        fi
        $PROGDIR/download-toolchain-sources.sh $DOWNLOAD_FLAGS $SRC_DIR
        if [ $? != 0 ] ; then
            dump "ERROR: Could not download toolchain sources!"
            exit 1
        fi
    fi
fi # ! $TOOLCHAIN_SRC_DIR

if [ "$MINGW" = yes ] ; then
    FLAGS="$FLAGS --mingw"
fi

# Needed to set HOST_TAG to windows if --mingw is used.
prepare_host_flags

# Package a directory in a .tar.bz2 archive
#
# $1: textual description
# $2: final package name (without .tar.bz2 suffix)
# $3: relative root path from $NDK_DIR
#
package_it ()
{
    if [ -n "$PACKAGE_DIR" ] ; then
        dump "Packaging $1 ($2.tar.bz2) ..."
        PREBUILT_PACKAGE="$PACKAGE_DIR/$2".tar.bz2
        (cd $NDK_DIR && tar cjf $PREBUILT_PACKAGE "$3")
        if [ $? != 0 ] ; then
            dump "ERROR: Could not package $1!"
            exit 1
        fi
    fi
}

# Build the toolchain from sources
build_toolchain ()
{
    dump "Building $1 toolchain... (this can be long)"
    run $PROGDIR/build-gcc.sh $FLAGS --build-out=$BUILD_DIR/toolchain-$1 $SRC_DIR $NDK_DIR $1
    if [ $? != 0 ] ; then
        dump "ERROR: Could not build $1 toolchain!"
        exit 1
    fi
    package_it "$1 toolchain" "$1-$HOST_TAG" "toolchains/$1/prebuilt/$HOST_TAG"
}

build_gdbserver ()
{
    if [ "$MINGW" = yes ] ; then
        dump "Skipping gdbserver build (--mingw option being used)."
        return
    fi
    dump "Build $1 gdbserver..."
    $PROGDIR/build-gdbserver.sh $FLAGS --build-out=$BUILD_DIR/gdbserver-$1 $SRC_DIR/gdb/gdb-$GDB_VERSION/gdb/gdbserver $NDK_DIR $1
    if [ $? != 0 ] ; then
        dump "ERROR: Could not build $1 toolchain!"
        exit 1
    fi
    package_it "$1 gdbserver" "$1-gdbserver" "toolchains/$1/prebuilt/gdbserver"
}

build_toolchain arm-eabi-4.4.0
build_gdbserver arm-eabi-4.4.0

build_toolchain arm-linux-androideabi-4.4.3
build_gdbserver arm-linux-androideabi-4.4.3

if [ "$OPTION_TRY_X86" = "yes" ] ; then
    build_toolchain x86-4.2.1
    build_gdbserver x86-4.2.1
fi

# XXX: NOT YET NEEDED!
#
#dump "Building host ccache binary..."
#$PROGDIR/build-ccache.sh $FLAGS --build-out=$BUILD_DIR/ccache $NDK_DIR
#if [ $? != 0 ] ; then
#    dump "ERROR: Could not build host ccache binary!"
#    exit 1
#fi

if [ -n "$PACKAGE_DIR" ] ; then
    dump "Done! See $PACKAGE_DIR"
else
    dump "Done! See $NDK_DIR/toolchains"
fi
