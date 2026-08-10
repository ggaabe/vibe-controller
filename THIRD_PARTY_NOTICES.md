# Third-Party Notices

Vibe Controller's optional Virtual Hardware Support uses
[Karabiner-DriverKit-VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice),
version 8.2.0, by Fumihiko Takayama and contributors.

The Karabiner-DriverKit-VirtualHIDDevice project is dedicated to the public
domain under CC0. Its header-only client code is distributed under the Boost
Software License 1.0. Vibe Controller does not modify the signed DriverKit
package; the build script verifies its pinned SHA-256 checksum and Apple's
notarization before including it in the local support installer.
