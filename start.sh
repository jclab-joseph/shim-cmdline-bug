#!/bin/bash

set -ex

export TMPDIR=$PWD/.tmp
mkdir -p ${TMPDIR}

if [ ! -f ${TMPDIR}/PK.key ]; then
  openssl req -newkey rsa:2048 -nodes -keyout ${TMPDIR}/PK.key -new -x509 -sha256 -days 3650 -subj "/CN=Platform Key/" -out ${TMPDIR}/PK.crt
  openssl x509 -in ${TMPDIR}/PK.crt -out ${TMPDIR}/PK.cer -outform DER
fi

if [ ! -f ${TMPDIR}/vendor.key ]; then
  openssl req -newkey rsa:2048 -nodes -keyout ${TMPDIR}/vendor.key -new -x509 -sha256 -days 3650 -subj "/CN=SHIM Vendor Key/" -out ${TMPDIR}/vendor.crt
  openssl x509 -in ${TMPDIR}/vendor.crt -out ${TMPDIR}/vendor.der -outform DER
fi

if [ ! -f ${TMPDIR}/shim/shimx64.efi ]; then
  wget -O ${TMPDIR}/shim.tar.bz2 https://github.com/rhboot/shim/releases/download/15.8/shim-15.8.tar.bz2
  mkdir -p ${TMPDIR}/shim
  tar -C ${TMPDIR}/shim -xf ${TMPDIR}/shim.tar.bz2 --strip-component=1

  (cd ${TMPDIR}/shim && make VENDOR_CERT_FILE=${TMPDIR}/vendor.der)
fi

#if [ ! -f ${TMPDIR}/grubx64.efi ]; then
  docker build --output=type=local,dest=${TMPDIR} -f grub2.Dockerfile .
#fi

sbsign --key ${TMPDIR}/PK.key --cert ${TMPDIR}/PK.crt ${TMPDIR}/shim/shimx64.efi --output ${TMPDIR}/signed_shim.efi

cp /usr/share/OVMF/OVMF_VARS_4M.fd ${TMPDIR}/OVMF_VARS_4M.fd

cert-to-efi-sig-list -g 9997dc83-7fdb-4813-abf5-12ce53cb8385 ${TMPDIR}/PK.crt ${TMPDIR}/PK.esl
cert-to-efi-sig-list -g e780a2b5-ca56-412c-b360-d0be1a4cc8d7 ${TMPDIR}/PK.crt ${TMPDIR}/db.esl
sign-efi-sig-list -k ${TMPDIR}/PK.key -c ${TMPDIR}/PK.crt PK ${TMPDIR}/PK.esl ${TMPDIR}/PK.auth
flash-var -g D719B2CB-3D3A-4596-A3BC-DAD00E67656F ${TMPDIR}/OVMF_VARS_4M.fd "db" ${TMPDIR}/db.esl
flash-var -g 8BE4DF61-93CA-11D2-AA0D-00E098032B8C ${TMPDIR}/OVMF_VARS_4M.fd "PK" ${TMPDIR}/PK.auth

echo -n -e '\x01' > ${TMPDIR}/secure_boot_enable
#flash-var -g F0A30BC7-AF08-4556-99C4-001009C93A44 ${TMPDIR}/OVMF_VARS_4M.fd SecureBootEnable ${TMPDIR}/secure_boot_enable

KERNEL=$PWD/assets/vmlinuz \
INITRD=$PWD/assets/initrd.img \
STUB_EFI=$PWD/assets/linuxx64.efi.stub \
OUTPUT_EFI=${TMPDIR}/linux.efi \
/bin/bash ./make-linux-efi.sh

sbsign --key ${TMPDIR}/vendor.key --cert ${TMPDIR}/vendor.crt ${TMPDIR}/grubx64.efi --output ${TMPDIR}/signed_grubx64.efi
sbsign --key ${TMPDIR}/vendor.key --cert ${TMPDIR}/vendor.crt ${TMPDIR}/linux.efi --output ${TMPDIR}/linux_signed.efi

fallocate -l 256M ${TMPDIR}/efiboot.img || dd if=/dev/zero of=${TMPDIR}/efiboot.img bs=1M count=256
mkfs.vfat ${TMPDIR}/efiboot.img
mmd -i ${TMPDIR}/efiboot.img EFI EFI/BOOT boot boot/grub
mcopy -vi ${TMPDIR}/efiboot.img ${TMPDIR}/signed_shim.efi ::EFI/BOOT/BOOTX64.EFI
mcopy -vi ${TMPDIR}/efiboot.img ${TMPDIR}/signed_grubx64.efi ::EFI/BOOT/grubx64.efi
mcopy -vi ${TMPDIR}/efiboot.img $PWD/grub.cfg ::boot/grub/grub.cfg
mcopy -vi ${TMPDIR}/efiboot.img ${TMPDIR}/linux_signed.efi ::linux.efi

qemu-system-x86_64 \
  -machine q35,smm=on,accel=kvm -cpu kvm64 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.ms.fd \
  -drive if=pflash,format=raw,file=${TMPDIR}/OVMF_VARS_4M.fd \
  -global kvm-pit.lost_tick_policy=delay \
  -global ICH9-LPC.disable_s3=1 \
  -global ICH9-LPC.disable_s4=1 \
  -device intel-iommu,intremap=off \
  -smp 2 -m 1024m \
  -rtc clock=rt,base=utc \
  -device ahci,id=ahci \
  -device virtio-scsi-pci,id=scsi \
  -drive file=${TMPDIR}/efiboot.img,format=raw,if=none,id=bootdisk \
  -device ide-hd,bus=ahci.0,drive=bootdisk,bootindex=1 \
  -D /dev/stderr \
  -global driver=cfi.pflash01,property=secure,value=on
