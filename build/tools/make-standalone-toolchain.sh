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

# Create a standalone toolchain package for Android.

. `dirname $0`/prebuilt-common.sh

PROGRAM_PARAMETERS=""
PROGRAM_DESCRIPTION=\
"Generate a customized Android toolchain installation that includes
a working sysroot. The result is something that can more easily be
used as a standalone cross-compiler, e.g. to run configure and
make scripts."

# $1: Source directory
# $2: Destination directory
copy_directory () {
    if [ ! -d "$1" ] ; then
        dump "Error: Trying to copy from non-existing directory: $1"
        exit 1
    fi
    mkdir -p "$2"
    if [ $? != 0 ] ; then
        dump "Error: Could not create target directory: $2"
        exit 1
    fi
    (cd "$1" && tar cf - *) | (tar xpf - -C "$2")
    if [ $? != 0 ] ; then
        dump "Error: Could not copy files from '$1' to '$2'"
        exit 1
    fi
}

force_32bit_binaries

# For now, this is the only toolchain that works reliably.
TOOLCHAIN_NAME=arm-linux-androideabi-4.4.3
register_var_option "--toolchain=<name>" TOOLCHAIN_NAME "Specify toolchain name"

NDK_DIR=`dirname $0`
NDK_DIR=`dirname $NDK_DIR`
NDK_DIR=`dirname $NDK_DIR`
register_var_option "--ndk-dir=<path>" NDK_DIR "Take source files from NDK at <path>"

SYSTEM=$HOST_TAG
register_var_option "--system=<name>" SYSTEM "Specify host system"

PACKAGE_DIR=/tmp/ndk
register_var_option "--package-dir=<path>" PACKAGE_DIR "Place package file in <path>"

INSTALL_DIR=
register_var_option "--install-dir=<path>" INSTALL_DIR "Don't create package, install files to <path> instead."

PLATFORM=android-3
register_var_option "--platform=<name>" PLATFORM "Specify target Android platform/API level."

extract_parameters "$@"

# Check NDK_DIR
if [ ! -d "$NDK_DIR/build/core" ] ; then
    echo "Invalid source NDK directory: $NDK_DIR"
    echo "Please use --ndk-dir=<path> to specify the path of an installed NDK."
    exit 1
fi

# Check PLATFORM
if [ ! -d "$NDK_DIR/platforms/$PLATFORM" ] ; then
    echo "Invalid platform name: $PLATFORM"
    echo "Please use --platform=<name> with one of:" `(cd "$NDK_DIR/platforms" && ls)`
    exit 1
fi

# Check toolchain name
TOOLCHAIN_PATH="$NDK_DIR/toolchains/$TOOLCHAIN_NAME"
if [ ! -d "$TOOLCHAIN_PATH" ] ; then
    echo "Invalid toolchain name: $TOOLCHAIN_NAME"
    echo "Please use --toolchain=<name> with the name of a toolchain supported by the source NDK."
    echo "Try one of: " `(cd "$NDK_DIR/toolchains" && ls)`
    exit 1
fi

# Extract architecture from platform name
case "$TOOLCHAIN_NAME" in
    arm-*)
        ARCH=arm
        ;;
    x86-*)
        ARCH=x86
        ;;
    *)
        echo "Unsupported toolchain name: $TOOLCHAIN_NAME"
        echo "Name must start with arm- or x86- !"
        exit 1
        ;;
esac

# Check that there are any platform files for it!
(cd $NDK_DIR/platforms && ls -d */arch-${ARCH} >/dev/null 2>&1 )
if [ $? != 0 ] ; then
    echo "Platform $PLATFORM doesn't have any files for this architecture: $ARCH"
    echo "Either use --platform=<name> or --toolchain=<name> to select a different"
    echo "platform or arch-dependent toolchain name (respectively)!"
    exit 1
fi

# Compute source sysroot
SRC_SYSROOT="$NDK_DIR/platforms/$PLATFORM/arch-$ARCH"
if [ ! -d "$SRC_SYSROOT" ] ; then
    echo "No platform files ($PLATFORM) for this architecture: $ARCH"
    exit 1
fi

# Check that we have any prebuilts here
if [ ! -d "$TOOLCHAIN_PATH/prebuilt" ] ; then
    echo "Toolchain is missing prebuilt files: $TOOLCHAIN_NAME"
    echo "You must point to a valid NDK release package!"
    exit 1
fi

if [ ! -d "$TOOLCHAIN_PATH/prebuilt/$SYSTEM" ] ; then
    echo "Host system '$SYSTEM' is not supported by the source NDK!"
    echo "Try --system=<name> with one of: " `(cd $TOOLCHAIN_PATH/prebuilt && ls) | grep -v gdbserver`
    exit 1
fi

TOOLCHAIN_PATH="$TOOLCHAIN_PATH/prebuilt/$SYSTEM"

# Create temporary directory
TMPDIR=`random_temp_directory`/$TOOLCHAIN_NAME

dump "Copying prebuilt binaries..."
# Now copy the toolchain prebuilt binaries
run copy_directory "$TOOLCHAIN_PATH" "$TMPDIR"

dump "Copying sysroot headers and libraries..."
# Copy the sysroot under $TMPDIR/sysroot. The toolchain was built to
# expect the sysroot files to be placed there!
run copy_directory "$SRC_SYSROOT" "$TMPDIR/sysroot"

# Install or Package
if [ -n "$INSTALL_DIR" ] ; then
    dump "Copying files to: $INSTALL_DIR"
    run copy_directory "$TMPDIR" "$INSTALL_DIR"
else
    PACKAGE_FILE="$PACKAGE_DIR/$TOOLCHAIN_NAME.tar.bz2"
    dump "Creating package file: $PACKAGE_FILE"
    (cd "`dirname $TMPDIR`" && run tar cjf "$PACKAGE_FILE" "$TOOLCHAIN_NAME")
    if [ $? != 0 ] ; then
        dump "Error: Could not create tarball from $TMPDIR"
        exit 1
    fi
fi
dump "Cleaning up..."
run rm -rf $TMPDIR

dump "Done."
