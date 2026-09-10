#import "FullUSBServiceClient.h"
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <xpc/xpc.h>
#include <unistd.h>

void VibeUSBRequestSession(const char *service, void (^completion)(int, const char *)) {
    // Defense in depth: even a direct caller in a public build cannot contact
    // a previously installed helper. Exclusive USB capture is Dev-only.
    NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
    NSString *expected = [identifier stringByAppendingString:@".usb-service"];
    if (![identifier isEqualToString:@"com.vibe-controller.app.dev"] ||
        ![expected isEqualToString:@(service)]) {
        completion(-1, "Full USB requires the signed Vibe Controller Dev bundle."); return;
    }
    SecCodeRef own = NULL;
    SecStaticCodeRef code = NULL;
    CFDictionaryRef info = NULL;
    NSString *team = nil;
    if (!SecCodeCopySelf(kSecCSDefaultFlags, &own) &&
        !SecCodeCopyStaticCode(own, kSecCSDefaultFlags, &code) &&
        !SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info)) {
        team = [(__bridge NSDictionary *)info objectForKey:(__bridge NSString *)kSecCodeInfoTeamIdentifier];
    }
    if (info) CFRelease(info);
    if (code) CFRelease(code);
    if (own) CFRelease(own);
    if (!team.length || [team rangeOfCharacterFromSet:
        [[NSCharacterSet alphanumericCharacterSet] invertedSet]].location != NSNotFound) {
        completion(-1, "The app has no valid signing team."); return;
    }
    dispatch_queue_t queue = dispatch_queue_create("com.vibe-controller.usb-approval-client", DISPATCH_QUEUE_SERIAL);
    xpc_connection_t connection = xpc_connection_create_mach_service(service, queue, XPC_CONNECTION_MACH_SERVICE_PRIVILEGED);
    NSString *requirement = [NSString stringWithFormat:
        @"anchor apple generic and certificate leaf[subject.OU] = \"%@\" and identifier \"%@\"", team, expected];
    if (xpc_connection_set_peer_code_signing_requirement(connection, requirement.UTF8String)) {
        completion(-1, "Could not verify the USB helper identity."); return;
    }
    __block BOOL finished = NO;
    void (^finish)(int, const char *) = ^(int fd, const char *error) {
        if (finished) { if (fd >= 0) close(fd); return; }
        finished = YES;
        xpc_connection_set_event_handler(connection, ^(xpc_object_t event) { (void)event; });
        xpc_connection_cancel(connection);
        completion(fd, error);
    };
    xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
        if (xpc_get_type(event) == XPC_TYPE_ERROR) {
            finish(-1, "USB helper unavailable. Check its approval in Login Items & Extensions.");
        }
    });
    xpc_connection_resume(connection);
    xpc_object_t request = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(request, "command", "start");
    xpc_dictionary_set_uint64(request, "version", 1);
    xpc_connection_send_message_with_reply(connection, request, queue, ^(xpc_object_t reply) {
        if (xpc_get_type(reply) != XPC_TYPE_DICTIONARY) {
            finish(-1, "Could not contact the approved USB helper."); return;
        }
        const char *error = xpc_dictionary_get_string(reply, "error");
        if (error) { finish(-1, error); return; }
        int fd = xpc_dictionary_dup_fd(reply, "session");
        finish(fd, fd < 0 ? "The USB helper returned no session." : "");
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), queue, ^{
        finish(-1, "USB helper did not respond. Check its approval in System Settings.");
    });
}
