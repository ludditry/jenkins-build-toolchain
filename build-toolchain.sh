#!/usr/bin/env bash

set -e
set -x

CLEAN_WORKSPACE=${CLEAN_WORKSPACE:-1}

# Build the zerovm toolchain.  This is kind of stupid.
function git_refresh() {
    # $1 - repo
    # $2 - branch
    # $3 - dest dir

    local repo=$1
    local branch=${2:-master}
    local dest=${3:-$(basename ${repo})}

    if [ -d ${dest} ]; then
        pushd ${dest}
        git checkout master
        git reset --hard
        git pull
        git checkout ${branch}
        popd
    else
        git clone ${repo} ${dest}
        pushd ${dest}
        git checkout ${branch}
        popd
    fi
}

function do_configure() {
    if [ ! -x ./configure ]; then
        if [ -x ./autogen.sh ]; then
            ./autogen.sh
        else
            autoreconf -fi
        fi
    fi

    echo "$@" > .configopts.new

    # don't run configure if we already have, prevent unnecessary rebuilds
    if [ ! -e .configopts ] || [ "$(md5sum .configopts | awk '{ print $1 }')" != "$(md5sum .configopts.new | awk '{ print $1 }')" ]; then
        ./configure "$@"
    fi

    mv .configopts.new .configopts
}

# check for necessary packages.
HAVE_PACKAGES=1
MISSING_PACKAGES=""
for package in libc6-dev-i386 libglib2.0-dev pkg-config git build-essential \
    automake autoconf libtool g++-multilib texinfo flex bison groff gperf \
    texinfo subversion; do
    if ( ! dpkg -s ${package} > /dev/null 2>&1 ); then
        echo "Missing package ${package}"
        MISSING_PACKAGES="${package} ${MISSING_PACKAGES}"
        HAVE_PACKAGES=0
    fi
done

if [ $HAVE_PACKAGES -eq 0 ]; then
    echo "try: apt-get install ${MISSING_PACKAGES}"
    exit 1
fi

if [ -e toolchain ] && [ "${CLEAN_WORKSPACE}" -eq 1 ]; then
    rm -rf toolchain
fi

mkdir -p toolchain
TOOLCHAIN_PATH=$(readlink -f toolchain)

pushd $TOOLCHAIN_PATH

git_refresh https://github.com/zerovm/zerovm devel
git_refresh https://github.com/zerovm/validator master
git_refresh https://github.com/zerovm/zrt master ${TOOLCHAIN_PATH}/zrt
git_refresh https://github.com/zerovm/toolchain master ${TOOLCHAIN_PATH}/toolchain
git_refresh https://github.com/zerovm/gcc zerovm ${TOOLCHAIN_PATH}/toolchain/SRC/gcc

for d in linux-headers-for-nacl glibc newlib binutils; do
    git_refresh https://github.com/zerovm/${d} master ${TOOLCHAIN_PATH}/toolchain/SRC/${d}
done

pushd validator
do_configure
make
popd # validator

mkdir -p ${TOOLCHAIN_PATH}/zerovm-toolchain

# here's an ugly hack for you...
mkdir -p ${TOOLCHAIN_PATH}/zerovm-toolchain/api
cp zerovm/api/zvm.h ${TOOLCHAIN_PATH}/zerovm-toolchain/api

pushd toolchain

cat > toolchain.env <<EOF
export ZVM_PREFIX=${TOOLCHAIN_PATH}/zerovm-toolchain
export ZRT_ROOT=${TOOLCHAIN_PATH}/zrt
export LD_LIBRARY_PATH=${TOOLCHAIN_PATH}/validator/native_client/src/trusted/validator/.libs
export CPATH=${TOOLCHAIN_PATH}/zerovm/api
export PATH=${ZVM_PREFIX}/bin:${PATH}
EOF

source toolchain.env

make
popd # toolchain

popd # ${TOOLCHAIN_PATH}
