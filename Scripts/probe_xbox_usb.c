// Non-disruptive Xbox USB access probe. No detach, reset, or output requests.
// clang -Wall -Wextra -Werror -I/opt/homebrew/include/libusb-1.0 \
//   scripts/probe_xbox_usb.c -L/opt/homebrew/lib -lusb-1.0 -o /tmp/probe_xbox_usb
#include <libusb.h>
#include <stdio.h>

int main(void) {
    libusb_context *context = NULL;
    int result = libusb_init(&context);
    if (result != LIBUSB_SUCCESS) return 1;
    const struct libusb_version *version = libusb_get_version();
    printf("libusb %u.%u.%u; no driver detach or reset permitted by this probe\n",
           version->major, version->minor, version->micro);
    libusb_device **devices = NULL;
    ssize_t count = libusb_get_device_list(context, &devices);
    for (ssize_t i = 0; i < count; ++i) {
        struct libusb_device_descriptor descriptor;
        if (libusb_get_device_descriptor(devices[i], &descriptor) != LIBUSB_SUCCESS ||
            descriptor.idVendor != 0x045e || descriptor.idProduct != 0x0b12) continue;
        printf("Xbox Series USB %04x:%04x bcdDevice=%04x\n",
               descriptor.idVendor, descriptor.idProduct, descriptor.bcdDevice);
        libusb_device_handle *handle = NULL;
        result = libusb_open(devices[i], &handle);
        printf("open: %s (%d)\n", libusb_error_name(result), result);
        if (result != LIBUSB_SUCCESS) continue;
        printf("interface 0 driver active: %d\n", libusb_kernel_driver_active(handle, 0));
        struct libusb_config_descriptor *config = NULL;
        if (libusb_get_active_config_descriptor(devices[i], &config) == LIBUSB_SUCCESS) {
            for (int j = 0; j < config->bNumInterfaces; ++j) {
                const struct libusb_interface *interface = &config->interface[j];
                for (int k = 0; k < interface->num_altsetting; ++k) {
                    const struct libusb_interface_descriptor *setting = &interface->altsetting[k];
                    printf("interface %u alt %u class=%02x subclass=%02x protocol=%02x\n",
                           setting->bInterfaceNumber, setting->bAlternateSetting,
                           setting->bInterfaceClass, setting->bInterfaceSubClass,
                           setting->bInterfaceProtocol);
                    for (int e = 0; e < setting->bNumEndpoints; ++e)
                        printf("  endpoint %02x attributes=%02x packet=%u\n",
                               setting->endpoint[e].bEndpointAddress,
                               setting->endpoint[e].bmAttributes,
                               setting->endpoint[e].wMaxPacketSize);
                }
            }
            libusb_free_config_descriptor(config);
        }
        result = libusb_claim_interface(handle, 0);
        printf("non-detaching claim: %s (%d)\n", libusb_error_name(result), result);
        if (result == LIBUSB_SUCCESS) libusb_release_interface(handle, 0);
        libusb_close(handle);
    }
    if (devices) libusb_free_device_list(devices, 1);
    libusb_exit(context);
    return 0;
}
