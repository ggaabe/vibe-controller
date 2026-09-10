// Session worker inside the signed, approved USB service. Never captures until
// the authenticated broker supplies a private session fd. No auto-detach.
#include <libusb.h>
#include <sys/socket.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <stdatomic.h>
#include <poll.h>

static atomic_bool stopping;
void vibe_usb_session_request_stop(void) { atomic_store(&stopping, true); }
static double monotime(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

// Fixed frames: kind, payload length, six reserved zeros, 64-byte payload.
// A stalled reader ends capture instead of accumulating delayed input.
static bool frame(int fd, uint8_t kind, const void *payload, size_t length) {
    if (length > 64) return false;
    uint8_t bytes[72] = {kind, (uint8_t)length};
    if (length) memcpy(bytes + 8, payload, length);
    return send(fd, bytes, sizeof(bytes), MSG_DONTWAIT) == sizeof(bytes);
}
static void message(int fd, uint8_t kind, const char *text) {
    frame(fd, kind, text, strnlen(text, 64));
}
static void usb_error(int fd, const char *stage, int result) {
    char text[65];
    snprintf(text, sizeof(text), "%s: %s (%d)", stage, libusb_error_name(result), result);
    message(fd, 3, text);
}
static bool usb_write(libusb_device_handle *handle, uint8_t *bytes, int count) {
    int sent = 0;
    return libusb_interrupt_transfer(handle, 0x02, bytes, count, &sent, 100) == 0 && sent == count;
}
static bool rumble(libusb_device_handle *handle, uint8_t *sequence, uint8_t left, uint8_t right, uint8_t ticks) {
    if (!ticks) left = right = 0; // Never interpret zero duration as indefinite.
    if (++*sequence == 0) ++*sequence;
    uint8_t bytes[] = {9, 0, *sequence, 9, 0, 15, 0, 0, left, right, ticks, 0, 0};
    return usb_write(handle, bytes, sizeof(bytes));
}

int vibe_usb_run_session(int fd) {
    if (geteuid() != 0 || atomic_load(&stopping)) { close(fd); return 2; }
    // Require the client to accept the returned fd before touching hardware.
    // A cancelled/timed-out XPC request must never start a USB capture later.
    uint8_t hello[8] = {0}; size_t hello_size = 0;
    double hello_deadline = monotime() + 3;
    while (hello_size < sizeof(hello) && monotime() < hello_deadline && !atomic_load(&stopping)) {
        struct pollfd p = {.fd = fd, .events = POLLIN};
        if (poll(&p, 1, 100) <= 0) continue;
        ssize_t n = recv(fd, hello + hello_size, sizeof(hello) - hello_size, 0);
        if (n <= 0) { close(fd); return 2; }
        hello_size += (size_t)n;
    }
    static const uint8_t heartbeat_command[8] = {0};
    if (hello_size != 8 || memcmp(hello, heartbeat_command, 8) || atomic_load(&stopping)) {
        close(fd); return 2;
    }
    libusb_context *context = NULL; libusb_device **devices = NULL;
    libusb_device_handle *handle = NULL;
    bool captured = false, claimed = false;
    uint8_t sequence = 1;
    int result = libusb_init(&context);
    if (result) { message(fd, 3, "Could not initialize USB."); close(fd); return 4; }
    ssize_t count = libusb_get_device_list(context, &devices);
    libusb_device *target = NULL; int matches = 0;
    for (ssize_t i = 0; i < count; ++i) {
        struct libusb_device_descriptor d;
        if (!libusb_get_device_descriptor(devices[i], &d) && d.idVendor == 0x045e && d.idProduct == 0x0b12) {
            target = devices[i]; ++matches;
        }
    }
    if (matches != 1) { message(fd, 3, "Connect exactly one Xbox Series controller using USB."); goto cleanup; }
    struct libusb_config_descriptor *config = NULL;
    bool input = false, output = false;
    if (!libusb_get_active_config_descriptor(target, &config)) {
        for (int i = 0; i < config->bNumInterfaces; ++i) {
            for (int j = 0; j < config->interface[i].num_altsetting; ++j) {
                const struct libusb_interface_descriptor *a = &config->interface[i].altsetting[j];
                if (a->bInterfaceNumber || a->bAlternateSetting || a->bInterfaceClass != 0xff ||
                    a->bInterfaceSubClass != 0x47 || a->bInterfaceProtocol != 0xd0) continue;
                for (int k = 0; k < a->bNumEndpoints; ++k) {
                    const struct libusb_endpoint_descriptor *e = &a->endpoint[k];
                    if ((e->bmAttributes & 3) != LIBUSB_TRANSFER_TYPE_INTERRUPT || e->wMaxPacketSize != 64) continue;
                    input |= e->bEndpointAddress == 0x82; output |= e->bEndpointAddress == 0x02;
                }
            }
        }
        libusb_free_config_descriptor(config);
    }
    if (!input || !output) { message(fd, 3, "Unsupported Xbox USB interface. No controller changed."); goto cleanup; }
    result = libusb_open(target, &handle);
    if (result) { usb_error(fd, "USB open failed", result); goto cleanup; }
    result = libusb_kernel_driver_active(handle, 0);
    if (result != 1) {
        if (result < 0) usb_error(fd, "USB driver lookup failed", result);
        else message(fd, 3, "Apple USB driver is not attached. Reconnect the controller.");
        goto cleanup;
    }
    uint8_t pending;
    if (atomic_load(&stopping) || recv(fd, &pending, 1, MSG_PEEK | MSG_DONTWAIT) == 0) goto cleanup;
    result = libusb_detach_kernel_driver(handle, 0);
    if (result) { usb_error(fd, "USB capture failed", result); goto cleanup; }
    captured = true;
    if (atomic_load(&stopping)) goto cleanup;
    result = libusb_claim_interface(handle, 0);
    if (result) { usb_error(fd, "USB claim failed", result); goto cleanup; }
    claimed = true;
    uint8_t wake[] = {5, 0x20, 1, 1, 0};
    if (!usb_write(handle, wake, sizeof(wake))) {
        message(fd, 3, "Could not start Xbox USB input."); goto cleanup;
    }
    if (!frame(fd, 1, NULL, 0)) goto cleanup;
    double heartbeat = monotime(), last_status = heartbeat, rate_window = heartbeat;
    unsigned commands = 0;
    uint8_t command[8]; size_t command_length = 0;
    while (!atomic_load(&stopping) && monotime() - heartbeat < 3) {
        if (monotime() - rate_window >= 1) { commands = 0; rate_window = monotime(); }
        // Only heartbeat, bounded rumble, and stop are accepted. Never forward
        // client-supplied native opcodes to the device.
        for (int n = 0; n < 32; ++n) {
            ssize_t got = recv(fd, command + command_length, 8 - command_length, MSG_DONTWAIT);
            if (got == 0) goto cleanup;
            if (got < 0) {
                if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) break;
                goto cleanup;
            }
            command_length += (size_t)got;
            if (command_length != 8) continue;
            command_length = 0;
            if (++commands > 250 || command[4] || command[5] || command[6] || command[7]) goto cleanup;
            if (command[0] == 0 && !command[1] && !command[2] && !command[3]) heartbeat = monotime();
            else if (command[0] == 2 && !command[1] && !command[2] && !command[3]) goto cleanup;
            else if (command[0] == 1 && command[1] <= 100 && command[2] <= 100 && command[3] <= 100) {
                if (!rumble(handle, &sequence, command[1], command[2], command[3])) {
                    message(fd, 3, "USB vibration write failed. Reconnect the controller."); goto cleanup;
                }
            } else goto cleanup;
        }
        uint8_t bytes[64]; int length = 0;
        result = libusb_interrupt_transfer(handle, 0x82, bytes, sizeof(bytes), &length, 4);
        if (result != LIBUSB_ERROR_TIMEOUT && result != LIBUSB_SUCCESS) {
            message(fd, 3, "Xbox USB disconnected. Reconnect it before enabling again."); goto cleanup;
        }
        if (!result && length > 0) {
            // GIP virtual-key requests need acknowledgement (including Guide).
            if (length >= 6 && bytes[0] == 7 && (bytes[1] & 0x30) == 0x30) {
                uint8_t ack[] = {1, 0x20, bytes[2], 9, 0, 7, 0x20, 2, 0, 0, 0, 0, 0};
                if (!usb_write(handle, ack, sizeof(ack))) goto cleanup;
            }
            if (!frame(fd, 2, bytes, (size_t)length)) goto cleanup;
        }
        if (monotime() - last_status >= 0.5) {
            if (!frame(fd, 5, NULL, 0)) goto cleanup;
            last_status = monotime();
        }
    }
cleanup:
    if (claimed) {
        rumble(handle, &sequence, 0, 0, 0);
        result = libusb_release_interface(handle, 0);
        if (result) message(fd, 3, "USB release failed. Unplug and reconnect the controller.");
    }
    // Explicit ordering is important: auto-detach can leave a captured device.
    if (captured) {
        result = libusb_attach_kernel_driver(handle, 0);
        message(fd, result ? 3 : 4, result
            ? "Reconnect the controller to restore Apple's USB driver."
            : "USB released. Reconnect if normal USB vibration is silent.");
    }
    if (handle) libusb_close(handle);
    if (devices) libusb_free_device_list(devices, 1);
    libusb_exit(context); close(fd);
    return 0;
}
