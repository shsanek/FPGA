#!/usr/bin/env python3
"""
riscv_tester.py — Тестер RISC-V процессора через UART

Протокол DEBUG_CONTROLLER:
  Команды (хост → FPGA):
    0x01  HALT         payload=—
    0x02  RESUME       payload=—
    0x03  STEP         payload=—
    0x04  READ_MEM     payload=ADDR[4B]
    0x05  WRITE_MEM    payload=ADDR[4B]+DATA[4B]
    0x06  INPUT        payload=DATA[1B]
    0x07  RESET_PC     payload=ADDR[4B]
    0xFD  SYNC_RESET   payload=—  (без ответа)

  Ответы (FPGA → хост):
    0xAA CMD CMD [DATA...]   — debug-ответ
    0xBB BYTE                — CPU UART вывод

Использование:
    python riscv_tester.py --list-ports
    python riscv_tester.py -p COM4 --capture
    python riscv_tester.py -p COM4 --step 10
    python riscv_tester.py -p COM4 --memdump 0x0:64
    python riscv_tester.py -p COM4 --upload program.hex
    python riscv_tester.py -p COM4 --tests tests/
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
# ANSI-цвета
# ---------------------------------------------------------------------------
def _enable_ansi_windows():
    if sys.platform != "win32":
        return sys.stdout.isatty()
    try:
        import ctypes
        kernel32 = ctypes.windll.kernel32
        handle = kernel32.GetStdHandle(-11)
        mode = ctypes.c_ulong()
        if not kernel32.GetConsoleMode(handle, ctypes.byref(mode)):
            return False
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


# ---------------------------------------------------------------------------
# Протокол
# ---------------------------------------------------------------------------
HDR_DEBUG    = 0xAA
HDR_CPU_UART = 0xBB

CMD_HALT      = 0x01
CMD_RESUME    = 0x02
CMD_STEP      = 0x03
CMD_READ_MEM  = 0x04
CMD_WRITE_MEM = 0x05
CMD_INPUT     = 0x06
CMD_RESET_PC  = 0x07
CMD_SYNC_RESET = 0xFD

# Сколько байт данных после ACK для каждой команды
_RESP_DATA_LEN = {
    CMD_HALT:      0,
    CMD_RESUME:    0,
    CMD_STEP:      8,   # PC[4B] + INSTR[4B]
    CMD_READ_MEM:  4,   # DATA[4B]
    CMD_WRITE_MEM: 0,
    CMD_INPUT:     0,
    CMD_RESET_PC:  0,
}


# ---------------------------------------------------------------------------
# Драйвер DEBUG_CONTROLLER
# ---------------------------------------------------------------------------
class RiscVDebug:
    """Синхронный интерфейс к DEBUG_CONTROLLER через COM-порт."""

    def __init__(self, port: str, baud: int = 115200, timeout: float = 1.0):
        self.timeout = timeout
        self.cpu_output_buf = bytearray()

        self._ser = serial.Serial(
            port=port,
            baudrate=baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.05,  # короткий таймаут для неблокирующего чтения
            dsrdtr=False,
            rtscts=False,
            xonxoff=False,
        )
        try:
            self._ser.dtr = False
            self._ser.rts = False
        except Exception:
            pass
        time.sleep(0.1)
        self._ser.reset_input_buffer()

        # Синхронизация при подключении
        self.sync_reset()
        time.sleep(0.05)
        self._ser.reset_input_buffer()

    def close(self):
        self._ser.close()

    # -------------------------------------------------------------------
    # Транспортный уровень
    # -------------------------------------------------------------------
    def _send(self, data: bytes):
        self._ser.write(data)
        self._ser.flush()

    def _read_byte(self, deadline: float) -> int:
        """Читает 1 байт с таймаутом. Кидает TimeoutError."""
        while True:
            if time.monotonic() > deadline:
                raise TimeoutError("Таймаут чтения UART")
            b = self._ser.read(1)
            if b:
                return b[0]

    def _read_exact(self, n: int, deadline: float) -> bytes:
        """Читает ровно n байт с таймаутом."""
        buf = bytearray()
        while len(buf) < n:
            if time.monotonic() > deadline:
                raise TimeoutError(
                    f"Таймаут: ожидалось {n} байт, получено {len(buf)}")
            chunk = self._ser.read(n - len(buf))
            if chunk:
                buf.extend(chunk)
        return bytes(buf)

    def _wait_debug_response(self, expected_cmd: int) -> bytes:
        """
        Ждёт debug-ответ (0xAA CMD CMD [DATA...]).
        Во время ожидания принимает CPU UART (0xBB BYTE) в буфер.
        Возвращает DATA (может быть пустым).
        """
        deadline = time.monotonic() + self.timeout
        data_len = _RESP_DATA_LEN.get(expected_cmd, 0)

        while True:
            hdr = self._read_byte(deadline)

            if hdr == HDR_CPU_UART:
                # CPU output: читаем 1 байт данных
                b = self._read_byte(deadline)
                self.cpu_output_buf.append(b)
                continue

            if hdr == HDR_DEBUG:
                # Debug response: CMD CMD [DATA...]
                ack = self._read_exact(2, deadline)
                if ack[0] != expected_cmd or ack[1] != expected_cmd:
                    raise RuntimeError(
                        f"ACK mismatch: ожидался 0x{expected_cmd:02X} 0x{expected_cmd:02X}, "
                        f"получен 0x{ack[0]:02X} 0x{ack[1]:02X}")
                if data_len > 0:
                    data = self._read_exact(data_len, deadline)
                    return data
                return b""

            # Неизвестный заголовок — пропускаем
            # (может быть мусор после sync_reset)

    # -------------------------------------------------------------------
    # Команды протокола
    # -------------------------------------------------------------------
    def sync_reset(self):
        """Сброс DEBUG FSM. Без ответа."""
        self._send(bytes([CMD_SYNC_RESET]))

    def halt(self):
        """Остановить CPU."""
        self._send(bytes([CMD_HALT]))
        self._wait_debug_response(CMD_HALT)

    def resume(self):
        """Возобновить CPU."""
        self._send(bytes([CMD_RESUME]))
        self._wait_debug_response(CMD_RESUME)

    def step(self) -> Tuple[int, int]:
        """Один шаг. Возвращает (pc, instr)."""
        self._send(bytes([CMD_STEP]))
        data = self._wait_debug_response(CMD_STEP)
        pc    = struct.unpack_from("<I", data, 0)[0]
        instr = struct.unpack_from("<I", data, 4)[0]
        return pc, instr

    def read_mem(self, addr: int) -> int:
        """Чтение 32-бит слова из памяти."""
        self._send(struct.pack("<BI", CMD_READ_MEM, addr))
        data = self._wait_debug_response(CMD_READ_MEM)
        return struct.unpack("<I", data)[0]

    def write_mem(self, addr: int, value: int):
        """Запись 32-бит слова в память."""
        self._send(struct.pack("<BII", CMD_WRITE_MEM, addr, value))
        self._wait_debug_response(CMD_WRITE_MEM)

    def input_byte(self, byte: int):
        """Доставить байт в CPU через CMD_INPUT."""
        self._send(struct.pack("<BB", CMD_INPUT, byte & 0xFF))
        self._wait_debug_response(CMD_INPUT)

    def reset_pc(self, addr: int = 0):
        """Установить PC."""
        self._send(struct.pack("<BI", CMD_RESET_PC, addr))
        self._wait_debug_response(CMD_RESET_PC)

    # -------------------------------------------------------------------
    # CPU output
    # -------------------------------------------------------------------
    def flush_cpu_output(self) -> bytes:
        """Забрать накопленный CPU output и очистить буфер."""
        data = bytes(self.cpu_output_buf)
        self.cpu_output_buf.clear()
        return data

    def capture_output(self, idle_timeout: float = 2.0,
                       total_timeout: float = 30.0) -> bytes:
        """
        Активно читает CPU output (0xBB пары) до idle timeout.
        Возвращает все накопленные байты.
        """
        deadline  = time.monotonic() + total_timeout
        last_byte = time.monotonic()

        while True:
            now = time.monotonic()
            if now > deadline:
                break
            if now - last_byte > idle_timeout:
                break

            b = self._ser.read(1)
            if not b:
                continue

            if b[0] == HDR_CPU_UART:
                # Читаем байт данных
                data_byte = self._ser.read(1)
                if data_byte:
                    self.cpu_output_buf.append(data_byte[0])
                    last_byte = time.monotonic()
            elif b[0] == HDR_DEBUG:
                # Неожиданный debug-ответ во время capture — пропускаем
                # (читаем ACK CMD CMD чтобы не сбить поток)
                self._ser.read(2)
            # Иначе — мусор, пропускаем

        return self.flush_cpu_output()

    # -------------------------------------------------------------------
    # Высокоуровневые операции
    # -------------------------------------------------------------------
    def upload_and_run(self, hex_path: str, base_addr: int = 0):
        """Загрузить hex в память и запустить CPU."""
        words = _load_hex_file(hex_path)
        self.halt()
        for i, w in enumerate(words):
            self.write_mem(base_addr + i * 4, w)
        self.reset_pc(base_addr)
        self.resume()

    def upload_hex(self, hex_path: str, base_addr: int = 0,
                   progress: bool = True):
        """Загрузить hex в память (CPU должен быть HALT)."""
        words = _load_hex_file(hex_path)
        total = len(words)
        for i, w in enumerate(words):
            self.write_mem(base_addr + i * 4, w)
            if progress and (i % 64 == 0 or i == total - 1):
                pct = (i + 1) * 100 // total
                print(f"\r  Загрузка: {pct:3d}% ({i+1}/{total} слов)  ",
                      end="", flush=True)
        if progress:
            print()

    def read_memory_range(self, base_addr: int, word_count: int,
                          progress: bool = True) -> List[int]:
        """Чтение блока памяти."""
        result = []
        show = progress and word_count > 16
        for i in range(word_count):
            result.append(self.read_mem(base_addr + i * 4))
            if show and (i % 16 == 0 or i == word_count - 1):
                pct = (i + 1) * 100 // word_count
                print(f"\r  Чтение: {pct:3d}% ({i+1}/{word_count})  ",
                      end="", flush=True)
        if show:
            print()
        return result


# ---------------------------------------------------------------------------
# Утилиты
# ---------------------------------------------------------------------------
def _load_hex_file(path: str) -> List[int]:
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


def _signed32(v: int) -> int:
    return v if v < 0x80000000 else v - 0x100000000


def _parse_memdump_spec(spec: str) -> Tuple[int, int]:
    parts = spec.split(":")
    addr  = int(parts[0], 0)
    count = int(parts[1], 0) if len(parts) > 1 else 64
    return addr, count


# ---------------------------------------------------------------------------
# Форматирование
# ---------------------------------------------------------------------------
def display_registers(regs: List[int], pc: Optional[int] = None):
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
            return f"{dim}x{n:<2d}/{ab:<4s} = {C.CYAN}{v:08X}{rst}{dim}  ({sgn:12d}){rst}"
        left  = fmt(i)
        right = fmt(i + 1) if i + 1 < 32 else ""
        print(f"  {left}    {right}")
    print()


def display_hexdump(base_addr: int, words: List[int]):
    print(f"\n{C.BOLD}  Дамп памяти  0x{base_addr:08X} – "
          f"0x{base_addr + len(words)*4 - 1:08X}"
          f"  ({len(words)} слов = {len(words)*4} байт){C.RESET}")
    print("  " + "─" * 74)
    WORDS_PER_ROW = 4
    for row in range(0, len(words), WORDS_PER_ROW):
        chunk = words[row: row + WORDS_PER_ROW]
        addr  = base_addr + row * 4
        raw_bytes = b"".join(struct.pack("<I", w) for w in chunk)
        hex_parts = []
        for i in range(WORDS_PER_ROW):
            if i < len(chunk):
                val = chunk[i]
                if val == 0:
                    hex_parts.append(f"{C.DIM}00000000{C.RESET}")
                elif val == 0xFFFFFFFF:
                    hex_parts.append(f"{C.YELLOW}FFFFFFFF{C.RESET}")
                else:
                    hex_parts.append(f"{val:08X}")
            else:
                hex_parts.append("        ")
        hex_str = "  ".join(hex_parts)
        ascii_str = "".join(
            chr(b) if 0x20 <= b < 0x7F else "." for b in raw_bytes
        )
        print(f"  {C.CYAN}0x{addr:08X}{C.RESET}  {hex_str}  {C.DIM}{ascii_str}{C.RESET}")
    print()


# ---------------------------------------------------------------------------
# Дизассемблер
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


# ---------------------------------------------------------------------------
# Тесты
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
            dbg.sync_reset()
            time.sleep(0.05)
            dbg.cpu_output_buf.clear()
            dbg.halt()
            dbg.upload_hex(str(hex_file), progress=False)
            dbg.reset_pc(0)
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
# CLI
# ---------------------------------------------------------------------------
def list_ports():
    ports = list(serial.tools.list_ports.comports())
    if not ports:
        print("Последовательные порты не найдены.")
        return
    print("Доступные порты:")
    for p in ports:
        print(f"  {p.device:<12s} {p.description}")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Тестер RISC-V процессора через UART",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Примеры:
  python riscv_tester.py --list-ports
  python riscv_tester.py -p COM4 --capture
  python riscv_tester.py -p COM4 --step 20
  python riscv_tester.py -p COM4 --memdump 0x0:64
  python riscv_tester.py -p COM4 --upload program.hex
  python riscv_tester.py -p COM4 --tests tests/
""")

    g = p.add_argument_group("Подключение")
    g.add_argument("--port",    "-p", help="COM-порт")
    g.add_argument("--baud",    "-b", type=int, default=115200)
    g.add_argument("--timeout",       type=float, default=1.0,
                   metavar="SEC", help="Таймаут команды (по умолч 1.0)")
    g.add_argument("--list-ports", action="store_true")

    g = p.add_argument_group("Инспекция")
    g.add_argument("--memdump", metavar="ADDR[:COUNT]", action="append",
                   help="Hexdump памяти (можно несколько раз)")
    g.add_argument("--step", type=int, metavar="N",
                   help="N шагов с дизассемблированием")

    g = p.add_argument_group("Захват вывода")
    g.add_argument("--capture", action="store_true")
    g.add_argument("--idle-timeout",  type=float, default=2.0, metavar="SEC")
    g.add_argument("--total-timeout", type=float, default=30.0, metavar="SEC")

    g = p.add_argument_group("Программирование и тесты")
    g.add_argument("--upload", "-u", metavar="HEX",
                   help="Загрузить hex и запустить CPU")
    g.add_argument("--tests", "-t", metavar="DIR",
                   help="Каталог tests/ для прогона")
    g.add_argument("--no-upload", action="store_true")
    g.add_argument("filter", nargs="?",
                   help="Фильтр имени теста")
    return p


def main():
    parser = build_parser()
    args   = parser.parse_args()

    if args.list_ports:
        list_ports()
        return

    if not args.port:
        print("Укажите --port или --list-ports")
        parser.print_usage()
        sys.exit(1)

    print(f"{C.CYAN}Подключение к {args.port} @ {args.baud}…{C.RESET}")
    try:
        dbg = RiscVDebug(args.port, args.baud, timeout=args.timeout)
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

    if args.step:
        any_action = True
        _cmd_step(dbg, args.step)

    if args.memdump:
        any_action = True
        for spec in args.memdump:
            _cmd_memdump(dbg, spec)

    if args.capture:
        any_action = True
        _cmd_capture(dbg, args.idle_timeout, args.total_timeout)

    if args.upload:
        any_action = True
        _cmd_upload(dbg, args.upload, args.idle_timeout, args.total_timeout)

    if args.tests:
        any_action = True
        _cmd_tests(dbg, args)

    if not any_action:
        print("Укажите действие: --step, --memdump, --capture, "
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


def _cmd_memdump(dbg: RiscVDebug, spec: str):
    try:
        base_addr, word_count = _parse_memdump_spec(spec)
    except ValueError as e:
        print(f"  {C.RED}Неверный формат: {e}{C.RESET}")
        return
    print(f"\n{C.BOLD}=== Дамп памяти  0x{base_addr:08X} : {word_count} слов ==={C.RESET}")
    try:
        dbg.halt()
        words = dbg.read_memory_range(base_addr, word_count, progress=True)
    except Exception as e:
        print(f"  {C.RED}Ошибка: {e}{C.RESET}")
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
    try:
        dbg.sync_reset()
        time.sleep(0.05)
        dbg.halt()
        print(f"  {C.GREEN}CPU остановлен.{C.RESET}")
        dbg.upload_hex(hex_path, base_addr=0, progress=True)
        dbg.reset_pc(0)
        print(f"  {C.GREEN}PC=0x00000000{C.RESET}")
        dbg.resume()
        print(f"  {C.GREEN}CPU запущен.{C.RESET}")
    except Exception as e:
        print(f"  {C.RED}Ошибка: {e}{C.RESET}")
        return
    print(f"  Жду вывод…")
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


if __name__ == "__main__":
    main()
