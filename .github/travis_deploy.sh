#! /bin/bash
## vim:set ts=4 sw=4 et:
set -e; set -o pipefail

# Support for Travis CI -- https://travis-ci.org/upx/upx/builds
# Copyright (C) Markus Franz Xaver Johannes Oberhumer

if [[ $TRAVIS_OS_NAME == osx ]]; then
argv0=$0; argv0abs=$(greadlink -en -- "$0"); argv0dir=$(dirname "$argv0abs")
else
argv0=$0; argv0abs=$(readlink -en -- "$0"); argv0dir=$(dirname "$argv0abs")
fi
source "$argv0dir/travis_init.sh" || exit 1

set -x # debug

if [[ $BM_X == rebuild-stubs ]]; then exit 0; fi
# save space
if [[ $BM_B =~ (^|\+)coverage($|\+) ]]; then exit 0; fi
if [[ $BM_B =~ (^|\+)debug($|\+) ]]; then exit 0; fi
if [[ $BM_B =~ (^|\+)sanitize($|\+) ]]; then exit 0; fi
if [[ $BM_B =~ (^|\+)scan-build($|\+) ]]; then exit 0; fi
if [[ $BM_B =~ (^|\+)valgrind($|\+) ]]; then exit 0; fi

if [[ -n $APPVEYOR_JOB_ID ]]; then
    TRAVIS_BRANCH=$APPVEYOR_REPO_BRANCH
    if [[ -n $APPVEYOR_PULL_REQUEST_NUMBER ]]; then exit 0; fi
else
    if [[ "$TRAVIS_PULL_REQUEST" != "false" ]]; then exit 0; fi
fi
if [[ "$TRAVIS_BRANCH" != "devel" ]]; then
    exit 0
fi

# get $rev and $branch
cd / && cd $upx_SRCDIR || exit 1
rev=$(git rev-parse --verify HEAD)
timestamp=$(git log -n1 --format='%at' HEAD)
date=$(TZ=UTC0 date -d "@$timestamp" '+%Y%m%d-%H%M%S')
branch="$TRAVIS_BRANCH-$date-${rev:0:6}"
if [[ -n $APPVEYOR_JOB_ID ]]; then
    branch="$branch-appveyor"
else
    branch="$branch-travis"
fi
unset timestamp date

# /***********************************************************************
# // prepare directory $d
# ************************************************************************/

cd / && cd $upx_BUILDDIR || exit 1

mkdir deploy || exit 1
cd deploy || exit 1

if [[ -n $BM_CROSS ]]; then
    d=$BM_CROSS
else
    cpu=unknown
    case $BM_C in
        clang*-m32 | gcc*-m32) cpu=i386;;
        clang*-m64 | gcc*-m64) cpu=amd64;;
        msvc*-x86) cpu=i386;;
        msvc*-x64) cpu=amd64;;
    esac
    os=$TRAVIS_OS_NAME
    if [[ $os == osx ]]; then
        os=darwin
    elif [[ $os == windows ]]; then
        [[ $cpu == i386 ]] && os=win32
        [[ $cpu == amd64 ]] && os=win64
    fi
    d=$cpu-$os
fi
d=$d-$BM_C-$BM_B

mkdir $d || exit 1
for exeext in .exe .out; do
    f=$upx_BUILDDIR/upx$exeext
    if [[ -f $f ]]; then
        cp -p -i $f $d/upx-${rev:0:12}$exeext
        sha256sum -b $d/upx-${rev:0:12}$exeext
    fi
done

# /***********************************************************************
# // clone, add files & push
# ************************************************************************/

new_branch=0
if ! git clone -b $branch --single-branch https://github.com/upx/upx-automatic-builds.git; then
    git  clone -b master  --single-branch https://github.com/upx/upx-automatic-builds.git
    new_branch=1
fi
cd upx-automatic-builds || exit 1
if [[ -n $APPVEYOR_JOB_ID ]]; then git config user.name "AppVeyor CI"
else git config user.name "Travis CI"
fi
git config user.email "none@none"
if [[ $new_branch == 1 ]]; then
    git checkout --orphan $branch
    git reset --hard
fi

mv ../$d .
git add $d

if git diff --cached --exit-code --quiet >/dev/null; then
    # nothing to do
    exit 0
fi

now=$(date '+%s')
##date=$(TZ=UTC0 date -d "@$now" '+%Y-%m-%d %H:%M:%S')
git commit --date="$now" -m "Automatic build $d"
git ls-files
#git log --pretty=fuller

repo=$(git config remote.origin.url)
ssh_repo=${repo/https:\/\/github.com\//git@github.com:}
eval $(ssh-agent -s)
set +x # IMPORTANT
openssl aes-256-cbc -d -a -K "$UPX_AUTOMATIC_BUILDS_SSL_KEY" -iv "$UPX_AUTOMATIC_BUILDS_SSL_IV" -in "$upx_SRCDIR/.github/upx-automatic-builds@github.com.enc" -out .git/deploy.key
set -x
chmod 600 .git/deploy.key
ssh-add .git/deploy.key

let i=0 || true
while [[ $i -lt 10 ]]; do
    if [[ $new_branch == 1 ]]; then
        if git push -u $ssh_repo $branch; then break; fi
    else
        if git push    $ssh_repo $branch; then break; fi
    fi
    git fetch origin $branch
    new_branch=0
    git rebase origin/$branch $branch
    sleep $((RANDOM % 5 + 1))
    let i=i+1
done

exit 0
