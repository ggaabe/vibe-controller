// Session-scoped, signed Xbox USB input + rumble helper. No installation,
// arbitrary USB commands, network listener, firmware writes, or auto-detach.
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <libusb.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/ucred.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t stopping;
static void stop_requested(int sig) { (void)sig; stopping = 1; }
static double monotime(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

// Authenticate the actual connected socket peer, never an argv-supplied PID.
static bool authorized_peer(int fd) {
    pid_t pid = 0; socklen_t size = sizeof(pid);
    if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) || pid <= 1) return false;
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberIntType, &pid);
    const void *keys[] = {kSecGuestAttributePid}, *values[] = {number};
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    SecCodeRef peer = NULL, self = NULL;
    CFDictionaryRef peer_info = NULL, self_info = NULL;
    bool ok = false;
    if (SecCodeCopyGuestWithAttributes(NULL, attributes, kSecCSDefaultFlags, &peer) ||
        SecCodeCheckValidity(peer, kSecCSStrictValidate, NULL) ||
        SecCodeCopySelf(kSecCSDefaultFlags, &self) ||
        SecCodeCopySigningInformation(peer, kSecCSSigningInformation, &peer_info) ||
        SecCodeCopySigningInformation(self, kSecCSSigningInformation, &self_info)) goto done;
    CFStringRef id = CFDictionaryGetValue(peer_info, kSecCodeInfoIdentifier);
    CFStringRef team = CFDictionaryGetValue(peer_info, kSecCodeInfoTeamIdentifier);
    CFStringRef own_team = CFDictionaryGetValue(self_info, kSecCodeInfoTeamIdentifier);
    ok = id && team && own_team && CFEqual(team, own_team) &&
        (CFEqual(id, CFSTR("com.vibe-controller.app")) ||
         CFEqual(id, CFSTR("com.vibe-controller.app.dev")));
done:
    if (peer) CFRelease(peer);
    if (self) CFRelease(self);
    if (peer_info) CFRelease(peer_info);
    if (self_info) CFRelease(self_info);
    CFRelease(attributes); CFRelease(number);
    return ok;
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

int main(int argc, char **argv) {
    if (argc != 3 || strcmp(argv[1], "--socket") || geteuid() != 0) {
        fputs("Requires an authorized Vibe Controller USB session.\n", stderr); return 2;
    }
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    if (strlen(argv[2]) >= sizeof(address.sun_path)) return 2;
    strlcpy(address.sun_path, argv[2], sizeof(address.sun_path));
    int fd = socket(AF_UNIX, SOCK_STREAM, 0), one = 1;
    if (fd < 0) return 3;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) || !authorized_peer(fd)) {
        close(fd); fputs("Unauthorized socket peer. No controller changed.\n", stderr); return 3;
    }
    fcntl(fd, F_SETFL, O_NONBLOCK);
    struct sigaction action = {.sa_handler = stop_requested};
    sigaction(SIGINT, &action, NULL); sigaction(SIGTERM, &action, NULL);

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
    if (libusb_open(target, &handle) || libusb_kernel_driver_active(handle, 0) != 1) {
        message(fd, 3, "Controller unavailable. Reconnect it, then try again."); goto cleanup;
    }
    if (libusb_detach_kernel_driver(handle, 0)) {
        message(fd, 3, "USB capture failed. Reconnect the controller and retry."); goto cleanup;
    }
    captured = true;
    if (libusb_claim_interface(handle, 0)) {
        message(fd, 3, "Could not claim Xbox USB input."); goto cleanup;
    }
    claimed = true;
    uint8_t wake[] = {5, 0x20, 1, 1, 0};
    if (!usb_write(handle, wake, sizeof(wake))) {
        message(fd, 3, "Could not start Xbox USB input."); goto cleanup;
    }
    if (!frame(fd, 1, NULL, 0)) goto cleanup;
    double heartbeat = monotime(), last_status = heartbeat, rate_window = heartbeat;
    unsigned commands = 0;
    uint8_t command[8]; size_t command_length = 0;
    while (!stopping && monotime() - heartbeat < 3) {
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
