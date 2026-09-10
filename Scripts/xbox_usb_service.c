// Launch-on-demand SMAppService broker. Only the matching, Apple-signed app
// from our signing team may request a session. No paths or commands to execute.
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include <dispatch/dispatch.h>
#include <xpc/xpc.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef VIBE_USB_APP_ID
#error VIBE_USB_APP_ID must match the packaged application
#endif
#define SERVICE VIBE_USB_APP_ID ".usb-service"
int vibe_usb_run_session(int fd);
void vibe_usb_session_request_stop(void);

static bool active;
static dispatch_queue_t session_queue;

static void respond(xpc_object_t request, const char *error, int fd) {
    xpc_object_t reply = xpc_dictionary_create_reply(request);
    if (!reply) return;
    if (error) xpc_dictionary_set_string(reply, "error", error);
    else xpc_dictionary_set_fd(reply, "session", fd);
    xpc_connection_send_message(xpc_dictionary_get_remote_connection(request), reply);
    xpc_release(reply);
}

static void handle_request(xpc_connection_t peer, xpc_object_t request) {
    if (xpc_get_type(request) != XPC_TYPE_DICTIONARY) return;
    uid_t console_uid = 0; gid_t console_gid = 0;
    CFStringRef user = SCDynamicStoreCopyConsoleUser(NULL, &console_uid, &console_gid);
    if (user) CFRelease(user);
    if (!console_uid || xpc_connection_get_euid(peer) != console_uid) {
        respond(request, "Full USB is available only to the logged-in console user.", -1); return;
    }
    const char *command = xpc_dictionary_get_string(request, "command");
    if (!command || strcmp(command, "start") || xpc_dictionary_get_uint64(request, "version") != 1 ||
        xpc_dictionary_get_count(request) != 2) {
        respond(request, "Unsupported USB service request.", -1); return;
    }
    if (active) { respond(request, "A USB session is already active. Stop it before retrying.", -1); return; }
    int pair[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, pair)) {
        respond(request, "Could not create a private USB connection.", -1); return;
    }
    for (int i = 0; i < 2; ++i) {
        int one = 1;
        setsockopt(pair[i], SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
        fcntl(pair[i], F_SETFD, FD_CLOEXEC);
        fcntl(pair[i], F_SETFL, O_NONBLOCK);
    }
    active = true;
    respond(request, NULL, pair[0]);
    close(pair[0]);
    int session_fd = pair[1];
    dispatch_async(session_queue, ^{
        vibe_usb_run_session(session_fd); // Owns/closes fd. Watchdog ends abandoned sessions.
        dispatch_async(dispatch_get_main_queue(), ^{ active = false; });
    });
}

int main(void) {
    if (geteuid() != 0) { fputs("Requires the approved macOS USB service.\n", stderr); return 2; }
    SecCodeRef own = NULL; SecStaticCodeRef code = NULL; CFDictionaryRef info = NULL;
    char team[64] = {0};
    static char requirement[512];
    if (SecCodeCopySelf(kSecCSDefaultFlags, &own) ||
        SecCodeCopyStaticCode(own, kSecCSDefaultFlags, &code) ||
        SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info)) return 3;
    CFStringRef team_ref = CFDictionaryGetValue(info, kSecCodeInfoTeamIdentifier);
    bool valid = team_ref && CFStringGetCString(team_ref, team, sizeof(team), kCFStringEncodingUTF8);
    CFRelease(info); CFRelease(code); CFRelease(own);
    if (!valid || strspn(team, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789") != strlen(team)) return 3;
    snprintf(requirement, sizeof(requirement),
        "anchor apple generic and certificate leaf[subject.OU] = \"%s\" and identifier \"%s\"", team, VIBE_USB_APP_ID);
    session_queue = dispatch_queue_create(SERVICE ".capture", DISPATCH_QUEUE_SERIAL);
    signal(SIGTERM, SIG_IGN);
    dispatch_source_t termination = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(termination, ^{
        vibe_usb_session_request_stop();
        dispatch_async(session_queue, ^{ exit(0); });
    });
    dispatch_resume(termination);
    // Let launchd relaunch the current bundled binary on the next request.
    // In particular, do not keep an obsolete helper resident after an app update.
    dispatch_source_t idle = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(idle, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), 60 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(idle, ^{ if (!active) exit(0); });
    dispatch_resume(idle);
    xpc_connection_t listener = xpc_connection_create_mach_service(SERVICE, dispatch_get_main_queue(), XPC_CONNECTION_MACH_SERVICE_LISTENER);
    // Apply the requirement once to each incoming peer, before it is resumed.
    // Every request message is checked by XPC, not merely a PID at connection time.
    xpc_connection_set_event_handler(listener, ^(xpc_object_t object) {
        if (xpc_get_type(object) != XPC_TYPE_CONNECTION) return;
        xpc_connection_t peer = (xpc_connection_t)object;
        xpc_connection_set_target_queue(peer, dispatch_get_main_queue());
        if (xpc_connection_set_peer_code_signing_requirement(peer, requirement)) { xpc_connection_cancel(peer); return; }
        xpc_connection_set_event_handler(peer, ^(xpc_object_t request) { handle_request(peer, request); });
        xpc_connection_resume(peer);
    });
    xpc_connection_resume(listener);
    dispatch_main();
}
