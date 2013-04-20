#!/usr/bin/env bash

CONSTANTS_FILE=src/main/java/org/lantern/LanternClientConstants.java
function die() {
  echo $*
  echo "Reverting version file"
  git checkout -- $CONSTANTS_FILE || die "Could not revert version file?"
  exit 1
}

if [ $# -lt "1" ]
then
    die "$0: Received $# args... version required"
fi

test -f ../secure/bns-osx-cert-developer-id-application.p12 || die "Need OSX signing certificate at ../secure/bns-osx-cert-developer-id-application.p12"
test -f ../secure/bns_cert.p12 || die "Need windows signing certificate at ../secure/bns_cert.p12"

javac -version 2>&1 | grep 1.7 && die "Cannot build with Java 7 due to bugs with generated class files and pac"

which install4jc || die "No install4jc on PATH -- ABORTING"
printenv | grep INSTALL4J_KEY || die "Must have INSTALL4J_KEY defined with the Install4J license key to use"
printenv | grep INSTALL4J_MAC_PASS || die "Must have OSX signing key password defined in INSTALL4J_MAC_PASS"
printenv | grep INSTALL4J_WIN_PASS || die "Must have windows signing key password defined in INSTALL4J_WIN_PASS"
test -f $CONSTANTS_FILE || die "No constants file at $CONSTANTS_FILE?? Exiting"

VERSION=$1
MVN_ARGS=$2
echo "*******MAVEN ARGS*******: $MVN_ARGS"
if [ $# -gt "2" ]
then
    RELEASE=$3;
else
    RELEASE=true;
fi

curBranch=`git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/'`
git pull --no-rebase origin $curBranch || die '"git pull origin" failed?'
git submodule update || die "git submodule update failed!!!"

INTERNAL_VERSION=$1-`git rev-parse HEAD | cut -c1-10`

BUILD_TIME=`date +%s`
perl -pi -e "s/build_time_tok/$BUILD_TIME/g" $CONSTANTS_FILE

# The build script in Lantern EC2 instances sets this in the environment.
if test -z $FALLBACK_SERVER_HOST; then
    FALLBACK_SERVER_HOST="75.101.134.244";
fi
perl -pi -e "s/fallback_server_host_tok/$FALLBACK_SERVER_HOST/g" $CONSTANTS_FILE || die "Could not set fallback server host"

# The build script in Lantern EC2 instances sets this in the environment.
if test -z $FALLBACK_SERVER_PORT; then
    FALLBACK_SERVER_PORT="7777";
fi
perl -pi -e "s/fallback_server_port_tok/$FALLBACK_SERVER_PORT/g" $CONSTANTS_FILE || die "Could not set fallback server port";

GE_API_KEY=`cat lantern_getexceptional.txt`
if [ ! -n "$GE_API_KEY" ]
  then
  die "No API key!!" 
fi

perl -pi -e "s/ExceptionalUtils.NO_OP_KEY/\"$GE_API_KEY\"/g" $CONSTANTS_FILE

mvn clean || die "Could not clean?"
mvn $MVN_ARGS -Prelease install -Dmaven.test.skip=true || die "Could not build?"

echo "Reverting version file"
git checkout -- $CONSTANTS_FILE || die "Could not revert version file?"

cp target/lantern*SNAPSHOT.jar install/common/lantern.jar || die "Could not copy jar?"

./bin/searchForJava7ClassFiles.bash install/common/lantern.jar || die "Found java 7 class files in build!!"
if $RELEASE ; then
    echo "Tagging...";
    git tag -f -a v$VERSION -m "Version $INTERNAL_VERSION release with MVN_ARGS $MVN_ARGS";

    echo "Pushing tags...";
    git push --tags || die "Could not push tags!!";
    echo "Finished push...";
fi

install4jc -L $INSTALL4J_KEY || die "Could not update license information?"
