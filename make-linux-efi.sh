#!/bin/bash -p

set -e

dinfo() {
  echo "$@" > /dev/stderr
}

# Check if file is in PE format
pe_file_format() {
    if [[ $# -eq 1 ]]; then
        local magic
        magic=$(objdump -p "$1" \
            | gawk '{if ($1 == "Magic"){print strtonum("0x"$2)}}')
        magic=$(printf "0x%x" "$magic")
        # 0x10b (PE32), 0x20b (PE32+)
        [[ $magic == 0x20b || $magic == 0x10b ]] && return 0
    fi
    return 1
}

# Get specific data from the PE header
pe_get_header_data() {
    local data_header
    [[ $# -ne "2" ]] && return 1
    [[ $(pe_file_format "$1") -eq 1 ]] && return 1
    data_header=$(objdump -p "$1" \
        | awk -v data="$2" '{if ($1 == data){print $2}}')
    echo "$data_header"
}

# Get the SectionAlignment data from the PE header
pe_get_section_align() {
    local align_hex
    [[ $# -ne "1" ]] && return 1
    align_hex=$(pe_get_header_data "$1" "SectionAlignment")
    [[ $? -eq 1 ]] && return 1
    echo "$((16#$align_hex))"
}

# Get the ImageBase data from the PE header
pe_get_image_base() {
    local base_image
    [[ $# -ne "1" ]] && return 1
    base_image=$(pe_get_header_data "$1" "ImageBase")
    [[ $? -eq 1 ]] && return 1
    echo "$((16#$base_image))"
}

uefi_outdir="${TMPDIR}/"
mkdir -p "${uefi_outdir}"

uefi_stub="${STUB_EFI}"
uefi_osrelease=""
uefi_splash_image=""
kernel_image="${KERNEL}"
kernel_cmdline="console=tty1 console=ttyS0,115200 libata.allow_tpm=1"

offs=$(objdump -h "$uefi_stub" 2> /dev/null | awk 'NF==7 {size=strtonum("0x"$3);\
            offset=strtonum("0x"$4)} END {print size + offset}')
if [[ $offs -eq 0 ]]; then
    dfatal "Failed to get the size of $uefi_stub to create UEFI image file"
    exit 1
fi
align=$(pe_get_section_align "$uefi_stub")
if [[ $? -eq 1 ]]; then
    dfatal "Failed to get the sectionAlignment of the stub PE header to create the UEFI image file"
    exit 1
fi
offs=$((offs + "$align" - offs % "$align"))
[[ -n "$uefi_osrelease" ]] \
    && uefi_osrelease_offs=${offs} \
    && offs=$((offs + $(stat -Lc%s "$uefi_osrelease"))) \
    && offs=$((offs + "$align" - offs % "$align"))

echo -ne "\x00" >> "$uefi_outdir/cmdline.txt"
dinfo "Using UEFI kernel cmdline:"
dinfo "$(tr -d '\000' < "$uefi_outdir/cmdline.txt")"
uefi_cmdline="${uefi_outdir}/cmdline.txt"
uefi_cmdline_offs=${offs}
offs=$((offs + $(stat -Lc%s "$uefi_cmdline")))
offs=$((offs + "$align" - offs % "$align"))

if [[ -n "${uefi_splash_image}" ]]; then
    uefi_splash_offs=${offs}
    offs=$((offs + $(stat -Lc%s "$uefi_splash_image")))
    offs=$((offs + "$align" - offs % "$align"))
fi

uefi_linux_offs="${offs}"
offs=$((offs + $(stat -Lc%s "$kernel_image")))
offs=$((offs + "$align" - offs % "$align"))
uefi_initrd_offs="${offs}"

set -x

objcopy \
    ${uefi_osrelease:+--add-section .osrel="$uefi_osrelease" --change-section-vma .osrel=$(printf 0x%x "$uefi_osrelease_offs")} \
    ${uefi_cmdline:+--add-section .cmdline="$uefi_cmdline" --change-section-vma .cmdline=$(printf 0x%x "$uefi_cmdline_offs")} \
    ${uefi_splash_image:+--add-section .splash="$uefi_splash_image" --change-section-vma .splash=$(printf 0x%x "$uefi_splash_offs")} \
    --add-section .linux="${KERNEL}" --change-section-vma .linux="$(printf 0x%x "$uefi_linux_offs")" \
    --add-section .initrd="${INITRD}" --change-section-vma .initrd="$(printf 0x%x "$uefi_initrd_offs")" \
    "${uefi_stub}" "${OUTPUT_EFI}"
