include settings.mk

.PHONY: all toolchain system kernel image clean

help:
	@$(SCRIPTS_DIR)/help.sh

all:
	@make clean toolchain system kernel image

toolchain:
	@$(SCRIPTS_DIR)/toolchain.sh

system:
	@$(SCRIPTS_DIR)/system.sh

kernel:
	@$(SCRIPTS_DIR)/kernel.sh

image:
	@$(SCRIPTS_DIR)/image.sh

run:
	@qemu-system-x86_64 -m 512M -kernel $(KERNEL_DIR)/bzImage -initrd $(IMAGES_DIR)/rootfs.cpio.gz # -nographic -append "console=ttyS0"

clean:
	@rm -rf out

download:
	@wget -c -i wget-list -P $(SOURCES_DIR)
