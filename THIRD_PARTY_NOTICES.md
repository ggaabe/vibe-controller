# Third-Party Notices

Vibe Controller's optional Virtual Hardware Support uses
[Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice),
version 8.2.0, by Fumihiko Takayama and contributors.

The Karabiner-DriverKit-VirtualHIDDevice project is dedicated to the public
domain under CC0. Its header-only client code is distributed under the Boost
Software License 1.0. Vibe Controller does not modify the signed DriverKit
package; the build script verifies its pinned SHA-256 checksum and Apple's
notarization before including it in the local support installer.

## libusb

The optional Full USB input session bundles an unmodified dynamic library from
[libusb 1.0.30](https://github.com/libusb/libusb/releases/tag/v1.0.30), copyright
the libusb contributors, under the GNU Lesser General Public License 2.1 or later.
The license is included in the app at `Contents/Resources/Licenses/libusb-LGPL-2.1.txt`.
Corresponding source is bundled alongside the license as
`libusb-1.0.30-source.tar.bz2` and available at that versioned upstream link; the helper's
source and rebuild instructions are in `Scripts/xbox_usb_session.c` and
`Scripts/package_xbox_usb_session.sh`. libusb is dynamically linked, not statically
incorporated into Vibe Controller. You may modify/replace and re-sign this local
build for your own use; reverse engineering to debug modifications to this
library is permitted under its license. Users do not need Homebrew or libusb
installed separately.
