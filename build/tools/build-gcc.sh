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
#  This shell script is used to rebuild the gcc and toolchain binaries
#  for the Android NDK.
#

# include common function and variable definitions
. `dirname $0`/prebuilt-common.sh

PROGRAM_PARAMETERS="<src-dir> <ndk-dir> <toolchain>"

PROGRAM_DESCRIPTION=\
"Rebuild the gcc toolchain prebuilt binaries for the Android NDK.

Where <src-dir> is the location of toolchain sources, <ndk-dir> is
the top-level NDK installation path and <toolchain> is the name of
the toolchain to use (e.g. arm-eabi-4.4.0)."

RELEASE=`date +%Y%m%d`
BUILD_OUT=`random_temp_directory`
OPTION_BUILD_OUT=
register_var_option "--build-out=<path>" OPTION_BUILD_OUT "Set temporary build directory" "/tmp/<random>"

PLATFORM=android-3
register_var_option "--platform=<name>"  PLATFORM "Specify platform name"

OPTION_SYSROOT=
register_var_option "--sysroot=<path>"   OPTION_SYSROOT   "Specify sysroot directory directly"

GDB_VERSION=6.6
register_var_option "--gdb-version=<version>"  GDB_VERSION "Specify gdb version"

BINUTILS_VERSION=2.19
register_var_option "--binutils-version=<version>" BINUTILS_VERSION "Specify binutils version"

JOBS=$BUILD_NUM_CPUS
register_var_option "-j<number>" JOBS "Use <number> parallel build jobs"

register_mingw_option

extract_parameters $@

setup_default_log_file

set_parameters ()
{
    SRC_DIR="$1"
    NDK_DIR="$2"
    TOOLCHAIN="$3"

    # Check source directory
    #
    if [ -z "$SRC_DIR" ] ; then
        echo "ERROR: Missing source directory parameter. See --help for details."
        exit 1
    fi

    if [ ! -d "$SRC_DIR/gcc" ] ; then
        echo "ERROR: Source directory does not contain gcc sources: $SRC_DIR"
        exit 1
    fi

    log "Using source directory: $SRC_DIR"

    # Check NDK installation directory
    #
    if [ -z "$NDK_DIR" ] ; then
        echo "ERROR: Missing NDK directory parameter. See --help for details."
        exit 1
    fi

    if [ ! -d "$NDK_DIR" ] ; then
        mkdir -p $NDK_DIR
        if [ $? != 0 ] ; then
            echo "ERROR: Could not create target NDK installation path: $NDK_DIR"
            exit 1
        fi
    fi

    log "Using NDK directory: $NDK_DIR"

    # Check toolchain name
    #
    if [ -z "$TOOLCHAIN" ] ; then
        echo "ERROR: Missing toolchain name parameter. See --help for details."
        exit 1
    fi
}

set_parameters $PARAMETERS

prepare_host_flags

parse_toolchain_name

fix_option BUILD_OUT "$OPTION_BUILD_OUT" "build directory"
fix_sysroot "$OPTION_SYSROOT"

if [ ! -d $SRC_DIR/gdb/gdb-$GDB_VERSION ] ; then
    echo "ERROR: Missing gdb sources: $SRC_DIR/gdb/gdb-$GDB_VERSION"
    echo "       Use --gdb-version=<version> to specify alternative."
    exit 1
fi

fix_option BINUTILS_VERSION "$OPTION_BINUTILS_VERSION" "binutils version"
if [ ! -d $SRC_DIR/binutils/binutils-$BINUTILS_VERSION ] ; then
    echo "ERROR: Missing binutils sources: $SRC_DIR/binutils/binutils-$BINUTILS_VERSION"
    echo "       Use --binutils-version=<version> to specify alternative."
    exit 1
fi

set_toolchain_ndk $NDK_DIR

dump "Using C compiler: $CC"
dump "Using C++ compiler: $CXX"

# Location where the toolchain license files are
TOOLCHAIN_LICENSES=$ANDROID_NDK_ROOT/build/tools/toolchain-licenses

# Copy the sysroot to the installation prefix. This prevents the generated
# binaries from containing hard-coding host paths
TOOLCHAIN_SYSROOT=$TOOLCHAIN_PATH/sysroot
dump "Sysroot  : Copying: $SYSROOT --> $TOOLCHAIN_SYSROOT"
mkdir -p $TOOLCHAIN_SYSROOT && (cd $SYSROOT && tar c *) | (cd $TOOLCHAIN_SYSROOT && tar x)
if [ $? != 0 ] ; then
    echo "Error while copying sysroot files. See $TMPLOG"
    exit 1
fi

# configure the toolchain
#
dump "Configure: $TOOLCHAIN toolchain build"
# Old versions of the toolchain source packages placed the
# configure script at the top-level. Newer ones place it under
# the build directory though. Probe the file system to check
# this.
BUILD_SRCDIR=$SRC_DIR/build
if [ ! -d $BUILD_SRCDIR ] ; then
    BUILD_SRCDIR=$SRC_DIR
fi
rm -rf $BUILD_OUT
OLD_ABI="${ABI}"
export CC CXX
mkdir -p $BUILD_OUT &&
cd $BUILD_OUT &&
export CC CXX &&
export ABI=$HOST_GMP_ABI &&  # needed to build a 32-bit gmp
export CFLAGS="-Wno-error" && # needed because gdb-6.6 uses -Werror by default and fails to build with recent GCC versions
run \
$BUILD_SRCDIR/configure --target=$ABI_CONFIGURE_TARGET \
                        --host=$ABI_CONFIGURE_HOST \
                        --build=$ABI_CONFIGURE_BUILD \
                        --disable-nls \
                        --prefix=$TOOLCHAIN_PATH \
                        --with-sysroot=$TOOLCHAIN_SYSROOT \
                        --with-binutils-version=$BINUTILS_VERSION \
                        --with-gcc-version=$GCC_VERSION \
                        --with-gdb-version=$GDB_VERSION \
                        $ABI_CONFIGURE_EXTRA_FLAGS
if [ $? != 0 ] ; then
    dump "Error while trying to configure toolchain build. See $TMPLOG"
    exit 1
fi
ABI="$OLD_ABI"
# build the toolchain
dump "Building : $TOOLCHAIN toolchain [this can take a long time]."
cd $BUILD_OUT &&
export CC CXX &&
export ABI=$HOST_GMP_ABI &&
run make -j$JOBS
if [ $? != 0 ] ; then
    echo "Error while building toolchain. See $TMPLOG"
    exit 1
fi
ABI="$OLD_ABI"

# install the toolchain to its final location
dump "Install  : $TOOLCHAIN toolchain binaries."
cd $BUILD_OUT && run make install
if [ $? != 0 ] ; then
    echo "Error while installing toolchain. See $TMPLOG"
    exit 1
fi
# don't forget to copy the GPL and LGPL license files
run cp -f $TOOLCHAIN_LICENSES/COPYING $TOOLCHAIN_LICENSES/COPYING.LIB $TOOLCHAIN_PATH
# remove some unneeded files
run rm -f $TOOLCHAIN_PATH/bin/*-gccbug
run rm -rf $TOOLCHAIN_PATH/man $TOOLCHAIN_PATH/info
# strip binaries to reduce final package size
run strip $TOOLCHAIN_PATH/bin/*
run strip $TOOLCHAIN_PATH/$ABI_CONFIGURE_TARGET/bin/*
run strip $TOOLCHAIN_PATH/libexec/gcc/*/*/cc1
run strip $TOOLCHAIN_PATH/libexec/gcc/*/*/cc1plus
run strip $TOOLCHAIN_PATH/libexec/gcc/*/*/collect2

dump "Done."
if [ -n "$OPTION_BUILD_OUT" ] ; then
    rm -rf $BUILD_OUT
fi
