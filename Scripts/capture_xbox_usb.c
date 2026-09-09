// Explicit, temporary Xbox Series USB capture. Not part of the installed app.
// Requires root on macOS; affects only the single 045e:0b12 controller.
// Builds with libusb 1.0.30. Never enables automatic driver detachment: release
// the claimed interface BEFORE explicitly restoring Apple's driver.
// Protocol reference: Linux xpad's GIP power-on message (05 20 seq 01 00).
#include <libusb.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t stopping = 0;
static void stop_requested(int signal_number) { (void)signal_number; stopping = 1; }
static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

int main(int argc, char **argv) {
    if (argc != 2 || strcmp(argv[1], "--capture-30-seconds") != 0) {
        fprintf(stderr, "Usage: %s --capture-30-seconds\n", argv[0]);
        return 2;
    }
    if (geteuid() != 0) {
        fprintf(stderr, "Administrator authorization is required. No device was changed.\n");
        return 3;
    }
    setvbuf(stdout, NULL, _IOLBF, 0);
    struct sigaction action = {0};
    action.sa_handler = stop_requested;
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGALRM, &action, NULL);

    libusb_context *context = NULL;
    libusb_device **devices = NULL;
    libusb_device_handle *handle = NULL;
    bool captured = false, claimed = false;
    int exit_code = 1;
    int result = libusb_init(&context);
    if (result != LIBUSB_SUCCESS) return 1;
    ssize_t count = libusb_get_device_list(context, &devices);
    libusb_device *target = NULL;
    int matching = 0;
    for (ssize_t i = 0; i < count; ++i) {
        struct libusb_device_descriptor descriptor;
        if (libusb_get_device_descriptor(devices[i], &descriptor) == LIBUSB_SUCCESS &&
            descriptor.idVendor == 0x045e && descriptor.idProduct == 0x0b12) {
            target = devices[i];
            ++matching;
        }
    }
    if (matching != 1) {
        printf("Expected one 045e:0b12 controller, found %d. No device changed.\n", matching);
        goto cleanup;
    }
    // Validate the exact gamepad interface/endpoints before any driver changes.
    struct libusb_config_descriptor *configuration = NULL;
    bool has_input = false, has_output = false;
    if (libusb_get_active_config_descriptor(target, &configuration) == LIBUSB_SUCCESS) {
        for (int i = 0; i < configuration->bNumInterfaces; ++i) {
            const struct libusb_interface *interface = &configuration->interface[i];
            for (int j = 0; j < interface->num_altsetting; ++j) {
                const struct libusb_interface_descriptor *alt = &interface->altsetting[j];
                if (alt->bInterfaceNumber != 0 || alt->bAlternateSetting != 0 ||
                    alt->bInterfaceClass != 0xff || alt->bInterfaceSubClass != 0x47 ||
                    alt->bInterfaceProtocol != 0xd0) continue;
                for (int k = 0; k < alt->bNumEndpoints; ++k) {
                    const struct libusb_endpoint_descriptor *ep = &alt->endpoint[k];
                    if ((ep->bmAttributes & 3) != LIBUSB_TRANSFER_TYPE_INTERRUPT || ep->wMaxPacketSize != 64) continue;
                    if (ep->bEndpointAddress == 0x82) has_input = true;
                    if (ep->bEndpointAddress == 0x02) has_output = true;
                }
            }
        }
        libusb_free_config_descriptor(configuration);
    }
    if (!has_input || !has_output) { puts("Unexpected endpoints. No device changed."); goto cleanup; }
    result = libusb_open(target, &handle);
    printf("open: %s (%d)\n", libusb_error_name(result), result);
    if (result != LIBUSB_SUCCESS) goto cleanup;
    result = libusb_kernel_driver_active(handle, 0);
    printf("original driver active: %d\n", result);
    if (result != 1) { puts("Expected Apple's attached driver; refusing ambiguous capture."); goto cleanup; }

    // The USB-capture call may itself re-enumerate the controller. No separate
    // reset, firmware write, driver install, or persistent system change.
    double started = now();
    alarm(30);
    puts("CAPTURE_BEGIN: 30-second maximum; controller input temporarily unavailable to macOS.");
    result = libusb_detach_kernel_driver(handle, 0);
    printf("capture: %s (%d)\n", libusb_error_name(result), result);
    if (result != LIBUSB_SUCCESS) goto cleanup;
    captured = true;
    if (stopping) goto cleanup;
    result = libusb_claim_interface(handle, 0);
    printf("claim interface 0: %s (%d)\n", libusb_error_name(result), result);
    if (result != LIBUSB_SUCCESS) goto cleanup;
    claimed = true;

    // Wake the input stream after re-enumeration. No rumble, LED, audio,
    // authentication, or firmware commands are sent.
    unsigned char wake[] = {0x05, 0x20, 0x01, 0x01, 0x00};
    int sent = 0;
    result = libusb_interrupt_transfer(handle, 0x02, wake, sizeof(wake), &sent, 500);
    printf("wake input: %s (%d), bytes=%d\n", libusb_error_name(result), result, sent);
    if (result != LIBUSB_SUCCESS || sent != sizeof(wake)) goto cleanup;
    puts("READY: tap Share three times, hold Share two seconds, then tap A once.");
    unsigned reports = 0, full_reports = 0, candidate_edges = 0;
    int previous_share = 0;
    while (!stopping && now() - started < 30 && reports < 15000) {
        unsigned char buffer[64] = {0};
        int length = 0;
        result = libusb_interrupt_transfer(handle, 0x82, buffer, sizeof(buffer), &length, 250);
        if (result == LIBUSB_ERROR_TIMEOUT) continue;
        if (result != LIBUSB_SUCCESS) {
            printf("read: %s (%d)\n", libusb_error_name(result), result);
            break;
        }
        ++reports;
        printf("%.3f len=%d hex=", now() - started, length);
        for (int i = 0; i < length; ++i) printf("%02x", buffer[i]);
        putchar('\n');
        // Candidate field for the tested 44-byte GIP payload; raw bytes remain
        // the evidence. Physical confirmation is required before app integration.
        if (length >= 48 && buffer[0] == 0x20 && buffer[3] == 44) {
            ++full_reports;
            int share = buffer[22] & 1;
            if (share != previous_share) {
                printf("SHARE_CANDIDATE %.3f %s byte22=%02x\n", now() - started,
                       share ? "DOWN" : "UP", buffer[22]);
                previous_share = share;
                ++candidate_edges;
            }
        }
    }
    printf("SUMMARY reports=%u full48=%u shareCandidateEdges=%u elapsed=%.3f\n",
           reports, full_reports, candidate_edges, now() - started);
    exit_code = 0;

cleanup:
    alarm(0);
    if (claimed) {
        result = libusb_release_interface(handle, 0);
        printf("release interface: %s (%d)\n", libusb_error_name(result), result);
        if (result != LIBUSB_SUCCESS) exit_code = 4;
    }
    if (captured) {
        result = libusb_attach_kernel_driver(handle, 0);
        printf("restore Apple driver: %s (%d)\n", libusb_error_name(result), result);
        if (result != LIBUSB_SUCCESS) {
            puts("RESTORE_FAILED: unplug and reconnect the controller.");
            exit_code = 5;
        }
    }
    if (handle) libusb_close(handle);
    if (devices) libusb_free_device_list(devices, 1);
    libusb_exit(context);
    printf("FINISHED exit=%d\n", exit_code);
    return exit_code;
}
