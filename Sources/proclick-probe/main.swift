// proclick-probe: hardware checks and recovery for the Razer Pro Click Mini.
import Foundation
import RazerBLE

let usage = """
    usage: proclick-probe <command>
      read                 print the mouse's DPI stages, sleep timer and battery
    """

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func connect() async -> (CoreBluetoothTransport, MouseClient) {
    let transport = CoreBluetoothTransport()
    do {
        try await transport.waitUntilConnected(timeout: 15)
    } catch {
        fail("Pro Click Mini not found over Bluetooth. Is it on, paired and connected?")
    }
    return (transport, MouseClient(transport: transport))
}

func describe(_ s: MouseState) -> String {
    let stages = s.dpi.stages.map { String($0.x) }.joined(separator: ",")
    return """
        dpi: active=\(s.dpi.activeID) stages=\(stages) marker=\(s.dpi.marker)
        sleep: \(s.sleepSeconds)s
        """
}

let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "read":
    let (_, client) = await connect()
    do {
        print(describe(try await client.readState()))
        let raw = try await client.readBatteryRaw()
        print("battery: \(raw)/255 (\(Int((Double(raw) * 100 / 255).rounded()))%)")
    } catch {
        fail("read failed: \(error)")
    }
default:
    fail(usage, code: 2)
}
