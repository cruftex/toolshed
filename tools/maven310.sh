kind=opt
repo=apache/maven
tag=maven-
url='https://archive.apache.org/dist/maven/maven-3/{version}/binaries/apache-maven-{version}-bin.tar.gz'
root='apache-maven-{version}'
table=maven
version_prefix=3.10.
links='bin/mvn bin/mvn=mvn310'
executable=mvn310
license=apache-2.0

tool_validate() {
    maven_is_installed "$1" "$2"
}

tool_latest() {
    maven_latest 3.10 "$1"
}
