#include <stdio.h>

/***********************************
 ** dos headers (fake on non-dos) **
 ***********************************/

#if (defined __BORLANDC__)
#  include <conio.h>
#  include <dos.h>

#  define bool  unsigned char
#  define false (0)
#  define true  (1)
#else
#  include <stdbool.h>

#  include "include/borland/conio.h"
#  include "include/borland/dos.h"

#  define _dos_getvect(ADDR_)           ((void *)0)
#  define _dos_setvect(ADDR_, HANDLER_) ((void)0)

#  define FP_SEG(FP_) (*(FP_ + 1))
#  define FP_OFF(FP_) (*FP_)

#  define _SP (0)
#  define _DS ((void *)0)
#  define _CS ((void *)0)
#endif

/***********************
 ** program constants **
 ***********************/

#define MASTER_INTERRUPT_REG (0x08)
#define SLAVE_INTERRUPT_REG  (0x70)

#define USER_MASTER_INTERRUPT_REG (0xD8)
#define USER_SLAVE_INTERRUPT_REG  (0x08)

#define MASTER_INTERRUPT_MASK (0x00)
#define SLAVE_INTERRUPT_MASK  (0x10)

/******************
 ** conviniences **
 ******************/

#define elsizeof(ARR_) (sizeof(*ARR_))
#define lenof(ARR_)    (sizeof(ARR_) / elsizeof(ARR_))

typedef void interrupt (*InterruptHandler)(void);

/*************
 ** program **
 *************/

static struct text_info info = {0};

static InterruptHandler old_master_handlers[8] = {0},
                        old_slave_handlers[8] = {0};

static void pic_init(
    unsigned char const new_master_interrupt_reg,
    unsigned char const new_slave_interrupt_reg,
    unsigned char const master_interrupt_mask,
    unsigned char const slave_interrupt_mask
) {
    /* docs:
     * - https://wiki.osdev.org/8259_PIC#Programming_with_the_8259_PIC
     * - http://www.brokenthorn.com/Resources/OSDevPic.html
     */

    disable();

    // init procedure for pic: ICW1 = 0x11
    outportb(0x20, 0x11), outportb(0xA0, 0x11);
    // ICW2 = <new addr>
    outportb(0x21, new_master_interrupt_reg),
        outportb(0xA1, new_slave_interrupt_reg);
    // ICW3 = <bit mask> (for master) and <index> (for slave)
    outportb(0x21, 0x4), outportb(0xA1, 2);
    // ICW4 = 0x1 (to select 80x86 mode)
    outportb(0x21, 0x1), outportb(0xA1, 0x1);

    outportb(0x21, master_interrupt_mask), outportb(0xA1, slave_interrupt_mask);

    enable();
}

// `freq` (1 to 15), where the real value = `32768 >> (freq - 1)`
static void rtc_start(unsigned const freq, bool const is_periodic) {
    /* docs:
     * - https://www.cs.fsu.edu/~baker/realtime/restricted/notes/rtc2.html
     * - https://www.xtof.info/Timing-on-PC-familly-under-DOS.html */

    disable();

    outportb(0x70, 0x8A), outportb(0x71, inportb(0x71) & ~0x0F | freq);
    outportb(0x70, 0x8B), outportb(0x71, inportb(0x71) | (is_periodic << 6));
    outportb(0x70, 0x0D), inportb(0x71);

    enable();
}

static void display(
    char const interrupt_controller_char,
    unsigned const bottom_offset,
    unsigned char const irr,
    unsigned char const isr,
    unsigned char const imr
) {
    static char far *const screen = (char far *)0xB8000000;

    static char buf[] =
        "X info: irr = 00000000, isr = 00000000, imr = 00000000";
    static char *const irr_buf = buf + lenof("X info: irr = ") - 1;
    static char *const isr_buf =
        buf + lenof("X info: irr = 00000000, isr = ") - 1;
    static char *const imr_buf =
        buf + lenof("X info: irr = 00000000, isr = 00000000, imr = ") - 1;

    unsigned i, j;

    // if on master and got timer interrupt - clear last two lines
    if (interrupt_controller_char == 'M' && isr & 0x01)
        for (i = 0; i < info.screenwidth * 2; i++)
            screen[2 * ((info.screenheight - 1 - 1) * info.screenwidth + i)] =
                ' ';

    buf[0] = interrupt_controller_char;
#define itoa_binary(NUM_, STR_)                                                \
    for (i = 0; i < 8; i++) STR_[i] = (NUM_ >> (7 - i)) & 1 ? '1' : '0'

    itoa_binary(irr, irr_buf);
    itoa_binary(isr, isr_buf);
    itoa_binary(imr, imr_buf);
#undef itoa_binary

    for (i = 0; buf[i] != '\0'; i++) {
        screen
            [2 * ((info.screenheight - bottom_offset - 1) * info.screenwidth + i
                 )] = buf[i];
    }
}

static unsigned first_switched_bit(unsigned num) {
    unsigned i;

    for (i = 0; i < sizeof(num) * 8; i++)
        if ((num >> i) & 1) break;

    return i;
}
static void user_any_interrupt_handler(bool const is_master) {
    unsigned char irr, isr, imr;

    disable();
    if (is_master) {
        irr = (outportb(0x20, 0x0A), inportb(0x20));
        isr = (outportb(0x20, 0x0B), inportb(0x20));
        imr = inportb(0x21);

        display('M', 0, irr, isr, imr);
        // call the old handler with ISR bitmask translated to IRQ number
        old_master_handlers[first_switched_bit(isr)]();

        // need to send EOI to the master PIC
        outportb(0x20, 0x20);
    } else {
        irr = (outportb(0xA0, 0x0A), inportb(0xA0));
        isr = (outportb(0xA0, 0x0B), inportb(0xA0));
        imr = inportb(0xA1);

        display('S', 1, irr, isr, imr);
        // the same as above
        old_slave_handlers[first_switched_bit(isr)]();

        // need to send EOI to both PICs
        outportb(0xA0, 0x20), outportb(0x20, 0x20);
    }
    enable();
}
static void interrupt user_master_interrupt_handler(void) {
    user_any_interrupt_handler(true);
}
static void interrupt user_slave_interrupt_handler(void) {
    user_any_interrupt_handler(false);
}

static void make_resident(void) {
    unsigned far *fp;

    FP_SEG(fp) = _psp, FP_OFF(fp) = 0x2C;
    _dos_freemem(*fp);

    _dos_keep(0, (_DS - _CS) + (_SP / 16) + 1);
}

int main() {
    unsigned i;

    gettextinfo(&info);

    // save old handlers
    for (i = 0; i < lenof(old_master_handlers); i++)
        old_master_handlers[i] = _dos_getvect(MASTER_INTERRUPT_REG + i);
    for (i = 0; i < lenof(old_slave_handlers); i++)
        old_slave_handlers[i] = _dos_getvect(SLAVE_INTERRUPT_REG + i);

    // remap interrupt registers and setup masks
    pic_init(
        USER_MASTER_INTERRUPT_REG,
        USER_SLAVE_INTERRUPT_REG,

        MASTER_INTERRUPT_MASK,
        SLAVE_INTERRUPT_MASK
    );

    // register new handlers
    for (i = 0; i < lenof(old_master_handlers); i++)
        _dos_setvect(
            USER_MASTER_INTERRUPT_REG + i,
            user_master_interrupt_handler
        );
    for (i = 0; i < lenof(old_slave_handlers); i++)
        _dos_setvect(
            USER_SLAVE_INTERRUPT_REG + i,
            user_slave_interrupt_handler
        );

    // timer for proper testing
    rtc_start(15, true);

    make_resident();
    // if making resident fails, exit with error code
    return 1;
}
