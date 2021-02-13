#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libudev.h>

#define BLOCK_SIZE 512
#define MAX_DEVICE_NUMBER 255

typedef struct
{
    int index;
    char model[100];
    char devpath[100];
    char syspath[100];
    char devnode[20];
    char sysname[10];
    char devtype[10];
    unsigned int devsize;
} device;

void printMessage(char *message)
{
    printf("\e[30;107m\e[5m>>> %s\e[0m\n", message);
}

void initDeviceList(device deviceList[])
{
    unsigned char index;
    for (index = 0; index < MAX_DEVICE_NUMBER; index++)
        deviceList[index].index = -1;
}

int getDeviceList(device deviceList[])
{
    unsigned char index = 0;
    struct udev *udev;
    struct udev_device *dev;
    struct udev_enumerate *enumerate;
    struct udev_list_entry *devices, *dev_list_entry;

    /* create udev object */
    udev = udev_new();
    if (!udev)
    {
        fprintf(stderr, "Cannot create udev context.\n");
        return EXIT_FAILURE;
    }

    /* create enumerate object */
    enumerate = udev_enumerate_new(udev);
    if (!enumerate)
    {
        fprintf(stderr, "Cannot create enumerate context.\n");
        return EXIT_FAILURE;
    }

    udev_enumerate_add_match_subsystem(enumerate, "block");
    udev_enumerate_scan_devices(enumerate);

    /* fillup device list */
    devices = udev_enumerate_get_list_entry(enumerate);
    if (!devices)
    {
        fprintf(stderr, "Failed to get device list.\n");
        return EXIT_FAILURE;
    }

    udev_list_entry_foreach(dev_list_entry, devices)
    {
        const char *path, *tmp;
        unsigned long long disk_size = 0;
        unsigned short int block_size = BLOCK_SIZE;

        path = udev_list_entry_get_name(dev_list_entry);
        dev = udev_device_new_from_syspath(udev, path);

        /* skip if device/disk is a partition or loop device */
        if (strncmp(udev_device_get_devtype(dev), "partition", 9) != 0 &&
            strncmp(udev_device_get_sysname(dev), "loop", 4) != 0)
        {
            deviceList[index].index = index;
            strcpy(deviceList[index].model, udev_device_get_sysattr_value(dev, "device/model"));
            strcpy(deviceList[index].devpath, udev_device_get_devpath(dev));
            strcpy(deviceList[index].syspath, udev_device_get_syspath(dev));
            strcpy(deviceList[index].devnode, udev_device_get_devnode(dev));
            strcpy(deviceList[index].sysname, udev_device_get_sysname(dev));
            strcpy(deviceList[index].devtype, udev_device_get_devtype(dev));

            tmp = udev_device_get_sysattr_value(dev, "size");
            if (tmp)
                disk_size = strtoull(tmp, NULL, 10);

            tmp = udev_device_get_sysattr_value(dev, "queue/logical_block_size");
            if (tmp)
                block_size = atoi(tmp);

            if (strncmp(udev_device_get_sysname(dev), "sr", 2) != 0)
                deviceList[index].devsize = (disk_size * block_size) / 1000000000;
            else
                deviceList[index].devsize = 0;
            index++;
        }

        /* free dev */
        udev_device_unref(dev);
    }
    /* free enumerate */
    udev_enumerate_unref(enumerate);
    /* free udev */
    udev_unref(udev);

    return EXIT_SUCCESS;
}

int printDeviceList(device deviceList[])
{
    unsigned char index;
    for (index = 0; index < MAX_DEVICE_NUMBER; index++)
    {
        if (deviceList[index].index == -1)
            break;
        if (strncmp(deviceList[index].sysname, "sr", 2) != 0)
            printf("[%d] %s (%lldGB) %s\n", index, deviceList[index].model, deviceList[index].devsize, deviceList[index].devnode);
        else
            printf("[%d] %s (N/A) %s\n", index, deviceList[index].model, deviceList[index].devnode);
    }
    return index;
}

int main()
{
    device deviceList[MAX_DEVICE_NUMBER];
    initDeviceList(deviceList);
    getDeviceList(deviceList);
    if (getDeviceList(deviceList) == EXIT_FAILURE)
        return EXIT_FAILURE;
    printMessage("Select the device to backup.");
    printDeviceList(deviceList);
}