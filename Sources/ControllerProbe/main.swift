import Foundation
import GameController

GCController.shouldMonitorBackgroundEvents = true

let center = NotificationCenter.default
let connectToken = center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { note in
    if let controller = note.object as? GCController {
        print("Controller connected: \(controller.vendorName ?? "Unknown")")
    }
}

defer {
    center.removeObserver(connectToken)
}

print("Waiting up to 5 seconds for Game Controller discovery...")
RunLoop.main.run(until: Date().addingTimeInterval(5))

let controllers = GCController.controllers()
print("Detected controllers: \(controllers.count)")
for controller in controllers {
    let batterySummary: String
    if let battery = controller.battery {
        batterySummary = String(format: "%.0f%% %@", battery.batteryLevel * 100, battery.batteryState.vibeDescription)
    } else {
        batterySummary = "n/a"
    }
    print("- \(controller.vendorName ?? "Unknown") | battery: \(batterySummary)")
}

guard let controller = GCController.current ?? controllers.first(where: { $0.extendedGamepad != nil }),
      let gamepad = controller.extendedGamepad else {
    print("No extended gamepad available after waiting.")
    exit(0)
}

print("Listening to \(controller.vendorName ?? "Unknown") for 10 seconds. Move sticks or press buttons.")

gamepad.valueChangedHandler = { _, element in
    let name = element.localizedName ?? String(describing: type(of: element))
    let left = gamepad.leftThumbstick
    let right = gamepad.rightThumbstick
    let pressed = [
        ("A", gamepad.buttonA.isPressed),
        ("B", gamepad.buttonB.isPressed),
        ("X", gamepad.buttonX.isPressed),
        ("Y", gamepad.buttonY.isPressed),
        ("LB", gamepad.leftShoulder.isPressed),
        ("RB", gamepad.rightShoulder.isPressed),
        ("LT", gamepad.leftTrigger.isPressed),
        ("RT", gamepad.rightTrigger.isPressed),
        ("View", gamepad.buttonOptions?.isPressed ?? false),
        ("Menu", gamepad.buttonMenu.isPressed),
    ]
    .filter(\.1)
    .map(\.0)
    .joined(separator: ", ")

    print(
        String(
            format: "%@ | left:(%.2f, %.2f) right:(%.2f, %.2f) pressed:[%@]",
            name,
            left.xAxis.value,
            left.yAxis.value,
            right.xAxis.value,
            right.yAxis.value,
            pressed
        )
    )
}

RunLoop.main.run(until: Date().addingTimeInterval(10))

private extension GCDeviceBattery.State {
    var vibeDescription: String {
        switch self {
        case .charging:
            return "charging"
        case .discharging:
            return "discharging"
        case .full:
            return "full"
        case .unknown:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }
}
