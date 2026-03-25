# MIG Setup for Arty A7-100T

Board: Digilent Arty A7-100T
FPGA: XC7A100TCSG324-1
DDR3 Chip: MT41K128M16JT-125 (Micron, 256MB, DDR3L 1.35V)
Source: DIGILENT_410-319-1.pdf

## Final MIG Summary (Validated)

### Vivado Project Options
- Target Device: xc7a100t-csg324
- Speed Grade: -1
- HDL: Verilog
- Module Name: mig_7series_0

### FPGA Options
| Parameter | Value |
|-----------|-------|
| System Clock Type | Single-Ended |
| System Clock Pin | E3 (Bank 35, 100 MHz) |
| Reference Clock Type | No Buffer |
| Debug Port | OFF |
| Internal Vref | Enabled |
| IO Power Reduction | ON |
| XADC Instantiation | Disabled |
| Internal Termination (HR Banks) | 50 Ohms |
| VCC_AUX IO | 1.8V |

### Controller 0 Options
| Parameter | Value |
|-----------|-------|
| Memory | DDR3_SDRAM |
| Interface | NATIVE (not AXI) |
| Design Clock Frequency | 3077 ps (324.99 MHz) |
| Phy to Controller Clock Ratio | 4:1 |
| Input Clock Period | 3076 ps |
| CLKFBOUT_MULT (PLL) | 4 |
| DIVCLK_DIVIDE (PLL) | 1 |
| Memory Type | Components |
| Memory Part | MT41K128M16XX-15E |
| Data Width | 16 |
| ECC | Disabled |
| Data Mask | Enabled |
| Ordering | Normal |

### Memory Options (MR Registers)
| Parameter | Value |
|-----------|-------|
| Burst Length (MR0[1:0]) | 8 - Fixed |
| Read Burst Type (MR0[3]) | Sequential |
| CAS Latency (MR0[6:4]) | 5 |
| Output Drive Strength (MR1[5,1]) | RZQ/6 (40 Ohm) |
| Controller CS option | Enable |
| Rtt_NOM - ODT (MR1[9,6,2]) | RZQ/6 (40 Ohm) |
| Rtt_WR - Dynamic ODT (MR2[10:9]) | Dynamic ODT off |
| Memory Address Mapping | BANK_ROW_COLUMN |
| System Reset Polarity | ACTIVE HIGH |

### Bank Selections
| Bank | Assignment |
|------|-----------|
| 34 T0 | DQ[0-7] |
| 34 T1 | DQ[8-15] |
| 34 T2 | Address/Ctrl-0 |
| 34 T3 | Address/Ctrl-1 |

### System Control Pins
| Signal | Pin | Bank |
|--------|-----|------|
| sys_clk_i | E3 | 35 |
| sys_rst | T13 | 14 |
| init_calib_complete | T10 | 14 |
| tg_compare_error | T11 | 14 |

## DDR3 Pin Assignments (from Digilent GitHub)

Source: https://github.com/Digilent/Arty/tree/master/Resources/Arty_MIG_DDR3
Imported via UCF file: Arty_C_mig.ucf

| Signal | FPGA Pin(s) |
|--------|-------------|
| ddr3_dq[0-15] | K5, L3, K3, L6, M3, M1, L4, M2, V4, T5, U4, V5, V1, T3, U3, R3 |
| ddr3_dm[0-1] | L1, U1 |
| ddr3_dqs_p[0-1] | N2, U2 |
| ddr3_dqs_n[0-1] | N1, V2 |
| ddr3_addr[0-13] | T8...R2 |
| ddr3_ba[0-2] | P2, P4, R1 |
| ddr3_ck_p[0] | U9 |
| ddr3_ck_n[0] | V9 |
| ddr3_ras_n | P3 |
| ddr3_cas_n | M4 |
| ddr3_we_n | P5 |
| ddr3_reset_n | K6 |
| ddr3_cke[0] | N5 |
| ddr3_odt[0] | R5 |
| ddr3_cs_n[0] | U8 |
| I/O Standard | SSTL135 / DIFF_SSTL135 |

## Important Notes

- sys_rst: tie to 1'b0 in top-level (ACTIVE HIGH, always inactive)
- init_calib_complete: connect to RAM_CONTROLLER.mig_init_calib_complete
- Output Drive Strength: RZQ/6 matches Digilent official mig.prj
- RTT (Rtt_NOM): RZQ/6 — per board doc (50 ohm trace impedance)
- Internal Termination: 50 Ohm — per board doc
- Reference: Xilinx UG586 (7 Series FPGAs Memory Interface Solutions User Guide)

## Code Interface (RAM_CONTROLLER.sv)

- CHUNK_PART = 128 bits (16-bit x BL8)
- ADDRESS_SIZE = 28 bits
- mig_app_wdf_mask = 16 bits (all zeros — full writes only)
- Commands: 3'b000 = Write, 3'b001 = Read
