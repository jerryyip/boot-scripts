#!/bin/bash -e
#
# Copyright (c) 2013-2016 Robert Nelson <robertcnelson@gmail.com>
# Portions copyright (c) 2014 Charles Steinkuehler <charles@steinkuehler.net>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

source $(dirname "$0")/functions.sh

#This script assumes, these packages are installed, as network may not be setup
#dosfstools initramfs-tools rsync u-boot-tools

version_message="1.20161013: oemflasher improvements..."

check_if_run_as_root

find_root_drive

mount -t tmpfs tmpfs /tmp

destination="/dev/mmcblk1"
usb_drive="/dev/sda"

write_failure () {
	message="writing to [${destination}] failed..." ; broadcast

	if [ "x${is_bbb}" = "xenable" ] ; then
		[ -e /proc/$CYLON_PID ]  && kill $CYLON_PID > /dev/null 2>&1

		if [ -e /sys/class/leds/beaglebone\:green\:usr0/trigger ] ; then
			echo heartbeat > /sys/class/leds/beaglebone\:green\:usr0/trigger
			echo heartbeat > /sys/class/leds/beaglebone\:green\:usr1/trigger
			echo heartbeat > /sys/class/leds/beaglebone\:green\:usr2/trigger
			echo heartbeat > /sys/class/leds/beaglebone\:green\:usr3/trigger
		fi
	fi
	message="-----------------------------" ; broadcast
	flush_cache
	inf_loop
}

print_eeprom () {
	unset got_eeprom
	#v8 of nvmem...
	if [ -f /sys/bus/nvmem/devices/at24-0/nvmem ] && [ "x${got_eeprom}" = "x" ] ; then
		eeprom="/sys/bus/nvmem/devices/at24-0/nvmem"
		eeprom_location="/sys/devices/platform/ocp/44e0b000.i2c/i2c-0/0-0050/at24-0/nvmem"
		got_eeprom="true"
	fi

	#pre-v8 of nvmem...
	if [ -f /sys/class/nvmem/at24-0/nvmem ] && [ "x${got_eeprom}" = "x" ] ; then
		eeprom="/sys/class/nvmem/at24-0/nvmem"
		eeprom_location="/sys/devices/platform/ocp/44e0b000.i2c/i2c-0/0-0050/nvmem/at24-0/nvmem"
		got_eeprom="true"
	fi

	#eeprom 3.8.x & 4.4 with eeprom-nvmem patchset...
	if [ -f /sys/bus/i2c/devices/0-0050/eeprom ] && [ "x${got_eeprom}" = "x" ] ; then
		eeprom="/sys/bus/i2c/devices/0-0050/eeprom"

		if [ -f /sys/devices/platform/ocp/44e0b000.i2c/i2c-0/0-0050/eeprom ] ; then
			eeprom_location="/sys/devices/platform/ocp/44e0b000.i2c/i2c-0/0-0050/eeprom"
		else
			eeprom_location=$(ls /sys/devices/ocp*/44e0b000.i2c/i2c-0/0-0050/eeprom 2> /dev/null)
		fi

		got_eeprom="true"
	fi

	if [ "x${got_eeprom}" = "xtrue" ] ; then
		eeprom_header=$(hexdump -e '8/1 "%c"' ${eeprom} -n 28 | cut -b 5-28)
		message="EEPROM: [${eeprom_header}]" ; broadcast
		message="-----------------------------" ; broadcast
	fi
}

flash_emmc () {
	message="eMMC: prepareing ${destination}" ; broadcast
	flush_cache
	dd if=/dev/zero of=${destination} bs=1M count=108
	sync
	dd if=${destination} of=/dev/null bs=1M count=108
	sync
	flush_cache

	LC_ALL=C sfdisk --force --no-reread --in-order --Linux --unit M ${destination} <<-__EOF__
	4,,L,*
	__EOF__

	sync
	flush_cache

	message="mkfs.ext4 -L rootfs ${destination}p1" ; broadcast
	LC_ALL=C mkfs.ext4 -L rootfs ${destination}p1 || write_failure
	message="Erasing: ${destination} complete" ; broadcast
	message="-----------------------------" ; broadcast

	if [ ! "x${conf_bmap}" = "x" ] ; then
		if [ -f /usr/bin/bmaptool ] && [ -f ${wdir}/${conf_bmap} ] ; then
			message="Flashing eMMC with bmaptool" ; broadcast
			message="-----------------------------" ; broadcast
			message="bmaptool copy --bmap ${wdir}/${conf_bmap} ${wdir}/${conf_image} ${destination}" ; broadcast
			/usr/bin/bmaptool copy --bmap ${wdir}/${conf_bmap} ${wdir}/${conf_image} ${destination} || write_failure
			message="-----------------------------" ; broadcast
		else
			message="Flashing eMMC with dd" ; broadcast
			message="-----------------------------" ; broadcast
			if [ "x${image_is_uncompressed}" = "xenable" ] ; then
				message="dd if=${wdir}/${conf_image} of=${destination} bs=1M" ; broadcast
				dd if=${wdir}/${conf_image} of=${destination} bs=1M || write_failure
			else
				message="xzcat ${wdir}/${conf_image} | dd of=${destination} bs=1M" ; broadcast
				xzcat ${wdir}/${conf_image} | dd of=${destination} bs=1M || write_failure
			fi
			message="-----------------------------" ; broadcast
		fi
	else
		message="Flashing eMMC with dd" ; broadcast
		message="-----------------------------" ; broadcast
			if [ "x${image_is_uncompressed}" = "xenable" ] ; then
				message="dd if=${wdir}/${conf_image} of=${destination} bs=1M" ; broadcast
				dd if=${wdir}/${conf_image} of=${destination} bs=1M || write_failure
			else
				message="xzcat ${wdir}/${conf_image} | dd of=${destination} bs=1M" ; broadcast
				xzcat ${wdir}/${conf_image} | dd of=${destination} bs=1M || write_failure
			fi
		message="-----------------------------" ; broadcast
	fi
	flush_cache
}

etc_mtab_symlink () {
	message="-----------------------------" ; broadcast
	message="Setting up: ln -s /proc/mounts /etc/mtab" ; broadcast
	mount -o rw,remount / || write_failure
	if [ -f /etc/mtab ] ; then
		rm -f /etc/mtab || write_failure
	fi
	ln -s /proc/mounts /etc/mtab || write_failure
	mount -o ro,remount / || write_failure
	message="-----------------------------" ; broadcast
}

auto_fsck () {
	etc_mtab_symlink
	message="-----------------------------" ; broadcast
	if [ "x${conf_partition1_fstype}" = "x0x83" ] ; then
		message="e2fsck -fy ${destination}p1" ; broadcast
		e2fsck -fy ${destination}p1 || write_failure
		message="-----------------------------" ; broadcast
	fi
	if [ "x${conf_partition2_fstype}" = "x0x83" ] ; then
		message="e2fsck -fy ${destination}p2" ; broadcast
		e2fsck -fy ${destination}p2 || write_failure
		message="-----------------------------" ; broadcast
	fi
	if [ "x${conf_partition3_fstype}" = "x0x83" ] ; then
		message="e2fsck -fy ${destination}p3" ; broadcast
		e2fsck -fy ${destination}p3 || write_failure
		message="-----------------------------" ; broadcast
	fi
	if [ "x${conf_partition4_fstype}" = "x0x83" ] ; then
		message="e2fsck -fy ${destination}p4" ; broadcast
		e2fsck -fy ${destination}p4 || write_failure
		message="-----------------------------" ; broadcast
	fi
	flush_cache
}

quad_partition () {
	conf_partition2_startmb=$(($conf_partition1_startmb + $conf_partition1_endmb))
	conf_partition3_startmb=$(($conf_partition2_startmb + $conf_partition2_endmb))
	conf_partition4_startmb=$(($conf_partition3_startmb + $conf_partition3_endmb))
	message="LC_ALL=C sfdisk --force --no-reread --in-order --Linux --unit M ${destination}" ; broadcast
	message="${conf_partition1_startmb},${conf_partition1_endmb},${conf_partition1_fstype},*" ; broadcast
	message="${conf_partition2_startmb},${conf_partition2_endmb},${conf_partition2_fstype},-" ; broadcast
	message="${conf_partition3_startmb},${conf_partition3_endmb},${conf_partition3_fstype},-" ; broadcast
	message="${conf_partition4_startmb},,${conf_partition4_fstype},-" ; broadcast
	message="-----------------------------" ; broadcast

	LC_ALL=C sfdisk --force --no-reread --in-order --Linux --unit M ${destination} <<-__EOF__
		${conf_partition1_startmb},${conf_partition1_endmb},${conf_partition1_fstype},*
		${conf_partition2_startmb},${conf_partition2_endmb},${conf_partition2_fstype},-
		${conf_partition3_startmb},${conf_partition3_endmb},${conf_partition3_fstype},-
		${conf_partition4_startmb},,${conf_partition4_fstype},-
	__EOF__

	auto_fsck
	message="resize2fs -f ${destination}p4" ; broadcast
	resize2fs -f ${destination}p4 || write_failure
	message="-----------------------------" ; broadcast
}

tri_partition () {
	conf_partition2_startmb=$(($conf_partition1_startmb + $conf_partition1_endmb))
	conf_partition3_startmb=$(($conf_partition2_startmb + $conf_partition2_endmb))
	message="LC_ALL=C sfdisk --force --no-reread --in-order --Linux --unit M ${destination}" ; broadcast
	message="${conf_partition1_startmb},${conf_partition1_endmb},${conf_partition1_fstype},*" ; broadcast
	message="${conf_partition2_startmb},${conf_partition2_endmb},${conf_partition2_fstype},-" ; broadcast
	message="${conf_partition3_startmb},,${conf_partition3_fstype},-" ; broadcast
	message="-----------------------------" ; broadcast

	LC_ALL=C sfdisk --force --no-reread --in-order --Linux --unit M ${destination} <<-__EOF__
		${conf_partition1_startmb},${conf_partition1_endmb},${conf_partition1_fstype},*
		${conf_partition2_startmb},${conf_partition2_endmb},${conf_partition2_fstype},-
		${conf_partition3_startmb},,${conf_partition3_fstype},-
	__EOF__

	auto_fsck
	message="resize2fs -f ${destination}p3" ; broadcast
	resize2fs -f ${destination}p3 || write_failure
	message="-----------------------------" ; broadcast
}

dual_partition () {
	conf_partition2_startmb=$(($conf_partition1_startmb + $conf_partition1_endmb))
	message="LC_ALL=C sfdisk --force --no-reread --in-order --Linux --unit M ${destination}" ; broadcast
	message="${conf_partition1_startmb},${conf_partition1_endmb},${conf_partition1_fstype},*" ; broadcast
	message="${conf_partition2_startmb},,${conf_partition2_fstype},-" ; broadcast
	message="-----------------------------" ; broadcast

	LC_ALL=C sfdisk --force --no-reread --in-order --Linux --unit M ${destination} <<-__EOF__
		${conf_partition1_startmb},${conf_partition1_endmb},${conf_partition1_fstype},*
		${conf_partition2_startmb},,${conf_partition2_fstype},-
	__EOF__

	auto_fsck
	message="resize2fs -f ${destination}p2" ; broadcast
	resize2fs -f ${destination}p2 || write_failure
	message="-----------------------------" ; broadcast
}

single_partition () {
	message="LC_ALL=C sfdisk --force --no-reread --in-order --Linux --unit M ${destination}" ; broadcast
	message="${conf_partition1_startmb},${conf_partition1_endmb},${conf_partition1_fstype},*" ; broadcast
	message="-----------------------------" ; broadcast

	LC_ALL=C sfdisk --force --no-reread --in-order --Linux --unit M ${destination} <<-__EOF__
		${conf_partition1_startmb},,${conf_partition1_fstype},*
	__EOF__

	auto_fsck
	message="resize2fs -f ${destination}p1" ; broadcast
	resize2fs -f ${destination}p1 || write_failure
	message="-----------------------------" ; broadcast
}

resize_emmc () {
	unset resized

	conf_partition1_startmb=$(cat ${wfile} | grep -v '#' | grep conf_partition1_startmb | awk -F '=' '{print $2}' || true)
	conf_partition1_fstype=$(cat ${wfile} | grep -v '#' | grep conf_partition1_fstype | awk -F '=' '{print $2}' || true)
	conf_partition1_endmb=$(cat ${wfile} | grep -v '#' | grep conf_partition1_endmb | awk -F '=' '{print $2}' || true)

	conf_partition2_fstype=$(cat ${wfile} | grep -v '#' | grep conf_partition2_fstype | awk -F '=' '{print $2}' || true)
	conf_partition2_endmb=$(cat ${wfile} | grep -v '#' | grep conf_partition2_endmb | awk -F '=' '{print $2}' || true)

	conf_partition3_fstype=$(cat ${wfile} | grep -v '#' | grep conf_partition3_fstype | awk -F '=' '{print $2}' || true)
	conf_partition3_endmb=$(cat ${wfile} | grep -v '#' | grep conf_partition3_endmb | awk -F '=' '{print $2}' || true)

	conf_partition4_fstype=$(cat ${wfile} | grep -v '#' | grep conf_partition4_fstype | awk -F '=' '{print $2}' || true)

	if [ ! "x${conf_partition4_fstype}" = "x" ] ; then
		quad_partition
		resized="done"
	fi

	if [ ! "x${conf_partition3_fstype}" = "x" ] && [ ! "x${resized}" = "xdone" ] ; then
		tri_partition
		resized="done"
	fi

	if [ ! "x${conf_partition2_fstype}" = "x" ] && [ ! "x${resized}" = "xdone" ] ; then
		dual_partition
		resized="done"
	fi

	if [ ! "x${conf_partition1_fstype}" = "x" ] && [ ! "x${resized}" = "xdone" ] ; then
		single_partition
		resized="done"
	fi
	flush_cache
}

set_uuid () {
	unset root_uuid
	root_uuid=$(/sbin/blkid -c /dev/null -s UUID -o value ${destination}p${conf_root_partition} || true)
	mkdir -p /tmp/rootfs/
	mkdir -p /tmp/boot/

	mount ${destination}p${conf_root_partition} /tmp/rootfs/ -o async,noatime
	sleep 2

	if [ ! "x${conf_root_partition}" = "x1" ] ; then
		mount ${destination}p1 /tmp/boot/ -o sync
		sleep 2
	fi

	if [ -f /tmp/rootfs/boot/uEnv.txt ] && [ -f /tmp/boot/uEnv.txt ] ; then
		rm -f /tmp/boot/uEnv.txt
		umount /tmp/boot/ || umount -l /tmp/boot/ || write_failure
	fi

	if [ -f /tmp/rootfs/boot/uEnv.txt ] && [ -f /tmp/rootfs/uEnv.txt ] ; then
		rm -f /tmp/rootfs/uEnv.txt
	fi

	unset uuid_uevntxt
	uuid_uevntxt=$(cat /tmp/rootfs/boot/uEnv.txt | grep -v '#' | grep uuid | awk -F '=' '{print $2}' || true)
	if [ ! "x${uuid_uevntxt}" = "x" ] ; then
		sed -i -e "s:uuid=$uuid_uevntxt:uuid=$root_uuid:g" /tmp/rootfs/boot/uEnv.txt
	else
		sed -i -e "s:#uuid=:uuid=$root_uuid:g" /tmp/rootfs/boot/uEnv.txt
		unset uuid_uevntxt
		uuid_uevntxt=$(cat /tmp/rootfs/boot/uEnv.txt | grep -v '#' | grep uuid | awk -F '=' '{print $2}' || true)
		if [ "x${uuid_uevntxt}" = "x" ] ; then
			echo "uuid=${root_uuid}" >> /tmp/rootfs/boot/uEnv.txt
		fi
	fi

	unset uuid_uevntxt
	uuid_uevntxt=$(cat /tmp/rootfs/boot/uEnv.txt | grep -v '#' | grep cmdline | awk -F '=' '{print $2}' || true)
	if [ ! "x${uuid_uevntxt}" = "x" ] ; then
		sed -i -e "s:cmdline=init:#cmdline=init:g" /tmp/rootfs/boot/uEnv.txt
	fi

	message="`cat /tmp/rootfs/boot/uEnv.txt | grep uuid`" ; broadcast
	message="-----------------------------" ; broadcast
	flush_cache

	message="UUID=${root_uuid}" ; broadcast
	root_uuid="UUID=${root_uuid}"

	message="Generating: /etc/fstab" ; broadcast
	echo "# /etc/fstab: static file system information." > /tmp/rootfs/etc/fstab
	echo "#" >> /tmp/rootfs/etc/fstab
	echo "${root_uuid}  /  ext4  noatime,errors=remount-ro  0  1" >> /tmp/rootfs/etc/fstab
	echo "debugfs  /sys/kernel/debug  debugfs  defaults  0  0" >> /tmp/rootfs/etc/fstab
	message="`cat /tmp/rootfs/etc/fstab`" ; broadcast
	message="-----------------------------" ; broadcast
	flush_cache

	umount /tmp/rootfs/ || umount -l /tmp/rootfs/ || write_failure
}

check_eeprom () {
	unset got_eeprom
	#v8 of nvmem...
	if [ -f /sys/bus/nvmem/devices/at24-0/nvmem ] && [ "x${got_eeprom}" = "x" ] ; then
		eeprom="/sys/bus/nvmem/devices/at24-0/nvmem"
		eeprom_location="/sys/devices/platform/ocp/44e0b000.i2c/i2c-0/0-0050/at24-0/nvmem"
		got_eeprom="true"
	fi

	#pre-v8 of nvmem...
	if [ -f /sys/class/nvmem/at24-0/nvmem ] && [ "x${got_eeprom}" = "x" ] ; then
		eeprom="/sys/class/nvmem/at24-0/nvmem"
		eeprom_location="/sys/devices/platform/ocp/44e0b000.i2c/i2c-0/0-0050/nvmem/at24-0/nvmem"
		got_eeprom="true"
	fi

	#eeprom 3.8.x & 4.4 with eeprom-nvmem patchset...
	if [ -f /sys/bus/i2c/devices/0-0050/eeprom ] && [ "x${got_eeprom}" = "x" ] ; then
		eeprom="/sys/bus/i2c/devices/0-0050/eeprom"

		if [ -f /sys/devices/platform/ocp/44e0b000.i2c/i2c-0/0-0050/eeprom ] ; then
			eeprom_location="/sys/devices/platform/ocp/44e0b000.i2c/i2c-0/0-0050/eeprom"
		else
			eeprom_location=$(ls /sys/devices/ocp*/44e0b000.i2c/i2c-0/0-0050/eeprom 2> /dev/null)
		fi

		got_eeprom="true"
	fi

	if [ "x${is_bbb}" = "xenable" ] ; then
		if [ "x${got_eeprom}" = "xtrue" ] ; then
			eeprom_header=$(hexdump -e '8/1 "%c"' ${eeprom} -n 8 | cut -b 6-8)
			if [ "x${eeprom_header}" = "x${conf_eeprom_compare}" ] ; then
				message="Valid EEPROM header found [${eeprom_header}]" ; broadcast
				message="-----------------------------" ; broadcast
			else
				message="Invalid EEPROM header detected" ; broadcast
				if [ -f ${wdir}/${conf_eeprom_file} ] ; then
					if [ ! "x${eeprom_location}" = "x" ] ; then
						message="Writing header to EEPROM" ; broadcast
						dd if=${wdir}/${conf_eeprom_file} of=${eeprom_location} || write_failure
						sync
						sync
						eeprom_check=$(hexdump -e '8/1 "%c"' ${eeprom} -n 8 | cut -b 6-8)
						echo "eeprom check: [${eeprom_check}]"

						#We have to reboot, as the kernel only loads the eMMC cape
						# with a valid header
						reboot -f

						#We shouldnt hit this...
						exit
					fi
				else
					message="error: no [${wdir}/${conf_eeprom_file}]" ; broadcast
				fi
			fi
		fi
	fi
}

process_job_file () {
	job_file=found
	if [ ! -f /usr/bin/dos2unix ] ; then
		message="Warning: dos2unix not installed, dont use windows to create job.txt file." ; broadcast
		sleep 1
	else
		dos2unix -n ${wfile} /tmp/job.txt
		wfile="/tmp/job.txt"
	fi
	message="Processing job.txt:" ; broadcast
	message="`cat ${wfile} | grep -v '#'`" ; broadcast
	message="-----------------------------" ; broadcast

	abi=$(cat ${wfile} | grep -v '#' | grep abi | awk -F '=' '{print $2}' || true)
	if [ "x${abi}" = "xaaa" ] ; then
		conf_eeprom_file=$(cat ${wfile} | grep -v '#' | grep conf_eeprom_file | awk -F '=' '{print $2}' || true)
		conf_eeprom_compare=$(cat ${wfile} | grep -v '#' | grep conf_eeprom_compare | awk -F '=' '{print $2}' || true)
		if [ ! "x${conf_eeprom_file}" = "x" ] ; then
			if [ -f ${wdir}/${conf_eeprom_file} ] ; then
				check_eeprom
			fi
		fi

		conf_image=$(cat ${wfile} | grep -v '#' | grep conf_image | awk -F '=' '{print $2}' || true)
		#check if it was pre-un-compressed:
		unset image_is_uncompressed
		if [ ! -f ${wdir}/${conf_image} ] ; then
			test_image=$(echo ${conf_image} | awk -F '.xz' '{ print $1 }')
			if [ -f ${wdir}/${test_image} ] ; then
				conf_image=${test_image}
				image_is_uncompressed="enable"
			fi
		fi

		if [ ! "x${conf_image}" = "x" ] ; then
			if [ -f ${wdir}/${conf_image} ] ; then
				conf_bmap=$(cat ${wfile} | grep -v '#' | grep conf_bmap | awk -F '=' '{print $2}' || true)
				if [ "x${is_bbb}" = "xenable" ] ; then
					cylon_leds & CYLON_PID=$!
				fi
				flash_emmc
				conf_resize=$(cat ${wfile} | grep -v '#' | grep conf_resize | awk -F '=' '{print $2}' || true)
				if [ "x${conf_resize}" = "xenable" ] ; then
					message="resizing eMMC" ; broadcast
					message="-----------------------------" ; broadcast
					resize_emmc
				fi
				conf_root_partition=$(cat ${wfile} | grep -v '#' | grep conf_root_partition | awk -F '=' '{print $2}' || true)
				if [ ! "x${conf_root_partition}" = "x" ] ; then
					set_uuid
				fi

				if [ "x${is_bbb}" = "xenable" ] ; then
					[ -e /proc/$CYLON_PID ]  && kill $CYLON_PID
				fi
			else
				message="error: image not found [${wdir}/${conf_image}]" ; broadcast
			fi
		else
			message="error: image not defined [conf_image=${conf_image}]" ; broadcast
		fi
	else
		message="error: unable to decode: [job.txt]" ; broadcast
		sleep 10
		write_failure
	fi
}

check_usb_media () {
	wfile="/tmp/usb/job.txt"
	wdir="/tmp/usb"
	message="Checking external usb media" ; broadcast
	message="lsblk:" ; broadcast
	message="`lsblk || true`" ; broadcast
	message="-----------------------------" ; broadcast

	if [ "x${is_bbb}" = "xenable" ] ; then
		if [ ! -e /sys/class/leds/beaglebone\:green\:usr0/trigger ] ; then
			modprobe leds_gpio || true
			sleep 1
		fi
	fi

	unset job_file

	num_partitions=$(LC_ALL=C fdisk -l 2>/dev/null | grep "^${usb_drive}" | grep -v "Extended" | grep -v "swap" | wc -l)

	i=0 ; while test $i -le ${num_partitions} ; do
		partition=$(LC_ALL=C fdisk -l 2>/dev/null | grep "^${usb_drive}" | grep -v "Extended" | grep -v "swap" | head -${i} | tail -1 | awk '{print $1}')
		if [ ! "x${partition}" = "x" ] ; then
			message="Trying: [${partition}]" ; broadcast

			mkdir -p "/tmp/usb/"
			mount ${partition} "/tmp/usb/" -o ro

			sync ; sync ; sleep 5

			if [ ! -f ${wfile} ] ; then
				umount "/tmp/usb/" || true
			else
				process_job_file
			fi

		fi
	i=$(($i+1))
	done

	if [ ! "x${job_file}" = "xfound" ] ; then
		if [ -f /opt/emmc/job.txt ] ; then
			wfile="/opt/emmc/job.txt"
			wdir="/opt/emmc"
			process_job_file
		else
			message="job.txt: format" ; broadcast
			message="-----------------------------" ; broadcast
			message="abi=aaa" ; broadcast
			message="conf_eeprom_file=<file>" ; broadcast
			message="conf_eeprom_compare=<6-8>" ; broadcast
			message="conf_image=<file>.img.xz" ; broadcast
			message="conf_bmap=<file>.bmap" ; broadcast
			message="conf_resize=enable|<blank>" ; broadcast
			message="conf_partition1_startmb=1" ; broadcast
			message="conf_partition1_fstype=" ; broadcast

			message="#last endmb is ignored as it just uses the rest of the drive..." ; broadcast
			message="conf_partition1_endmb=" ; broadcast

			message="conf_partition2_fstype=" ; broadcast
			message="conf_partition2_endmb=" ; broadcast

			message="conf_partition3_fstype=" ; broadcast
			message="conf_partition3_endmb=" ; broadcast

			message="conf_partition4_fstype=" ; broadcast

			message="conf_root_partition=1|2|3|4" ; broadcast
			message="-----------------------------" ; broadcast
			write_failure
		fi
	fi

	message="eMMC has been flashed: please wait for device to power down." ; broadcast
	message="-----------------------------" ; broadcast

	umount /tmp || umount -l /tmp

	if [ "x${is_bbb}" = "xenable" ] ; then
		if [ -e /sys/class/leds/beaglebone\:green\:usr0/trigger ] ; then
			echo default-on > /sys/class/leds/beaglebone\:green\:usr0/trigger
			echo default-on > /sys/class/leds/beaglebone\:green\:usr1/trigger
			echo default-on > /sys/class/leds/beaglebone\:green\:usr2/trigger
			echo default-on > /sys/class/leds/beaglebone\:green\:usr3/trigger
		fi
	fi

	sleep 1

	#To properly shudown, /opt/scripts/boot/am335x_evm.sh is going to call halt:
	exec /sbin/init
	#halt -f
}

sleep 5
clear
message="-----------------------------" ; broadcast
message="Starting eMMC Flasher from usb media" ; broadcast
message="Version: [${version_message}]" ; broadcast
message="-----------------------------" ; broadcast

get_device
print_eeprom
check_usb_media
#
