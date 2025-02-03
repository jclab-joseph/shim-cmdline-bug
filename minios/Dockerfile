FROM alpine:3.20 as rootfs
COPY init /init
RUN chmod +x /init

FROM alpine:3.20 as builder
COPY --from=rootfs / /rootfs
RUN cd /rootfs && \
    find . -print0 | cpio --null -ov --format=newc > /initrd.img

FROM scratch
COPY --from=builder /initrd.img /
