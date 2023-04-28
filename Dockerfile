## Base Image
# https://github.com/wojiushixiaobai/docker-loongnix-artifacts/tree/master/debian/buster-slim
# https://github.com/wojiushixiaobai/docker-library-loong64/blob/master/golang/1.19/slim-buster/Dockerfile

FROM golang:1.19-buster AS builder

ARG RUNC_VERSION=v1.1.5 \
    CONTAINERD_VERSION=v1.6.20 \
    DOCKER_VERSION=v23.0.5 \
    TINI_VERSION=v0.19.0

ENV GOPROXY=https://goproxy.io,direct \
    GOSUMDB=off \
    GO111MODULE=auto \
    GOOS=linux

RUN set -ex; \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
    apt-get update; \
    apt-get install -y wget g++ cmake make pkg-config git libseccomp-dev libbtrfs-dev libseccomp-dev libbtrfs-dev libdevmapper-dev; \
    rm -rf /var/lib/apt/lists/*

RUN set -ex; \
    mkdir -p /tmp/go; \
    cd /tmp/go; \
    go mod init test; \
    go mod tidy; \
    go get -u github.com/creack/pty\@v1.1.18

WORKDIR /go/src/github.com/opencontainers
RUN set -ex; \
    git clone -b ${RUNC_VERSION} https://github.com/opencontainers/runc --depth=1

WORKDIR /go/src/github.com/opencontainers/runc
RUN cp -rf /usr/local/go/src/cmd/vendor/golang.org/x/sys/unix vendor/golang.org/x/sys/; \
    sed -i 's@|| s390x@|| s390x || loong64@g' libcontainer/system/syscall_linux_64.go; \
    sed -i 's@riscv64 s390x@riscv64 s390x loong64@g' libcontainer/system/syscall_linux_64.go; \
    sed -i 's@--dirty @@g' Makefile; \
    make static; \
    ./runc -v

WORKDIR /go/src/github.com/containerd
RUN set -ex; \
    git clone -b ${CONTAINERD_VERSION} https://github.com/containerd/containerd --depth=1

WORKDIR /go/src/github.com/containerd/containerd
RUN wget -O vendor/go.etcd.io/bbolt/bolt_loong64.go https://github.com/etcd-io/bbolt/raw/master/bolt_loong64.go; \
    sed -i "s@--dirty='.m' @@g" Makefile; \
    sed -i 's@$(shell if ! git diff --no-ext-diff --quiet --exit-code; then echo .m; fi)@@g' Makefile; \
    make STATIC=True; \
    ./bin/containerd -v; \
    ./bin/ctr -v

WORKDIR /go/src/github.com/docker
RUN set -ex; \
    git clone -b ${DOCKER_VERSION} https://github.com/docker/cli --depth=1

WORKDIR /go/src/github.com/docker/cli
RUN make; \
    ./build/docker -v

WORKDIR /go/src/github.com/docker
RUN set -ex; \
    git clone -b ${DOCKER_VERSION} https://github.com/moby/moby docker --depth=1

WORKDIR /go/src/github.com/docker/docker
RUN mkdir bin; \
    rm -rf vendor/github.com/creack/pty; \
    cp -rf /go/pkg/mod/github.com/creack/pty\@v1.1.18 vendor/github.com/creack/pty; \
    sed -i 's@GITCOMMIT-unsupported@GITCOMMIT@g' hack/make.sh; \
    VERSION=${DOCKER_VERSION#*v} ./hack/make.sh; \
    ./bundles/binary-daemon/dockerd -v; \
    cp -rf bundles/binary-daemon bin/; \
    VERSION=${DOCKER_VERSION#*v} ./hack/make.sh binary-proxy; \
    ./bundles/binary-proxy/docker-proxy --version; \
    cp -rf bundles/binary-proxy bin/

WORKDIR /go/src/github.com/docker
RUN set -ex; \
    git clone -b ${TINI_VERSION} https://github.com/krallin/tini --depth=1

WORKDIR /go/src/github.com/docker/tini
RUN cmake .; \
    make tini-static; \
    ./tini-static --version

WORKDIR /opt/docker
RUN set -ex; \
    cp /go/src/github.com/opencontainers/runc/runc /opt/docker/; \
    cp /go/src/github.com/containerd/containerd/bin/containerd /opt/docker/; \
    cp /go/src/github.com/containerd/containerd/bin/containerd-shim-runc-v2 /opt/docker/; \
    cp /go/src/github.com/containerd/containerd/bin/ctr /opt/docker/; \
    cp /go/src/github.com/docker/cli/build/docker /opt/docker/; \
    cp /go/src/github.com/docker/docker/bin/binary-daemon/dockerd /opt/docker/; \
    cp /go/src/github.com/docker/docker/bin/binary-proxy/docker-proxy /opt/docker/; \
    cp /go/src/github.com/docker/tini/tini-static /opt/docker/docker-init

WORKDIR /opt
RUN set -ex; \
    chmod +x docker/*; \
    tar -czf docker-${DOCKER_VERSION#*v}.tgz docker; \
    echo $(md5sum docker-${DOCKER_VERSION#*v}.tgz) > docker-${DOCKER_VERSION#*v}.tgz.md5; \
    rm -rf docker

FROM debian:buster-slim
ARG DOCKER_VERSION=v23.0.4

COPY --from=builder /opt /opt
WORKDIR /opt

RUN set -ex; \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
    cat docker-${DOCKER_VERSION#*v}.tgz.md5

VOLUME /dist

CMD cp -f docker-* /dist/