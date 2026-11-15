kind=bin
repo=kubernetes-sigs/cluster-api
tag=v
asset=clusterctl-linux-amd64
archive=binary
version_args='version -o short'
version_env=CLUSTERCTL_DISABLE_VERSIONCHECK=true
version_match='v{version}*'
license=apache-2.0
