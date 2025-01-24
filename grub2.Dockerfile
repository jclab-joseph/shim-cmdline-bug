FROM debian:sid-slim as builder

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
    bash \
    grub-efi-amd64-bin \
    systemd-boot-efi

COPY assets/grub-sbat.csv /sbat.csv
RUN mkdir -p /output && \
    grub-mkimage \
      --directory="/usr/lib/grub/x86_64-efi" \
      --output=/output/grubx64.efi \
      --format="x86_64-efi" \
      --prefix="(hd0)/boot/grub" \
      --sbat="/sbat.csv" \
      configfile msdospart part_gpt part_msdos fat iso9660 search search_fs_file search_fs_uuid probe ls linux boot normal chain peimage cat echo test file

FROM scratch
COPY --from=builder /output/grubx64.efi /grubx64.efi
