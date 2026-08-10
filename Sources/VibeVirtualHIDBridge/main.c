#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

// The protocol below is intentionally small and dependency-free. It is the
// documented wire format used by Karabiner-DriverKit-VirtualHIDDevice 8.2.0.
// Vibe Controller talks only to this helper over an inherited stdin pipe. The
// helper, in turn, is the root peer accepted by Karabiner's protected daemon.

static const char *socket_path =
    "/Library/Application Support/org.pqrs/tmp/rootonly/"
    "karabiner_virtual_hid_device_service.sock";
static const char *daemon_path =
    "/Library/Application Support/org.pqrs/"
    "Karabiner-DriverKit-VirtualHIDDevice/Applications/"
    "Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/"
    "Karabiner-VirtualHIDDevice-Daemon";

enum message_type {
  message_heartbeat = 0,
  message_user_data = 1,
  message_health_check = 2,
  message_health_check_response = 3,
  message_request = 4,
  message_response = 5,
};

enum service_request {
  request_keyboard_initialize = 0,
  request_keyboard_terminate = 1,
  request_keyboard_reset = 2,
  request_pointing_initialize = 3,
  request_pointing_terminate = 4,
  request_pointing_reset = 5,
  request_post_keyboard = 6,
  request_post_consumer = 7,
  request_post_apple_keyboard = 8,
  request_post_apple_top_case = 9,
  request_post_generic_desktop = 10,
  request_post_pointing = 11,
};

_Static_assert(request_post_apple_keyboard == 8,
               "Karabiner protocol v7 Apple keyboard request changed");
_Static_assert(request_post_apple_top_case == 9,
               "Karabiner protocol v7 Apple top-case request changed");

enum bridge_command_kind {
  command_pointing = 1,
  command_keyboard = 2,
  command_function = 3,
  command_quit = 4,
};

struct __attribute__((packed)) bridge_command {
  uint8_t kind;
  int8_t x;
  int8_t y;
  int8_t vertical_wheel;
  int8_t horizontal_wheel;
  uint8_t modifiers;
  uint16_t usage;
  uint32_t buttons;
  uint8_t reserved[4];
};

_Static_assert(sizeof(struct bridge_command) == 16,
               "bridge command must remain a 16-byte wire record");

static int service_socket = -1;
static uint64_t next_request_id = 1;
static bool driver_activated = false;
static bool driver_connected = false;
static bool driver_version_mismatched = false;
static bool keyboard_ready = false;
static bool pointing_ready = false;
static bool status_reported = false;

static double monotonic_seconds(void) {
  struct timespec value;
  clock_gettime(CLOCK_MONOTONIC, &value);
  return (double)value.tv_sec + (double)value.tv_nsec / 1000000000.0;
}

static void encode_u64_be(uint8_t output[8], uint64_t value) {
  for (size_t index = 0; index < 8; ++index) {
    output[index] = (uint8_t)((value >> (56 - index * 8)) & 0xff);
  }
}

static uint64_t decode_u64_be(const uint8_t input[8]) {
  uint64_t value = 0;
  for (size_t index = 0; index < 8; ++index) {
    value = (value << 8) | input[index];
  }
  return value;
}

static bool write_all(int fd, const uint8_t *bytes, size_t count) {
  size_t offset = 0;
  while (offset < count) {
    ssize_t written = write(fd, bytes + offset, count - offset);
    if (written > 0) {
      offset += (size_t)written;
      continue;
    }
    if (written < 0 && errno == EINTR) {
      continue;
    }
    return false;
  }
  return true;
}

static bool send_frame(uint8_t type, uint64_t request_id,
                       const uint8_t *payload, size_t payload_size) {
  const bool has_request_id =
      type == message_request || type == message_response;
  size_t body_size = 1 + (has_request_id ? 8 : 0) + payload_size;
  if (body_size > 2048) {
    return false;
  }

  uint8_t frame[2052];
  uint32_t encoded_size = htonl((uint32_t)body_size);
  memcpy(frame, &encoded_size, sizeof(encoded_size));
  frame[4] = type;
  size_t offset = 5;

  if (has_request_id) {
    encode_u64_be(frame + offset, request_id);
    offset += 8;
  }
  if (payload_size > 0) {
    memcpy(frame + offset, payload, payload_size);
  }

  return write_all(service_socket, frame, 4 + body_size);
}

static bool send_service_request(uint8_t request, const uint8_t *report,
                                 size_t report_size) {
  uint8_t payload[128];
  if (report_size + 3 > sizeof(payload)) {
    return false;
  }

  const uint16_t protocol_version = 7;
  memcpy(payload, &protocol_version, sizeof(protocol_version));
  payload[2] = request;
  if (report_size > 0) {
    memcpy(payload + 3, report, report_size);
  }

  return send_frame(message_request, next_request_id++, payload,
                    report_size + 3);
}

static int connect_to_service(void) {
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    return -1;
  }

  struct sockaddr_un address;
  memset(&address, 0, sizeof(address));
  address.sun_family = AF_UNIX;
  if (strlen(socket_path) >= sizeof(address.sun_path)) {
    close(fd);
    errno = ENAMETOOLONG;
    return -1;
  }
  strlcpy(address.sun_path, socket_path, sizeof(address.sun_path));

  if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
    close(fd);
    return -1;
  }
  return fd;
}

static bool start_daemon_if_needed(void) {
  service_socket = connect_to_service();
  if (service_socket >= 0) {
    return true;
  }

  if (access(daemon_path, X_OK) != 0) {
    dprintf(STDERR_FILENO, "ERROR driver daemon is not installed\n");
    return false;
  }

  pid_t child = fork();
  if (child < 0) {
    return false;
  }
  if (child == 0) {
    setsid();
    int null_fd = open("/dev/null", O_RDWR);
    if (null_fd >= 0) {
      dup2(null_fd, STDIN_FILENO);
      dup2(null_fd, STDOUT_FILENO);
      dup2(null_fd, STDERR_FILENO);
      if (null_fd > STDERR_FILENO) {
        close(null_fd);
      }
    }
    execl(daemon_path, daemon_path, (char *)NULL);
    _exit(127);
  }

  for (int attempt = 0; attempt < 80; ++attempt) {
    usleep(100000);
    service_socket = connect_to_service();
    if (service_socket >= 0) {
      return true;
    }
  }

  dprintf(STDERR_FILENO, "ERROR driver daemon did not create its socket\n");
  return false;
}

static CFDictionaryRef copy_signing_information(SecCodeRef code) {
  CFDictionaryRef information = NULL;
  if (SecCodeCopySigningInformation(code, kSecCSSigningInformation,
                                    &information) != errSecSuccess) {
    return NULL;
  }
  return information;
}

static bool parent_is_authorized(void) {
  pid_t parent_pid = getppid();
  CFNumberRef pid_number =
      CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &parent_pid);
  if (pid_number == NULL) {
    return false;
  }

  const void *keys[] = {kSecGuestAttributePid};
  const void *values[] = {pid_number};
  CFDictionaryRef attributes = CFDictionaryCreate(
      kCFAllocatorDefault, keys, values, 1, &kCFTypeDictionaryKeyCallBacks,
      &kCFTypeDictionaryValueCallBacks);
  CFRelease(pid_number);
  if (attributes == NULL) {
    return false;
  }

  SecCodeRef parent_code = NULL;
  OSStatus parent_status = SecCodeCopyGuestWithAttributes(
      NULL, attributes, kSecCSDefaultFlags, &parent_code);
  CFRelease(attributes);
  if (parent_status != errSecSuccess || parent_code == NULL) {
    return false;
  }

  if (SecCodeCheckValidity(parent_code, kSecCSStrictValidate, NULL) !=
      errSecSuccess) {
    CFRelease(parent_code);
    return false;
  }

  SecCodeRef self_code = NULL;
  if (SecCodeCopySelf(kSecCSDefaultFlags, &self_code) != errSecSuccess ||
      self_code == NULL) {
    CFRelease(parent_code);
    return false;
  }

  CFDictionaryRef parent_info = copy_signing_information(parent_code);
  CFDictionaryRef self_info = copy_signing_information(self_code);
  CFRelease(parent_code);
  CFRelease(self_code);
  if (parent_info == NULL || self_info == NULL) {
    if (parent_info != NULL) CFRelease(parent_info);
    if (self_info != NULL) CFRelease(self_info);
    return false;
  }

  CFStringRef parent_identifier =
      CFDictionaryGetValue(parent_info, kSecCodeInfoIdentifier);
  CFStringRef parent_team =
      CFDictionaryGetValue(parent_info, kSecCodeInfoTeamIdentifier);
  CFStringRef self_team =
      CFDictionaryGetValue(self_info, kSecCodeInfoTeamIdentifier);

  bool authorized =
      parent_identifier != NULL && parent_team != NULL && self_team != NULL &&
      CFEqual(parent_identifier, CFSTR("com.vibe-controller.app")) &&
      CFEqual(parent_team, self_team);

  CFRelease(parent_info);
  CFRelease(self_info);
  return authorized;
}

static bool become_root(void) {
  if (geteuid() != 0) {
    dprintf(STDERR_FILENO,
            "ERROR privileged helper is not installed setuid-root\n");
    return false;
  }
  if (getuid() != 0 && !parent_is_authorized()) {
    dprintf(STDERR_FILENO, "ERROR unauthorized parent process\n");
    return false;
  }
  if (setgid(0) != 0 || setuid(0) != 0) {
    dprintf(STDERR_FILENO, "ERROR could not establish root identity\n");
    return false;
  }
  return true;
}

static bool initialize_devices(void) {
  uint64_t keyboard_parameters[3] = {0x16c0, 0x27db, 33};
  return send_service_request(request_keyboard_initialize,
                              (const uint8_t *)keyboard_parameters,
                              sizeof(keyboard_parameters)) &&
         send_service_request(request_pointing_initialize, NULL, 0);
}

static bool post_pointing(int8_t x, int8_t y, int8_t vertical_wheel,
                          int8_t horizontal_wheel, uint32_t buttons) {
  uint8_t report[8];
  memcpy(report, &buttons, sizeof(buttons));
  report[4] = (uint8_t)x;
  report[5] = (uint8_t)y;
  report[6] = (uint8_t)vertical_wheel;
  report[7] = (uint8_t)horizontal_wheel;
  return send_service_request(request_post_pointing, report, sizeof(report));
}

static bool post_keyboard(uint8_t modifiers, uint16_t usage) {
  uint8_t report[67];
  memset(report, 0, sizeof(report));
  report[0] = 1;
  report[1] = modifiers;
  memcpy(report + 3, &usage, sizeof(usage));
  return send_service_request(request_post_keyboard, report, sizeof(report));
}

static bool post_function(uint16_t usage) {
  uint8_t report[65];
  memset(report, 0, sizeof(report));
  report[0] = 3;
  memcpy(report + 1, &usage, sizeof(usage));
  return send_service_request(request_post_apple_top_case, report,
                              sizeof(report));
}

static void print_status_payload(const uint8_t *payload, size_t size) {
  if (size == 0) {
    return;
  }
  bool previous_keyboard_ready = keyboard_ready;
  bool previous_pointing_ready = pointing_ready;
  bool previous_driver_activated = driver_activated;
  bool previous_driver_connected = driver_connected;
  bool previous_driver_version_mismatched = driver_version_mismatched;
  for (size_t offset = 0; offset + 1 < size; offset += 2) {
    uint8_t response = payload[offset];
    bool value = payload[offset + 1] != 0;
    if (response == 1) {
      driver_activated = value;
    } else if (response == 2) {
      driver_connected = value;
    } else if (response == 3) {
      driver_version_mismatched = value;
    } else if (response == 4) {
      keyboard_ready = value;
    } else if (response == 5) {
      pointing_ready = value;
    }
  }
  if (!status_reported || previous_driver_activated != driver_activated ||
      previous_driver_connected != driver_connected ||
      previous_driver_version_mismatched != driver_version_mismatched ||
      previous_keyboard_ready != keyboard_ready ||
      previous_pointing_ready != pointing_ready) {
    dprintf(STDOUT_FILENO,
            "STATUS activated=%d connected=%d mismatch=%d keyboard=%d pointing=%d\n",
            driver_activated ? 1 : 0, driver_connected ? 1 : 0,
            driver_version_mismatched ? 1 : 0, keyboard_ready ? 1 : 0,
            pointing_ready ? 1 : 0);
    status_reported = true;
  }
}

static bool handle_socket_frame(const uint8_t *body, size_t body_size) {
  if (body_size == 0) {
    return false;
  }
  uint8_t type = body[0];
  if (type == message_health_check) {
    return send_frame(message_health_check_response, 0, NULL, 0);
  }
  if (type != message_request && type != message_response) {
    return true;
  }
  if (body_size < 9) {
    return false;
  }

  uint64_t request_id = decode_u64_be(body + 1);
  const uint8_t *payload = body + 9;
  size_t payload_size = body_size - 9;
  print_status_payload(payload, payload_size);

  if (type == message_request) {
    return send_frame(message_response, request_id, NULL, 0);
  }
  return true;
}

static bool consume_socket_bytes(uint8_t *buffer, size_t *buffer_size) {
  size_t offset = 0;
  while (*buffer_size - offset >= 4) {
    uint32_t encoded_size;
    memcpy(&encoded_size, buffer + offset, sizeof(encoded_size));
    size_t body_size = ntohl(encoded_size);
    if (body_size == 0 || body_size > 2048) {
      return false;
    }
    if (*buffer_size - offset < body_size + 4) {
      break;
    }
    if (!handle_socket_frame(buffer + offset + 4, body_size)) {
      return false;
    }
    offset += body_size + 4;
  }

  if (offset > 0) {
    memmove(buffer, buffer + offset, *buffer_size - offset);
    *buffer_size -= offset;
  }
  return true;
}

static bool handle_command(const struct bridge_command *command) {
  switch (command->kind) {
    case command_pointing:
      return post_pointing(command->x, command->y, command->vertical_wheel,
                           command->horizontal_wheel, command->buttons);
    case command_keyboard:
      return post_keyboard(command->modifiers, command->usage);
    case command_function:
      return post_function(command->usage);
    case command_quit:
      post_pointing(0, 0, 0, 0, 0);
      post_keyboard(0, 0);
      post_function(0);
      return false;
    default:
      return true;
  }
}

int main(int argc, char **argv) {
  signal(SIGPIPE, SIG_IGN);
  bool demo_right = argc == 2 && strcmp(argv[1], "--demo-right") == 0;

  if (!become_root() || !start_daemon_if_needed()) {
    return 1;
  }
  if (!initialize_devices()) {
    dprintf(STDERR_FILENO, "ERROR could not initialize virtual devices\n");
    return 1;
  }

  dprintf(STDOUT_FILENO, "CONNECTED\n");

  uint8_t socket_buffer[8192];
  size_t socket_buffer_size = 0;
  uint8_t command_buffer[sizeof(struct bridge_command)];
  size_t command_buffer_size = 0;
  double last_heartbeat = monotonic_seconds();
  double demo_deadline = monotonic_seconds() + 20.0;
  double next_demo_report = 0;
  int demo_reports_remaining = 1250;
  bool running = true;

  while (running) {
    struct pollfd descriptors[2] = {
        {.fd = service_socket, .events = POLLIN},
        {.fd = demo_right ? -1 : STDIN_FILENO, .events = POLLIN},
    };
    int result = poll(descriptors, 2, demo_right ? 8 : 250);
    if (result < 0 && errno != EINTR) {
      break;
    }

    if (descriptors[0].revents & (POLLERR | POLLHUP | POLLNVAL)) {
      break;
    }
    if (descriptors[0].revents & POLLIN) {
      ssize_t count = read(service_socket,
                           socket_buffer + socket_buffer_size,
                           sizeof(socket_buffer) - socket_buffer_size);
      if (count <= 0) {
        break;
      }
      socket_buffer_size += (size_t)count;
      if (!consume_socket_bytes(socket_buffer, &socket_buffer_size)) {
        break;
      }
    }

    if (!demo_right && (descriptors[1].revents & (POLLERR | POLLHUP | POLLNVAL))) {
      break;
    }
    if (!demo_right && (descriptors[1].revents & POLLIN)) {
      ssize_t count = read(STDIN_FILENO,
                           command_buffer + command_buffer_size,
                           sizeof(command_buffer) - command_buffer_size);
      if (count <= 0) {
        break;
      }
      command_buffer_size += (size_t)count;
      if (command_buffer_size == sizeof(struct bridge_command)) {
        running = handle_command((const struct bridge_command *)command_buffer);
        command_buffer_size = 0;
      }
    }

    double now = monotonic_seconds();
    if (now - last_heartbeat >= 3.0) {
      if (!send_frame(message_heartbeat, 0, NULL, 0)) {
        break;
      }
      last_heartbeat = now;
    }

    if (demo_right) {
      if (pointing_ready && next_demo_report == 0) {
        next_demo_report = now + 0.5;
        dprintf(STDOUT_FILENO, "DEMO starting sustained rightward motion\n");
      }
      if (next_demo_report > 0 && now >= next_demo_report &&
          demo_reports_remaining > 0) {
        if (!post_pointing(8, 0, 0, 0, 0)) {
          break;
        }
        --demo_reports_remaining;
        next_demo_report += 0.008;
      }
      if (demo_reports_remaining == 0) {
        dprintf(STDOUT_FILENO, "DEMO complete\n");
        break;
      }
      if (now >= demo_deadline) {
        dprintf(STDERR_FILENO,
                "ERROR virtual pointing device did not become ready\n");
        break;
      }
    }
  }

  post_pointing(0, 0, 0, 0, 0);
  post_keyboard(0, 0);
  post_function(0);
  close(service_socket);
  return running || demo_right ? 0 : 0;
}
