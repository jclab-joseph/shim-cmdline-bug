# ISSUE

cmdline: [grub.cfg](./grub.cfg)

```bash
search --file --set boot_root /linux.efi
echo "boot_root: ${boot_root}"
ls (${boot_root})/
if chainloader (${boot_root})/linux.efi console=tty1 rdinit=/bin/sh hello=world; then
  boot
else
  echo "FAILED"
fi
```

## SECURE BOOT ON

![img2](./docs/vm_secure_boot_on.png)

=> NO /proc/cmdline !!!

## SECURE BOOT OFF

![img2](./docs/vm_secure_boot_off.png)

=> GOOD /proc/cmdline !!!
