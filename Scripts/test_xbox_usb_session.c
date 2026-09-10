// Hardware-free tests of the exact privileged session worker, with a fake USB
// backend. No administrator privileges, device opens, or capture required.
#include <libusb.h>
#include <assert.h>
#include <pthread.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>

enum scenario { NORMAL, INIT_FAIL, OPEN_FAIL, DRIVER_MISSING, DRIVER_ERROR, CAPTURE_FAIL, CLAIM_FAIL, WAKE_FAIL, INPUT_FAIL };
static enum scenario scenario;
static int inits, detaches, claims, releases, attaches, writes;
static char order[64];
static void mark(char value) { size_t n = strlen(order); order[n] = value; order[n + 1] = 0; }
static uid_t mock_uid(void) { return 0; }
static int mock_init(libusb_context **ctx) { ++inits; *ctx = (void *)1; return scenario == INIT_FAIL ? LIBUSB_ERROR_OTHER : 0; }
static ssize_t mock_devices(libusb_context *ctx, libusb_device ***devices) {
    (void)ctx; static libusb_device *list[] = {(void *)1}; *devices = list; return 1;
}
static int mock_descriptor(libusb_device *d, struct libusb_device_descriptor *result) {
    (void)d; memset(result, 0, sizeof(*result)); result->idVendor = 0x045e; result->idProduct = 0x0b12; return 0;
}
static int mock_config(libusb_device *d, struct libusb_config_descriptor **result) {
    (void)d;
    static struct libusb_endpoint_descriptor endpoints[] = {
        {.bEndpointAddress = 0x82, .bmAttributes = 3, .wMaxPacketSize = 64},
        {.bEndpointAddress = 0x02, .bmAttributes = 3, .wMaxPacketSize = 64}};
    static struct libusb_interface_descriptor alt = {.bInterfaceClass = 0xff, .bInterfaceSubClass = 0x47,
        .bInterfaceProtocol = 0xd0, .bNumEndpoints = 2, .endpoint = endpoints};
    static struct libusb_interface interface = {.altsetting = &alt, .num_altsetting = 1};
    static struct libusb_config_descriptor config = {.bNumInterfaces = 1, .interface = &interface};
    *result = &config; return 0;
}
static void mock_free_config(struct libusb_config_descriptor *c) { (void)c; }
static int mock_open(libusb_device *d, libusb_device_handle **handle) {
    (void)d; mark('o'); if (scenario == OPEN_FAIL) return LIBUSB_ERROR_ACCESS; *handle = (void *)1; return 0;
}
static int mock_driver(libusb_device_handle *h, int i) { (void)h; (void)i;
    return scenario == DRIVER_MISSING ? 0 : scenario == DRIVER_ERROR ? LIBUSB_ERROR_NOT_FOUND : 1;
}
static int mock_detach(libusb_device_handle *h, int i) { (void)h; (void)i; ++detaches; mark('d'); return scenario == CAPTURE_FAIL ? LIBUSB_ERROR_BUSY : 0; }
static int mock_claim(libusb_device_handle *h, int i) { (void)h; (void)i; ++claims; mark('c'); return scenario == CLAIM_FAIL ? LIBUSB_ERROR_BUSY : 0; }
static int mock_transfer(libusb_device_handle *h, unsigned char ep, unsigned char *bytes, int length, int *sent, unsigned int timeout) {
    (void)h; (void)timeout;
    if (ep == 0x82) return LIBUSB_ERROR_NO_DEVICE;
    assert(ep == 2); ++writes;
    if (bytes[0] == 5 && scenario == WAKE_FAIL) return LIBUSB_ERROR_IO;
    assert(bytes[0] == 5 || (bytes[0] == 9 && length == 13 && bytes[10] <= 100));
    *sent = length; return 0;
}
static int mock_release(libusb_device_handle *h, int i) { (void)h; (void)i; ++releases; mark('r'); return 0; }
static int mock_attach(libusb_device_handle *h, int i) { (void)h; (void)i; ++attaches; mark('a'); return 0; }
static void mock_close(libusb_device_handle *h) { (void)h; mark('x'); }
static void mock_free_devices(libusb_device **d, int unref) { (void)d; (void)unref; }
static void mock_exit(libusb_context *ctx) { (void)ctx; }

#define geteuid mock_uid
#define libusb_init mock_init
#define libusb_get_device_list mock_devices
#define libusb_get_device_descriptor mock_descriptor
#define libusb_get_active_config_descriptor mock_config
#define libusb_free_config_descriptor mock_free_config
#define libusb_open mock_open
#define libusb_kernel_driver_active mock_driver
#define libusb_detach_kernel_driver mock_detach
#define libusb_claim_interface mock_claim
#define libusb_interrupt_transfer mock_transfer
#define libusb_release_interface mock_release
#define libusb_attach_kernel_driver mock_attach
#define libusb_close mock_close
#define libusb_free_device_list mock_free_devices
#define libusb_exit mock_exit
#include "xbox_usb_session.c"

static void *run(void *p) { vibe_usb_run_session(*(int *)p); return NULL; }
static void reset(enum scenario next) { scenario = next; inits = detaches = claims = releases = attaches = writes = 0; order[0] = 0; }
int main(void) {
    for (int n = 0; n < 2; ++n) {
        reset(NORMAL); int pair[2]; assert(!socketpair(AF_UNIX, SOCK_STREAM, 0, pair));
        if (n) { uint8_t invalid[8] = {99}; assert(write(pair[0], invalid, 8) == 8); }
        close(pair[0]); vibe_usb_run_session(pair[1]); assert(inits == 0);
    }
    for (enum scenario next = NORMAL; next <= INPUT_FAIL; ++next) {
        reset(next); int pair[2]; assert(!socketpair(AF_UNIX, SOCK_STREAM, 0, pair));
        assert(fcntl(pair[1], F_SETFL, O_NONBLOCK) == 0);
        int one = 1; setsockopt(pair[1], SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
        uint8_t commands[16] = {0}; commands[8] = 2;
        assert(write(pair[0], commands, next == INPUT_FAIL ? 8 : 16) == (next == INPUT_FAIL ? 8 : 16));
        pthread_t thread; assert(!pthread_create(&thread, NULL, run, &pair[1]));
        uint8_t frames[720] = {0}; size_t total = 0; ssize_t got;
        while ((got = read(pair[0], frames + total, sizeof(frames) - total)) > 0) total += (size_t)got;
        pthread_join(thread, NULL); close(pair[0]); assert(total % 72 == 0); assert(inits == 1);
        if (next <= DRIVER_ERROR && next != NORMAL) { assert(detaches == 0 && attaches == 0); }
        if (next == CAPTURE_FAIL) assert(attaches == 0 && claims == 0);
        if (next == CLAIM_FAIL) assert(releases == 0 && attaches == 1);
        if (next == NORMAL || next == WAKE_FAIL || next == INPUT_FAIL) {
            assert(releases == 1 && attaches == 1 && strstr(order, "ra"));
        }
        if (next != NORMAL) {
            bool found_error = false;
            for (size_t offset = 0; offset < total; offset += 72) found_error |= frames[offset] == 3;
            assert(found_error);
        }
        printf("PASS simulated USB scenario %d: %s\n", next, order);
    }
    puts("PASS abandoned/invalid sessions never open USB; cleanup releases before reattaching.");
    return 0;
}
