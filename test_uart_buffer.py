"""UART Buffer Stress Test: проверяет 4-байтный FIFO буфер на FPGA.

Тесты:
1. Одиночные байты (базовая проверка)
2. Burst 4 байта (заполнение буфера)
3. Burst 5+ байт (переполнение — 5-й может потеряться)
4. Быстрая последовательность коротких пакетов
5. Полный диапазон значений
"""
import serial
import time
import sys

PORT = "COM4"
BAUD = 115200
TIMEOUT = 2.0

def open_port():
    ser = serial.Serial(PORT, BAUD, timeout=TIMEOUT)
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    time.sleep(0.2)
    return ser

def test_single_bytes(ser):
    """Тест 1: одиночные байты с паузой — все должны пройти."""
    print("Test 1: Single bytes with pause")
    errors = 0
    for val in [0x00, 0x55, 0xAA, 0xFF, 0x01, 0x80]:
        ser.reset_input_buffer()
        time.sleep(0.01)
        ser.write(bytes([val]))
        ser.flush()
        resp = ser.read(1)
        if resp == bytes([val]):
            print(f"  PASS  0x{val:02x}")
        else:
            print(f"  FAIL  sent 0x{val:02x}, got {resp.hex() if resp else 'NOTHING'}")
            errors += 1
        time.sleep(0.05)
    return errors

def test_burst_4(ser):
    """Тест 2: burst 4 байта — точно в размер буфера."""
    print("Test 2: Burst of 4 bytes (exact buffer size)")
    ser.reset_input_buffer()
    time.sleep(0.05)
    data = bytes([0x11, 0x22, 0x33, 0x44])
    ser.write(data)
    ser.flush()
    resp = ser.read(4)
    if resp == data:
        print(f"  PASS  sent {data.hex(' ')}, got {resp.hex(' ')}")
        return 0
    else:
        print(f"  FAIL  sent {data.hex(' ')}, got {resp.hex(' ')} ({len(resp)} bytes)")
        return 1

def test_burst_overflow(ser):
    """Тест 3: burst 8 байт — переполнение FIFO. Ожидаем потерю байт."""
    print("Test 3: Burst of 8 bytes (overflow expected)")
    ser.reset_input_buffer()
    time.sleep(0.05)
    data = bytes([0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8])
    ser.write(data)
    ser.flush()
    time.sleep(0.5)  # ждём все ответы
    resp = ser.read(16)
    # При 115200 бод ~86 мкс/байт, TX FIFO 4 байта.
    # RX FIFO 4 байта — если хост шлёт 8 байт подряд,
    # UART RX принимает по 1 биту, так что реально буфер
    # не переполняется (каждый байт ~86 мкс, а чтение из FIFO ~нс)
    print(f"  Sent {len(data)} bytes, received {len(resp)} bytes")
    print(f"  Sent: {data.hex(' ')}")
    print(f"  Got:  {resp.hex(' ')}")
    if len(resp) >= 4:
        print(f"  INFO  At least 4 bytes received (buffer working)")
        return 0
    else:
        print(f"  FAIL  Less than 4 bytes received")
        return 1

def test_rapid_packets(ser):
    """Тест 4: 10 пакетов по 4 байта с минимальной паузой."""
    print("Test 4: 10 rapid 4-byte packets")
    ser.reset_input_buffer()
    time.sleep(0.05)

    all_data = b""
    for i in range(10):
        pkt = bytes([i*4, i*4+1, i*4+2, i*4+3])
        ser.write(pkt)
        all_data += pkt
    ser.flush()

    time.sleep(1.0)  # ждём все ответы
    resp = ser.read(len(all_data) + 10)

    match = resp == all_data
    print(f"  Sent {len(all_data)} bytes, received {len(resp)} bytes")
    if match:
        print(f"  PASS  all bytes match")
        return 0
    else:
        # Найти первое расхождение
        for i in range(min(len(resp), len(all_data))):
            if resp[i] != all_data[i]:
                print(f"  FAIL  first diff at byte {i}: expected 0x{all_data[i]:02x}, got 0x{resp[i]:02x}")
                break
        if len(resp) != len(all_data):
            print(f"  FAIL  length mismatch: expected {len(all_data)}, got {len(resp)}")
        return 1

def test_full_range(ser):
    """Тест 5: все 256 значений по 1 байту."""
    print("Test 5: Full byte range 0x00-0xFF")
    ser.reset_input_buffer()
    time.sleep(0.05)
    data = bytes(range(256))
    ser.write(data)
    ser.flush()

    time.sleep(3.0)  # 256 байт @ 115200 ≈ 22 мс, но даём запас
    resp = ser.read(512)

    if resp == data:
        print(f"  PASS  256 bytes OK")
        return 0
    else:
        print(f"  FAIL  {len(resp)}/256 bytes received")
        for i in range(min(len(resp), len(data))):
            if resp[i] != data[i]:
                print(f"  first diff at byte {i}: expected 0x{data[i]:02x}, got 0x{resp[i]:02x}")
                break
        return 1

def test_tx_buffer_backpressure(ser):
    """Тест 6: TX backpressure — шлём данные быстрее чем TX может отправить.
    На уровне UART 115200 это не применимо (хост и FPGA на одной скорости),
    но проверяем что TX FIFO корректно буферизирует."""
    print("Test 6: TX buffer (large burst response)")
    ser.reset_input_buffer()
    time.sleep(0.05)

    # Шлём 16 байт — FPGA echo должна буферизировать TX ответы
    data = bytes([0xDE, 0xAD, 0xBE, 0xEF] * 4)
    ser.write(data)
    ser.flush()

    time.sleep(0.5)
    resp = ser.read(32)

    if resp == data:
        print(f"  PASS  {len(data)} bytes echoed correctly")
        return 0
    else:
        print(f"  FAIL  sent {len(data)}, got {len(resp)}")
        return 1


if __name__ == "__main__":
    ser = open_port()

    print(f"=== UART Buffer Test on {PORT} @ {BAUD} ===\n")

    errors = 0
    errors += test_single_bytes(ser)
    errors += test_burst_4(ser)
    errors += test_burst_overflow(ser)
    errors += test_rapid_packets(ser)
    errors += test_full_range(ser)
    errors += test_tx_buffer_backpressure(ser)

    ser.close()

    print(f"\n=== Results: {6 - errors} passed, {errors} failed ===")
    sys.exit(0 if errors == 0 else 1)
