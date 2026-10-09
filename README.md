# Arya OS

A bare-metal x86 kernel built from scratch in C and x86 assembly — bootloader through preemptive multitasking, with no OS underneath.

Built as a systems-level counterpart to hardware/RTL work: a way to understand the hardware/software boundary from the software side, one layer at a time.

---

## Features

- **Bootloader** — GRUB multiboot header, boots straight into 32-bit protected mode
- **GDT** — flat memory model, kernel code/data segments
- **IDT + ISR/IRQ stubs** — full 256-entry interrupt table, exception and hardware interrupt dispatch
- **PIC remapping** — 8259 PIC remapped off the CPU's reserved exception vectors
- **Keyboard driver** — IRQ1, scancode-to-ASCII translation, feeds a live shell
- **Timer** — IRQ0 via the PIT, 100Hz tick, drives the scheduler
- **Physical memory allocator** — bitmap-based, tracks 4KB pages from multiboot memory info
- **Paging / virtual memory** — page directory + page table, identity-mapped, CR3/CR0 enabled
- **Preemptive round-robin scheduler** — hand-written context switch (register save/restore via the stack), timer-interrupt-driven task switching
- **Interactive shell** — `arya>` prompt, keyboard-driven, with built-in commands

---

## Shell commands

| Command | Description |
|---|---|
| `help` | List available commands |
| `meminfo` | Show free physical memory (blocks and KB) |
| `uptime` | Show timer ticks and elapsed seconds |
| `about` | Print OS info |
| `clear` | Clear the screen |

---

## Architecture

```
┌─────────────────────────────────────────────┐
│                 boot.s                       │
│   GRUB multiboot header → _start             │
│   sets up stack, pushes multiboot args       │
└───────────────────┬───────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────┐
│               kernel_main()                  │
│                                               │
│  gdt_install()   → flat GDT, segment reload  │
│  idt_install()   → 256-entry IDT             │
│  isr_install()   → exception/IRQ gates       │
│  pic_remap()     → 8259 remap to 0x20/0x28   │
│  keyboard_install() → IRQ1 handler           │
│  timer_install() → IRQ0 @ 100Hz (PIT)        │
│  pmm_init()      → bitmap physical allocator │
│  paging_init()   → page dir/table, CR3/CR0   │
│  shell_init()    → arya> prompt              │
└───────────────────┬───────────────────────────┘
                    │
                    ▼
        ┌───────────────────────┐
        │   Interrupt-driven     │
        │   event loop (hlt)     │
        │                        │
        │  Timer IRQ  → schedule()          │
        │  Keyboard IRQ → shell_handle_char()│
        └───────────────────────┘
```

### Preemptive scheduler

Round-robin, timer-driven. Each task gets a 4KB stack; `task_create()` builds a fake initial stack frame so a brand-new task's first "resume" looks identical to a real context switch — landing in a small launcher stub (`task_launch`) that re-enables interrupts (`sti`) before jumping to the task's actual entry point.

This matters because interrupt gates clear the CPU's interrupt flag on entry, and a raw `ret`-based context switch (as opposed to `iret`) doesn't restore it — without the launcher stub, a freshly-switched-to task would run forever with interrupts silently disabled, and the timer could never preempt it again.

```
context_switch(&prev->esp, next->esp):
    push ebp, ebx, esi, edi     ; save current task's registers
    save esp into *prev_esp     ; bookmark current task
    load esp from next_esp      ; switch stacks
    pop edi, esi, ebx, ebp      ; restore next task's registers
    ret                         ; resume next task
```

---

## Project structure

```
arya-os/
├── boot/
│   ├── boot.s              # multiboot header, protected mode entry
│   ├── gdt_flush.s         # loads GDT, reloads segment registers
│   ├── idt_flush.s         # loads IDT
│   ├── interrupt.s         # ISR/IRQ stubs (0-19 exceptions, 0-15 IRQs)
│   ├── paging_asm.s        # loads CR3, sets paging bit in CR0
│   ├── context_switch.s    # register save/restore, task_launch stub
│   └── linker.ld           # kernel link script (loads at 1MB)
├── include/
│   ├── io.h                # inb/outb port I/O
│   ├── gdt.h / idt.h       # GDT/IDT structures and install routines
│   ├── isr.h               # interrupt dispatch, registers_t struct
│   ├── pic.h                # 8259 PIC remap/EOI
│   ├── keyboard.h / timer.h # driver interfaces
│   ├── multiboot.h         # multiboot info struct
│   ├── pmm.h / paging.h    # physical/virtual memory management
│   ├── task.h               # TCB, scheduler interface
│   └── shell.h              # shell interface
├── src/
│   ├── kernel.c             # kernel_main, VGA terminal, boot sequence
│   ├── gdt.c / idt.c / isr.c
│   ├── pic.c / keyboard.c / timer.c
│   ├── pmm.c                # bitmap physical memory allocator
│   ├── paging.c              # page directory/table management
│   ├── task.c                # task creation, round-robin scheduler
│   └── shell.c                # command parsing, built-in commands
├── isodir/boot/grub/
│   └── grub.cfg              # GRUB menu entry
└── Makefile
```

---

## Building and running

### Prerequisites (WSL2 Ubuntu)

```bash
sudo apt update
sudo apt install -y build-essential bison flex libgmp3-dev libmpc-dev \
    libmpfr-dev texinfo libisl-dev nasm qemu-system-x86 grub-pc-bin \
    grub-common xorriso mtools gdb
```

An `i686-elf` cross-compiler (built from binutils 2.42 + gcc 13.2.0) is required — kernel code targets bare-metal x86, not the host's Linux toolchain. See build notes below if it's not already in `~/opt/cross`.

### Build and run

```bash
make run
```

Builds the kernel, links it, packages it into a GRUB-bootable ISO, and boots it in QEMU. You should see:

```
GNU GRUB version 2.12
> Arya OS
```

Booting into it shows:

```
Hello, Arya OS!
Free blocks: 00007ED9
Starting preemptive tasks:
arya>
```

Try `help`, `meminfo`, `uptime`, `about`, `clear`.

### Cross-compiler build (one-time setup)

```bash
export PREFIX="$HOME/opt/cross"
export TARGET=i686-elf
export PATH="$PREFIX/bin:$PATH"

mkdir -p ~/src && cd ~/src
curl -O https://ftp.gnu.org/gnu/binutils/binutils-2.42.tar.gz
curl -O https://ftp.gnu.org/gnu/gcc/gcc-13.2.0/gcc-13.2.0.tar.gz
tar xf binutils-2.42.tar.gz && tar xf gcc-13.2.0.tar.gz

mkdir build-binutils && cd build-binutils
../binutils-2.42/configure --target=$TARGET --prefix="$PREFIX" --with-sysroot --disable-nls --disable-werror
make -j$(nproc) && make install
cd ..

mkdir build-gcc && cd build-gcc
../gcc-13.2.0/configure --target=$TARGET --prefix="$PREFIX" --disable-nls --enable-languages=c --without-headers
make all-gcc -j$(nproc)
make all-target-libgcc -j$(nproc)
make install-gcc
make install-target-libgcc
```

Add `export PATH="$HOME/opt/cross/bin:$PATH"` to `~/.bashrc`.

---

## Why x86

QEMU emulates x86 regardless of host architecture, and 32-bit protected mode has decades of documentation (OSDev wiki, Intel SDM) and mature tooling (GRUB multiboot, QEMU, GDB) that make it the most direct path for a bare-metal OS from scratch — no custom bootloader or thin hobbyist toolchain required. The underlying concepts (interrupt handling, paging, context switching) transfer directly to any architecture.

---

## Known bugs found and fixed along the way

- **Missing `boot/linker.ld` / `grub.cfg`** — heredoc writes silently failed at different points; caught by GRUB dropping to a rescue shell instead of loading the kernel.
- **`context_switch` fake stack frame register order** — the pushed dummy register order didn't match `context_switch`'s pop order (`edi, esi, ebx, ebp`), so a new task's smuggled entry point landed in the wrong register (`esi` instead of `ebx`), causing a jump to address 0 and a triple fault.
- **Interrupt flag not restored after context switch** — a raw `ret`-based switch (rather than `iret`) doesn't restore `EFLAGS`, so a freshly-switched task ran forever with interrupts disabled and could never be preempted again. Fixed with a `task_launch` stub that explicitly re-enables interrupts (`sti`) before running new tasks.
- **cdecl argument order in `boot.s`** — multiboot magic/info pointer were pushed in the wrong order for `kernel_main(magic, mbi)`'s calling convention (args pushed right-to-left).

---

## Scope

Deliberately excludes: filesystem, disk I/O drivers, a graphical UI, process isolation (user/kernel mode separation), and networking. This was scoped as a focused systems-programming exercise covering boot, memory management, and concurrency — not a general-purpose OS.

---

## Author

Rakshith Suresh
MS Electrical Engineering, USC Viterbi School of Engineering
