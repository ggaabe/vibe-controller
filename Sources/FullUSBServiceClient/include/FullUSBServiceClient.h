#pragma once

// Returns an owned session fd, or -1 with a diagnostic. Completion is called
// exactly once; early validation errors may return synchronously. No password
// or shell command is accepted.
void VibeUSBRequestSession(const char *service,
                          void (^completion)(int fd, const char *error));
