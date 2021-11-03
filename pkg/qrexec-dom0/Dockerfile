FROM lfedge/eve-xen-tools:1384d61043b17b11a179a2a7fa42f87ebe977ba7 as xentools
FROM lfedge/eve-qrexec-lib:4cff59cd356f162dc407313a0190362de6f690c7 as qrexec_lib
FROM lfedge/eve-alpine:6.7.0 as build
ENV BUILD_PKGS gcc make libc-dev linux-headers git pkgconf
RUN eve-alpine-deploy.sh

COPY --from=xentools / /
COPY --from=qrexec_lib / /

RUN git clone https://github.com/QubesOS/qubes-core-qrexec qubes-core-qrexec

RUN mkdir -p /out/usr/bin

WORKDIR /qubes-core-qrexec/daemon

RUN sed -i. -e 's#-Wall##' -e 's#-Wextra##' -e 's#-Werror##'  `find . -name Makefile`
RUN make BACKEND_VMM=xen
RUN cp qrexec-daemon qrexec-client /out/usr/bin

FROM scratch
ENTRYPOINT []
CMD []
COPY --from=build /out /
