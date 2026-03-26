"""UART Echo Test: send bytes, check that they come back identical."""
import serial
import time
import sys

PORT = "COM4"
BAUD = 115200
TIMEOUT = 2.0

def test_echo():
    ser = serial.Serial(PORT, BAUD, timeout=TIMEOUT)
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    time.sleep(0.1)

    # Test patterns
    tests = [
        ("single 0x55",       bytes([0x55])),
        ("single 0xAA",       bytes([0xAA])),
        ("single 0x00",       bytes([0x00])),
        ("single 0xFF",       bytes([0xFF])),
        ("single 0x01",       bytes([0x01])),
        ("single 0x80",       bytes([0x80])),
        ("single 0x42",       bytes([0x42])),
        ("ASCII 'Hello'",     b"Hello"),
        ("all printable",     bytes(range(0x20, 0x7F))),
        ("sequential 0-255",  bytes(range(256))),
    ]

    passed = 0
    failed = 0

    print(f"=== UART Echo Test on {PORT} @ {BAUD} ===\n")

    for name, data in tests:
        ser.reset_input_buffer()
        time.sleep(0.05)

        ser.write(data)
        ser.flush()

        # Read back
        response = b""
        deadline = time.time() + TIMEOUT
        while len(response) < len(data) and time.time() < deadline:
            chunk = ser.read(len(data) - len(response))
            if chunk:
                response += chunk

        if response == data:
            passed += 1
            if len(data) <= 8:
                print(f"  PASS  {name}: sent {data.hex(' ')}, got {response.hex(' ')}")
            else:
                print(f"  PASS  {name}: {len(data)} bytes OK")
        else:
            failed += 1
            if len(data) <= 16:
                print(f"  FAIL  {name}: sent {data.hex(' ')}, got {response.hex(' ')} ({len(response)}/{len(data)} bytes)")
            else:
                # Show first divergence
                print(f"  FAIL  {name}: {len(response)}/{len(data)} bytes received")
                for i in range(min(len(response), len(data))):
                    if i >= len(response) or response[i] != data[i]:
                        got = f"0x{response[i]:02x}" if i < len(response) else "MISSING"
                        print(f"        first diff at byte {i}: expected 0x{data[i]:02x}, got {got}")
                        # Show a few more
                        end = min(i + 8, min(len(response), len(data)))
                        if end > i + 1:
                            exp_s = ' '.join(f'{data[j]:02x}' for j in range(i, min(i+8, len(data))))
                            got_s = ' '.join(f'{response[j]:02x}' for j in range(i, min(i+8, len(response))))
                            print(f"        expected: {exp_s}")
                            print(f"        got:      {got_s}")
                        break

        # Small gap between tests
        time.sleep(0.1)

    ser.close()

    print(f"\n=== Results: {passed} passed, {failed} failed out of {passed + failed} ===")
    return failed == 0

if __name__ == "__main__":
    ok = test_echo()
    sys.exit(0 if ok else 1)
