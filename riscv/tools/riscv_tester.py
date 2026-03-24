#!/usr/bin/env python3
"""
riscv_tester.py — Тестер RISC-V процессора через UART (Windows/Linux/macOS)

╔══════════════════════════════════════════════════════════════════════════════╗
║  ПРОТОКОЛ DEBUG_CONTROLLER  (little-endian, все поля 32-бит если не указано)  ║
╠══════════════════════════════════════════════════════════════════════════════╣
║ Byte  Команда    Payload (→ FPGA)       Ответ (← FPGA)                       ║
║ 0x01  HALT       —                      0xFF  (после остановки CPU)           ║
║ 0x02  RESUME     —                      0xFF                                  ║
║ 0x03  STEP       —                      PC[31:0] + INSTR[31:0]  (8 байт)     ║
║ 0x04  READ_MEM   ADDR[31:0]             DATA[31:0]              (4 байта)     ║
║ 0x05  WRITE_MEM  ADDR[31:0] DATA[31:0]  0xFF                                  ║
║                                                                               ║
║ Байты вне диапазона 0x01–0x05 идут напрямую в CPU (passthrough).             ║
║ Байты от CPU приходят через тот же UART (passthrough обратно).               ║
╚══════════════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════════════╗
║  ПРОТОКОЛ ДАМПА РЕГИСТРОВ  (поверх CPU passthrough, без изменений железа)    ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  Python → CPU:  байт REG_DUMP_TRIGGER = 0x06  (проходит через passthrough)   ║
║  CPU → Python:  128 байт = 32 регистра × 4 байта little-endian (x0..x31)    ║
║                                                                               ║
║  Firmware-сторона (добавить в runtime.c или отдельный debug_stub.c):         ║
║                                                                               ║
║    #define REG_DUMP_TRIGGER 0x06                                              ║
║    void poll_debug(void) {                /* вызывать в main loop */         ║
║        if (!(*UART_STS & 1)) return;      /* нет байта */                    ║
║        if (*UART_RX != REG_DUMP_TRIGGER) return;                             ║
║        dump_regs_binary();               /* см. debug_stub.s */              ║
║    }                                                                          ║
║                                                                               ║
║  debug_stub.s (asm — единственный способ прочитать все регистры без искажений║
║    dump_regs_binary:                                                          ║
║        # сохранить t0 в стек, использовать t0 = 0x08000000 (UART TX)        ║
║        addi  sp, sp, -4                                                       ║
║        sw    t0, 0(sp)                                                        ║
║        lui   t0, 0x8000        # t0 = 0x08000000                             ║
║        .irp reg, x0,x1,...,x31                                                ║
║            sw \reg, 0(t0)                                                     ║
║        .endr                                                                  ║
║        lw    t0, 0(sp)                                                        ║
║        addi  sp, sp, 4                                                        ║
║        ret                                                                    ║
║                                                                               ║
║  Примечание: x0 всегда 0. t0 в дампе = сохранённое (до вызова) значение.    ║
╚══════════════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════════════╗
║  КАК СДЕЛАТЬ ROM ПЕРЕЗАПИСЫВАЕМЫМ ЧЕРЕЗ UART (аппаратные изменения TOP.sv)   ║
╠══════════════════════════════════════════════════════════════════════════════╣
║  Текущая архитектура:                                                        ║
║    logic [31:0] rom [0:ROM_DEPTH-1];    ← synthesis → Distributed RAM/BRAM  ║
║    wire instr_data = rom[pc >> 2];      ← только чтение                     ║
║                                                                               ║
║  Проблема: WRITE_MEM пишет в MEMORY_CONTROLLER (DDR SDRAM), а не в ROM.     ║
║  CPU fetches instructions из ROM, не из DDR → загруженная программа не      ║
║  выполняется.                                                                 ║
║                                                                               ║
║  Решение — двухпортовый BRAM (True Dual Port):                               ║
║                                                                               ║
║  1. В TOP.sv замените массив rom[] на экземпляр BRAM_TDP:                   ║
║       BRAM_TDP #(.DEPTH(ROM_DEPTH)) rom_bram (                               ║
║           // Port A — instruction fetch (read-only, async)                   ║
║           .clka(clk), .ena(1), .wea(0),                                      ║
║           .addra(instr_addr[clog2(ROM_DEPTH)+1:2]),                          ║
║           .douta(instr_data),                                                 ║
║           // Port B — debug write                                             ║
║           .clkb(clk), .enb(rom_dbg_we), .web(1),                            ║
║           .addrb(rom_dbg_addr[$clog2(ROM_DEPTH)+1:2]),                       ║
║           .dinb(rom_dbg_data)                                                 ║
║       );                                                                      ║
║                                                                               ║
║  2. Добавьте в DEBUG_CONTROLLER команду CMD_WRITE_ROM = 0x06:               ║
║       — payload: ADDR[31:0] DATA[31:0]  (адрес в пространстве ROM, 0..N)   ║
║       — ответ: 0xFF                                                           ║
║       — выходы: rom_dbg_we, rom_dbg_addr, rom_dbg_data                      ║
║                                                                               ║
║  3. Карта адресов для записи (предложение):                                  ║
║       0x0F000000 + offset → пишет в ROM[offset/4]                           ║
║       0x00000000 + offset → пишет в DDR (текущее поведение)                 ║
║                                                                               ║
║  После этого workflow станет:                                                 ║
║    python riscv_tester.py --port COM3 --upload program.hex                   ║
║    (скрипт пишет через CMD_WRITE_ROM → BRAM, затем RESUME)                  ║
╚══════════════════════════════════════════════════════════════════════════════╝

Требования и установка (Windows):
    1. Python 3.9+  →  https://python.org/downloads  (галочка "Add to PATH")
    2. pip install pyserial
    3. Драйвер UART-моста:
         FTDI FT232  →  https://ftdichip.com/drivers/vcp-drivers/
         CH340/CH341 →  https://www.wch-ic.com/downloads/CH341SER_EXE.html
         CP210x      →  Silicon Labs VCP driver
    4. Открыть Диспетчер устройств → Порты (COM и LPT) → запомнить номер COM

    Запуск (cmd.exe или PowerShell):
        python riscv_tester.py --list-ports
        python riscv_tester.py -p COM3 --capture

Использование:
    python riscv_tester.py --list-ports
    python riscv_tester.py --port COM3 --capture
    python riscv_tester.py --port COM3 --regs
    python riscv_tester.py --port COM3 --memdump 0x10000:64
    python riscv_tester.py --port COM3 --step 10
    python riscv_tester.py --port COM3 --tests tests/ --no-upload
    python riscv_tester.py --port COM3 --tests tests/ hello
"""

import argparse
import os
import struct
import sys
import time
from pathlib import Path
from typing import List, Optional, Tuple

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("Ошибка: pyserial не установлен.")
    print("Выполните:  pip install pyserial")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Поддержка ANSI-цветов на Windows
# ---------------------------------------------------------------------------
def _enable_ansi_windows():
    """
    На Windows 10+ включает VT100/ANSI через WinAPI.
    На старых Windows (< 10) тихо отключает цвета.
    Возвращает True если ANSI поддерживается.
    """
    if sys.platform != "win32":
        return sys.stdout.isatty()
    try:
        import ctypes
        kernel32 = ctypes.windll.kernel32
        # GetStdHandle(-11) = stdout
        handle = kernel32.GetStdHandle(-11)
        # GetConsoleMode
        mode = ctypes.c_ulong()
        if not kernel32.GetConsoleMode(handle, ctypes.byref(mode)):
            return False
        # ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
        if kernel32.SetConsoleMode(handle, mode.value | 0x0004):
            return True
    except Exception:
        pass
    return False


class C:
    _on = _enable_ansi_windows() if sys.platform == "win32" else sys.stdout.isatty()
    GREEN  = "\033[32m" if _on else ""
    RED    = "\033[31m" if _on else ""
    YELLOW = "\033[33m" if _on else ""
    CYAN   = "\033[36m" if _on else ""
    DIM    = "\033[2m"  if _on else ""
    RESET  = "\033[0m"  if _on else ""
    BOLD   = "\033[1m"  if _on else ""


# ---------------------------------------------------------------------------
# ABI имена регистров
# ---------------------------------------------------------------------------
_ABI = [
    "zero", "ra", "sp", "gp", "tp",
    "t0",  "t1",  "t2",
    "s0",  "s1",
    "a0",  "a1",  "a2",  "a3",  "a4",  "a5",  "a6",  "a7",
    "s2",  "s3",  "s4",  "s5",  "s6",  "s7",  "s8",  "s9",  "s10", "s11",
    "t3",  "t4",  "t5",  "t6",
]

# Байт-триггер дампа регистров через CPU passthrough
REG_DUMP_TRIGGER = 0x06   # не конфликтует с debug-командами 0x01–0x05


# ---------------------------------------------------------------------------
# Низкоуровневый драйвер DEBUG_CONTROLLER
# ---------------------------------------------------------------------------
class RiscVDebug:
    """Полный интерфейс к DEBUG_CONTROLLER через COM-порт."""

    CMD_HALT      = 0x01
    CMD_RESUME    = 0x02
    CMD_STEP      = 0x03
    CMD_READ_MEM  = 0x04
    CMD_WRITE_MEM = 0x05
    ACK           = 0xFF

    def __init__(self, port: str, baud: int = 115200, ack_timeout: float = 2.0):
        self.ack_timeout = ack_timeout
        self._ser = serial.Serial(
            port=port,
            baudrate=baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=ack_timeout,
            # Не дёргаем DTR/RTS при открытии — иначе FPGA может сброситься
            dsrdtr=False,
            rtscts=False,
            xonxoff=False,
        )
        # DTR=False явно, чтобы не было сброса через FTDI/CH340
        try:
            self._ser.dtr = False
            self._ser.rts = False
        except Exception:
            pass
        time.sleep(0.1)
        self._ser.reset_input_buffer()

    def close(self):
        self._ser.close()

    # -----------------------------------------------------------------------
    # Транспортный уровень
    # -----------------------------------------------------------------------
    def _send(self, data: bytes):
        self._ser.write(data)

    def _recv_exact(self, n: int, timeout: Optional[float] = None) -> bytes:
        """Читает ровно n байт; кидает TimeoutError если не успело."""
        deadline = time.monotonic() + (timeout if timeout is not None else self.ack_timeout)
        data = b""
        while len(data) < n:
            if time.monotonic() > deadline:
                raise TimeoutError(
                    f"Таймаут: ожидалось {n} байт, получено {len(data)}"
                )
            chunk = self._ser.read(n - len(data))
            data += chunk
        return data

    def _expect_ack(self):
        b = self._recv_exact(1)
        if b[0] != self.ACK:
            raise RuntimeError(f"Ожидался ACK 0xFF, получен 0x{b[0]:02X}")

    # -----------------------------------------------------------------------
    # Команды протокола
    # -----------------------------------------------------------------------
    def halt(self):
        """Останавливает CPU; блокирует до подтверждения."""
        self._send(bytes([self.CMD_HALT]))
        self._expect_ack()

    def resume(self):
        """Возобновляет CPU; блокирует до подтверждения."""
        self._send(bytes([self.CMD_RESUME]))
        self._expect_ack()

    def step(self) -> Tuple[int, int]:
        """Один шаг. Возвращает (pc, instr) — состояние ПОСЛЕ шага."""
        self._send(bytes([self.CMD_STEP]))
        raw = self._recv_exact(8)
        pc    = struct.unpack_from("<I", raw, 0)[0]
        instr = struct.unpack_from("<I", raw, 4)[0]
        return pc, instr

    def read_mem(self, addr: int) -> int:
        """Читает слово из MEMORY_CONTROLLER (DDR SDRAM)."""
        if addr & 3:
            raise ValueError(f"Адрес 0x{addr:08X} не выровнен по 4 байтам")
        self._send(struct.pack("<BI", self.CMD_READ_MEM, addr))
        raw = self._recv_exact(4)
        return struct.unpack("<I", raw)[0]

    def write_mem(self, addr: int, data: int):
        """Записывает слово в MEMORY_CONTROLLER (DDR SDRAM)."""
        if addr & 3:
            raise ValueError(f"Адрес 0x{addr:08X} не выровнен по 4 байтам")
        self._send(struct.pack("<BII", self.CMD_WRITE_MEM, addr, data))
        self._expect_ack()

    # -----------------------------------------------------------------------
    # Дамп регистров через CPU passthrough
    # -----------------------------------------------------------------------
    def read_registers(self, timeout: float = 2.0) -> List[int]:
        """
        Запрашивает у CPU дамп всех 32 регистров через passthrough.

        Отправляет байт REG_DUMP_TRIGGER (0x06) → CPU читает его из UART_RX
        → CPU пишет x0..x31 (каждый 4 байта LE) в UART_TX → Python читает
        128 байт и декодирует.

        CPU должен быть ЗАПУЩЕН и firmware должен поддерживать REG_DUMP_TRIGGER.
        Добавьте в main loop:
            poll_debug();   // проверяет UART и отвечает на 0x06 дампом регистров

        Возвращает список из 32 целых чисел [x0, x1, ..., x31].
        """
        self._ser.reset_input_buffer()
        self._send(bytes([REG_DUMP_TRIGGER]))
        raw = self._recv_exact(32 * 4, timeout=timeout)
        return [struct.unpack_from("<I", raw, i * 4)[0] for i in range(32)]

    # -----------------------------------------------------------------------
    # Последовательный дамп памяти
    # -----------------------------------------------------------------------
    def read_memory_range(self, base_addr: int, word_count: int,
                          progress: bool = True) -> List[int]:
        """
        Читает word_count слов начиная с base_addr через последовательные
        READ_MEM команды.

        Все адреса должны быть выровнены по 4 байтам.
        Прогресс-бар выводится если progress=True и word_count > 16.
        """
        if base_addr & 3:
            raise ValueError(f"base_addr 0x{base_addr:08X} не выровнен")
        result = []
        show = progress and word_count > 16
        for i in range(word_count):
            result.append(self.read_mem(base_addr + i * 4))
            if show and (i % 16 == 0 or i == word_count - 1):
                pct = (i + 1) * 100 // word_count
                print(f"\r  Чтение 0x{base_addr:08X}+{(i+1)*4-4:#06x}: "
                      f"{pct:3d}% ({i+1}/{word_count})  ",
                      end="", flush=True)
        if show:
            print()
        return result

    # -----------------------------------------------------------------------
    # Загрузка hex-файла
    # -----------------------------------------------------------------------
    def upload_hex(self, hex_path: str, base_addr: int = 0x00000000,
                   progress: bool = True):
        """
        Загружает hex-файл в DDR SDRAM через WRITE_MEM.
        Для исполнения нужен двухпортовый BRAM (см. документацию в шапке файла).
        """
        words = _load_hex_file(hex_path)
        total = len(words)
        for i, word in enumerate(words):
            self.write_mem(base_addr + i * 4, word)
            if progress and (i % 64 == 0 or i == total - 1):
                pct = (i + 1) * 100 // total
                print(f"\r  Загрузка: {pct:3d}% ({i+1}/{total} слов)  ",
                      end="", flush=True)
        if progress:
            print()

    # -----------------------------------------------------------------------
    # Захват вывода CPU
    # -----------------------------------------------------------------------
    def capture_output(self, idle_timeout: float = 2.0,
                       total_timeout: float = 30.0) -> bytes:
        """
        Читает байты UART passthrough (вывод программы) до тайм-аута.
        idle_timeout  — пауза без байт = программа завершилась.
        total_timeout — жёсткий предел времени.
        """
        buf = bytearray()
        self._ser.timeout = 0.05
        deadline   = time.monotonic() + total_timeout
        last_byte  = time.monotonic()
        while True:
            if time.monotonic() > deadline:
                break
            if time.monotonic() - last_byte > idle_timeout:
                break
            chunk = self._ser.read(512)
            if chunk:
                buf.extend(chunk)
                last_byte = time.monotonic()
        self._ser.timeout = self.ack_timeout
        return bytes(buf)


# ---------------------------------------------------------------------------
# Утилиты форматирования
# ---------------------------------------------------------------------------
def display_registers(regs: List[int], pc: Optional[int] = None):
    """
    Выводит таблицу регистров: два столбца, ABI-имена, hex + decimal.
    Нулевые регистры приглушены.
    """
    print(f"\n{C.BOLD}  Регистры RISC-V{C.RESET}"
          + (f"  (PC = {C.CYAN}0x{pc:08X}{C.RESET})" if pc is not None else ""))
    print("  " + "─" * 70)
    for i in range(0, 32, 2):
        def fmt(n):
            v  = regs[n]
            ab = _ABI[n]
            dim = C.DIM if v == 0 else ""
            rst = C.RESET if v == 0 else ""
            sgn = _signed32(v)
            note = f"  ({sgn:12d})" if sgn < 0 else f"  ({sgn:12d})"
            return f"{dim}x{n:<2d}/{ab:<4s} = {C.CYAN}{v:08X}{rst}{dim}{note}{rst}"
        left  = fmt(i)
        right = fmt(i + 1) if i + 1 < 32 else ""
        print(f"  {left}    {right}")
    print()


def display_hexdump(base_addr: int, words: List[int]):
    """
    Классический hexdump: 4 слова на строку (16 байт),
    адрес | hex words | ASCII-представление байт.
    """
    print(f"\n{C.BOLD}  Дамп памяти  0x{base_addr:08X} – "
          f"0x{base_addr + len(words)*4 - 1:08X}"
          f"  ({len(words)} слов = {len(words)*4} байт){C.RESET}")
    print("  " + "─" * 74)
    WORDS_PER_ROW = 4
    for row in range(0, len(words), WORDS_PER_ROW):
        chunk = words[row: row + WORDS_PER_ROW]
        addr  = base_addr + row * 4
        # сборка сырых байт (little-endian)
        raw_bytes = b"".join(struct.pack("<I", w) for w in chunk)
        # hex-часть: 4 группы по 4 байта
        hex_parts = []
        for i in range(WORDS_PER_ROW):
            if i < len(chunk):
                val = chunk[i]
                # цвет: 0x00000000 приглушён, 0xFFFFFFFF — жёлтый
                if val == 0:
                    hex_parts.append(f"{C.DIM}00000000{C.RESET}")
                elif val == 0xFFFFFFFF:
                    hex_parts.append(f"{C.YELLOW}FFFFFFFF{C.RESET}")
                else:
                    hex_parts.append(f"{val:08X}")
            else:
                hex_parts.append("        ")
        hex_str = "  ".join(hex_parts)
        # ASCII-часть
        ascii_str = "".join(
            chr(b) if 0x20 <= b < 0x7F else "." for b in raw_bytes
        )
        print(f"  {C.CYAN}0x{addr:08X}{C.RESET}  {hex_str}  {C.DIM}{ascii_str}{C.RESET}")
    print()


def _signed32(v: int) -> int:
    return v if v < 0x80000000 else v - 0x100000000


# ---------------------------------------------------------------------------
# Работа с hex-файлами
# ---------------------------------------------------------------------------
def _load_hex_file(path: str) -> List[int]:
    """Загружает $readmemh hex-файл (одно 32-битное слово на строку)."""
    words = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//") or line.startswith("@"):
                continue
            words.append(int(line, 16))
    return words


def load_expected(path: str) -> Optional[str]:
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    return None


def _parse_memdump_spec(spec: str) -> Tuple[int, int]:
    """
    Парсит спецификацию дампа:  ADDR[:COUNT]
      ADDR  — hex (0x...) или decimal
      COUNT — количество слов (по умолчанию 64)
    Примеры: '0x10000:128'  '65536'  '0x10000'
    """
    parts = spec.split(":")
    addr  = int(parts[0], 0)
    count = int(parts[1], 0) if len(parts) > 1 else 64
    return addr, count


# ---------------------------------------------------------------------------
# Обнаружение и запуск тестов
# ---------------------------------------------------------------------------
def discover_tests(tests_root: str) -> List[str]:
    programs_dir = Path(tests_root) / "programs"
    if not programs_dir.is_dir():
        programs_dir = Path(tests_root)
    return [
        e.name for e in sorted(programs_dir.iterdir())
        if e.is_dir() and (e / "program.hex").exists()
    ]


def run_test(dbg: RiscVDebug, test_dir: Path,
             upload: bool = True,
             idle_timeout: float = 2.0,
             total_timeout: float = 30.0) -> Tuple[bool, str]:
    hex_file = test_dir / "program.hex"
    exp_file = test_dir / "expected.txt"

    if not hex_file.exists():
        return False, "program.hex не найден"

    if upload:
        try:
            dbg.halt()
            dbg.upload_hex(str(hex_file), progress=True)
            dbg.resume()
        except Exception as e:
            return False, f"Загрузка/запуск: {e}"

    try:
        raw = dbg.capture_output(idle_timeout=idle_timeout,
                                 total_timeout=total_timeout)
    except Exception as e:
        return False, f"Захват вывода: {e}"

    got      = raw.decode("utf-8", errors="replace")
    expected = load_expected(str(exp_file))

    if expected is None:
        return True, f"(нет expected.txt)\n{got}"
    if got == expected:
        return True, ""
    return False, _diff_str(expected, got)


def _diff_str(expected: str, got: str) -> str:
    e_lines = expected.splitlines()
    g_lines = got.splitlines()
    out = [f"  Ожидалось ({len(e_lines)} строк):"]
    for l in e_lines[:8]:
        out.append(f"    {repr(l)}")
    out.append(f"  Получено ({len(g_lines)} строк):")
    for l in g_lines[:8]:
        out.append(f"    {repr(l)}")
    return "\n".join(out)


# ---------------------------------------------------------------------------
# Информация о портах
# ---------------------------------------------------------------------------
def list_ports():
    ports = list(serial.tools.list_ports.comports())
    if not ports:
        print("Последовательные порты не найдены.")
        return
    print("Доступные порты:")
    for p in ports:
        print(f"  {p.device:<12s} {p.description}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Тестер RISC-V процессора через UART",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Примеры:
  python riscv_tester.py --list-ports
  python riscv_tester.py -p COM3 --capture
  python riscv_tester.py -p COM3 --regs
  python riscv_tester.py -p COM3 --memdump 0x10000:64
  python riscv_tester.py -p COM3 --memdump 0x10000:128 --memdump 0x20000:32
  python riscv_tester.py -p COM3 --step 20
  python riscv_tester.py -p COM3 --tests tests/ --no-upload
  python riscv_tester.py -p COM3 --tests tests/ hello
  python riscv_tester.py -p COM3 --upload tests/programs/hello/program.hex
""")

    g = p.add_argument_group("Подключение")
    g.add_argument("--port",        "-p", help="COM-порт (COM3, /dev/ttyUSB0, …)")
    g.add_argument("--baud",        "-b", type=int, default=115200)
    g.add_argument("--ack-timeout",       type=float, default=2.0,
                   metavar="SEC", help="Таймаут ответа на команду (сек, по умолч 2.0)")
    g.add_argument("--list-ports",  action="store_true",
                   help="Показать доступные COM-порты и выйти")

    g = p.add_argument_group("Инспекция")
    g.add_argument("--regs",   action="store_true",
                   help="Дамп всех 32 регистров через CPU passthrough (0x06 триггер)")
    g.add_argument("--memdump", metavar="ADDR[:COUNT]", action="append",
                   help="Hexdump памяти: --memdump 0x10000:64  (можно несколько раз)")
    g.add_argument("--step",   type=int, metavar="N",
                   help="N шагов с выводом PC и дизассемблированной инструкции")

    g = p.add_argument_group("Захват вывода")
    g.add_argument("--capture",     action="store_true",
                   help="Захватить и показать вывод текущей программы")
    g.add_argument("--idle-timeout",  type=float, default=2.0, metavar="SEC")
    g.add_argument("--total-timeout", type=float, default=30.0, metavar="SEC")

    g = p.add_argument_group("Программирование и тесты")
    g.add_argument("--upload", "-u", metavar="HEX",
                   help="Загрузить hex в DDR и запустить CPU")
    g.add_argument("--tests",  "-t", metavar="DIR",
                   help="Каталог tests/ для прогона всех тестов")
    g.add_argument("--no-upload", action="store_true",
                   help="Не загружать программу (CPU уже работает)")
    g.add_argument("filter", nargs="?",
                   help="Запустить только тест с данным именем (фильтр)")
    return p


def main():
    parser = build_parser()
    args   = parser.parse_args()

    if args.list_ports:
        list_ports()
        return

    if not args.port:
        print("Укажите --port или используйте --list-ports")
        parser.print_usage()
        sys.exit(1)

    print(f"{C.CYAN}Подключение к {args.port} @ {args.baud} baud…{C.RESET}")
    try:
        dbg = RiscVDebug(args.port, args.baud, ack_timeout=args.ack_timeout)
    except serial.SerialException as e:
        print(f"{C.RED}Ошибка порта: {e}{C.RESET}")
        sys.exit(1)
    print(f"{C.GREEN}Подключено.{C.RESET}")

    try:
        _run(dbg, args)
    finally:
        dbg.close()


def _run(dbg: RiscVDebug, args):
    any_action = False

    # ── Шаговая отладка ────────────────────────────────────────────────────
    if args.step:
        any_action = True
        _cmd_step(dbg, args.step)

    # ── Дамп регистров ─────────────────────────────────────────────────────
    if args.regs:
        any_action = True
        _cmd_regs(dbg, args.ack_timeout)

    # ── Дамп памяти ────────────────────────────────────────────────────────
    if args.memdump:
        any_action = True
        for spec in args.memdump:
            _cmd_memdump(dbg, spec)

    # ── Захват вывода ──────────────────────────────────────────────────────
    if args.capture:
        any_action = True
        _cmd_capture(dbg, args.idle_timeout, args.total_timeout)

    # ── Загрузка программы ─────────────────────────────────────────────────
    if args.upload:
        any_action = True
        _cmd_upload(dbg, args.upload, args.idle_timeout, args.total_timeout)

    # ── Прогон тестов ──────────────────────────────────────────────────────
    if args.tests:
        any_action = True
        _cmd_tests(dbg, args)

    if not any_action:
        print("Укажите действие: --step, --regs, --memdump, --capture, "
              "--upload или --tests.  --help для справки.")


# ---------------------------------------------------------------------------
# Команды CLI
# ---------------------------------------------------------------------------
def _cmd_step(dbg: RiscVDebug, n: int):
    print(f"\n{C.BOLD}=== Шаговая отладка ({n} шагов) ==={C.RESET}")
    try:
        dbg.halt()
        print(f"  {C.GREEN}CPU остановлен.{C.RESET}")
    except Exception as e:
        print(f"  {C.RED}HALT: {e}{C.RESET}")
        return
    for i in range(n):
        try:
            pc, instr = dbg.step()
            mnem = _decode_instr(instr)
            print(f"  {i+1:4d}  {C.CYAN}PC=0x{pc:08X}{C.RESET}  "
                  f"{instr:08X}   {mnem}")
        except Exception as e:
            print(f"  {C.RED}STEP #{i+1}: {e}{C.RESET}")
            break


def _cmd_regs(dbg: RiscVDebug, timeout: float):
    print(f"\n{C.BOLD}=== Дамп регистров ==={C.RESET}")
    print(f"  Отправляю триггер 0x{REG_DUMP_TRIGGER:02X} → CPU…")
    try:
        regs = dbg.read_registers(timeout=timeout)
    except TimeoutError:
        print(f"  {C.RED}Таймаут: CPU не ответил на триггер.{C.RESET}")
        print(f"  {C.YELLOW}Убедитесь что firmware вызывает poll_debug() в main loop.{C.RESET}")
        return
    except Exception as e:
        print(f"  {C.RED}Ошибка: {e}{C.RESET}")
        return
    display_registers(regs)


def _cmd_memdump(dbg: RiscVDebug, spec: str):
    try:
        base_addr, word_count = _parse_memdump_spec(spec)
    except ValueError as e:
        print(f"  {C.RED}Неверный формат --memdump '{spec}': {e}{C.RESET}")
        return
    print(f"\n{C.BOLD}=== Дамп памяти  0x{base_addr:08X} : {word_count} слов ==={C.RESET}")
    try:
        words = dbg.read_memory_range(base_addr, word_count, progress=True)
    except Exception as e:
        print(f"  {C.RED}Ошибка чтения памяти: {e}{C.RESET}")
        return
    display_hexdump(base_addr, words)


def _cmd_capture(dbg: RiscVDebug, idle: float, total: float):
    print(f"\n{C.BOLD}=== Захват вывода CPU ==={C.RESET}")
    print(f"  Жду байты (idle {idle}s, max {total}s)…")
    raw  = dbg.capture_output(idle, total)
    text = raw.decode("utf-8", errors="replace")
    print(f"  Получено {len(raw)} байт:")
    print("  " + "─" * 60)
    for line in text.splitlines():
        print(f"  {line}")
    print("  " + "─" * 60)


def _cmd_upload(dbg: RiscVDebug, hex_path: str, idle: float, total: float):
    print(f"\n{C.BOLD}=== Загрузка программы ==={C.RESET}")
    print(f"  Файл: {hex_path}")
    print(f"  {C.YELLOW}Примечание: запись в DDR, не в ROM. "
          f"Для исполнения нужен двухпортовый BRAM (см. --help).{C.RESET}")
    try:
        dbg.halt()
        print(f"  {C.GREEN}CPU остановлен.{C.RESET}")
        dbg.upload_hex(hex_path, base_addr=0x00000000, progress=True)
        dbg.resume()
        print(f"  {C.GREEN}CPU запущен.{C.RESET}")
    except Exception as e:
        print(f"  {C.RED}Ошибка: {e}{C.RESET}")
        return
    print(f"  Жду вывод (idle {idle}s)…")
    raw  = dbg.capture_output(idle, total)
    text = raw.decode("utf-8", errors="replace")
    print(f"  Вывод ({len(raw)} байт):")
    print("  " + "─" * 60)
    for line in text.splitlines():
        print(f"  {line}")
    print("  " + "─" * 60)


def _cmd_tests(dbg: RiscVDebug, args):
    tests = discover_tests(args.tests)
    if args.filter:
        tests = [t for t in tests if args.filter in t]
    if not tests:
        print(f"{C.YELLOW}Тесты не найдены в {args.tests}{C.RESET}")
        return

    programs_dir = Path(args.tests) / "programs"
    if not programs_dir.is_dir():
        programs_dir = Path(args.tests)

    upload = not args.no_upload
    print(f"\n{C.BOLD}=== Прогон {len(tests)} тестов ==={C.RESET}")
    mode = "загрузка в DDR + запуск" if upload else "захват вывода"
    print(f"  Режим: {mode}")
    if upload:
        print(f"  {C.YELLOW}Требуется аппаратная поддержка двухпортового BRAM!{C.RESET}")
    print()

    passed = failed = 0
    for name in tests:
        print(f"  {C.BOLD}{name:<24}{C.RESET}", end="", flush=True)
        ok, details = run_test(dbg, programs_dir / name,
                               upload=upload,
                               idle_timeout=args.idle_timeout,
                               total_timeout=args.total_timeout)
        if ok:
            print(f"{C.GREEN}PASS{C.RESET}")
            passed += 1
        else:
            print(f"{C.RED}FAIL{C.RESET}")
            failed += 1
            for line in details.splitlines():
                print(f"    {line}")

    color = C.RED if failed else C.GREEN
    print(f"\n{C.BOLD}=== {C.GREEN}{passed} пройдено{C.RESET}{C.BOLD}  "
          f"{color}{failed} провалено{C.RESET}{C.BOLD} ==={C.RESET}")


# ---------------------------------------------------------------------------
# Дизассемблер инструкций (для --step)
# ---------------------------------------------------------------------------
def _decode_instr(instr: int) -> str:
    opcode = instr & 0x7F
    f3     = (instr >> 12) & 0x7
    rd     = (instr >> 7)  & 0x1F
    rs1    = (instr >> 15) & 0x1F
    rs2    = (instr >> 20) & 0x1F
    f7     = (instr >> 25) & 0x7F

    def reg(r):
        return _ABI[r] if r < 32 else f"x{r}"

    def i_imm():
        v = instr >> 20
        return v if not (v >> 11) else v | (-1 << 12)

    def s_imm():
        v = ((instr >> 25) << 5) | ((instr >> 7) & 0x1F)
        return v if not (v >> 11) else v | (-1 << 12)

    def b_imm():
        v = (((instr >> 31) & 1) << 12) | (((instr >> 7)  & 1) << 11) | \
            (((instr >> 25) & 0x3F) << 5) | (((instr >> 8) & 0xF) << 1)
        return v if not (v >> 12) else v | (-1 << 13)

    def u_imm():
        return instr & 0xFFFFF000

    def j_imm():
        v = (((instr >> 31) & 1) << 20) | (((instr >> 12) & 0xFF) << 12) | \
            (((instr >> 20) & 1) << 11) | (((instr >> 21) & 0x3FF) << 1)
        return v if not (v >> 20) else v | (-1 << 21)

    try:
        if opcode == 0x37: return f"lui    {reg(rd)}, 0x{(u_imm()>>12)&0xFFFFF:x}"
        if opcode == 0x17: return f"auipc  {reg(rd)}, 0x{(u_imm()>>12)&0xFFFFF:x}"
        if opcode == 0x6F: return f"jal    {reg(rd)}, {j_imm():+d}"
        if opcode == 0x67: return f"jalr   {reg(rd)}, {i_imm()}({reg(rs1)})"
        if opcode == 0x63:
            m = {0:"beq",1:"bne",4:"blt",5:"bge",6:"bltu",7:"bgeu"}.get(f3, "b??")
            return f"{m:<6} {reg(rs1)}, {reg(rs2)}, {b_imm():+d}"
        if opcode == 0x03:
            m = {0:"lb",1:"lh",2:"lw",4:"lbu",5:"lhu"}.get(f3, "l??")
            return f"{m:<6} {reg(rd)}, {i_imm()}({reg(rs1)})"
        if opcode == 0x23:
            m = {0:"sb",1:"sh",2:"sw"}.get(f3, "s??")
            return f"{m:<6} {reg(rs2)}, {s_imm()}({reg(rs1)})"
        if opcode == 0x13:
            if f3 == 0: return f"addi   {reg(rd)}, {reg(rs1)}, {i_imm()}"
            if f3 == 1: return f"slli   {reg(rd)}, {reg(rs1)}, {rs2}"
            if f3 == 2: return f"slti   {reg(rd)}, {reg(rs1)}, {i_imm()}"
            if f3 == 3: return f"sltiu  {reg(rd)}, {reg(rs1)}, {i_imm()}"
            if f3 == 4: return f"xori   {reg(rd)}, {reg(rs1)}, {i_imm()}"
            if f3 == 5:
                return (f"srai   {reg(rd)}, {reg(rs1)}, {rs2}" if f7 == 0x20
                        else f"srli   {reg(rd)}, {reg(rs1)}, {rs2}")
            if f3 == 6: return f"ori    {reg(rd)}, {reg(rs1)}, {i_imm()}"
            if f3 == 7: return f"andi   {reg(rd)}, {reg(rs1)}, {i_imm()}"
        if opcode == 0x33:
            if f3 == 0: return (f"sub    {reg(rd)}, {reg(rs1)}, {reg(rs2)}" if f7==0x20
                                else f"add    {reg(rd)}, {reg(rs1)}, {reg(rs2)}")
            if f3 == 1: return f"sll    {reg(rd)}, {reg(rs1)}, {reg(rs2)}"
            if f3 == 2: return f"slt    {reg(rd)}, {reg(rs1)}, {reg(rs2)}"
            if f3 == 3: return f"sltu   {reg(rd)}, {reg(rs1)}, {reg(rs2)}"
            if f3 == 4: return f"xor    {reg(rd)}, {reg(rs1)}, {reg(rs2)}"
            if f3 == 5: return (f"sra    {reg(rd)}, {reg(rs1)}, {reg(rs2)}" if f7==0x20
                                else f"srl    {reg(rd)}, {reg(rs1)}, {reg(rs2)}")
            if f3 == 6: return f"or     {reg(rd)}, {reg(rs1)}, {reg(rs2)}"
            if f3 == 7: return f"and    {reg(rd)}, {reg(rs1)}, {reg(rs2)}"
        if opcode == 0x0F: return "fence"
        if opcode == 0x73:
            if instr == 0x00000073: return "ecall"
            if instr == 0x00100073: return "ebreak"
    except Exception:
        pass
    return "???"


if __name__ == "__main__":
    main()
