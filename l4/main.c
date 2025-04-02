#include <stdio.h>

/***********************************
 ** dos headers (fake on non-dos) **
 ***********************************/

#if (defined __BORLANDC__)
#  include <conio.h>
#  include <dos.h>
#else

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

/******************
 ** conviniences **
 ******************/

#define elsizeof(ARR_) (sizeof(*ARR_))
#define lenof(ARR_)    (sizeof(ARR_) / elsizeof(ARR_))

/*************
 ** program **
 *************/

/* static void print_timer_channels(void) {
    unsigned char states[3];
    unsigned counters[3];

    states[0] = (outportb(0x43, 0xE2), inportb(0x40));
    states[1] = (outportb(0x43, 0xE4), inportb(0x41));
    states[2] = (outportb(0x43, 0xE8), inportb(0x42));

    counters[0] = (outportb(0x43, 0x00), inportb(0x40) | (inportb(0x40) << 8));
    counters[1] = (outportb(0x43, 0x40), inportb(0x41) | (inportb(0x41) << 8));
    counters[2] = (outportb(0x43, 0x80), inportb(0x42) | (inportb(0x42) << 8));

#define binfmt        "i%i%i%i%i%i%i%i"
#define bit(I_, NUM_) ((NUM_ >> I_) & 1)
#define tobinfmt(NUM_)                                                         \
    bit(7, NUM_), bit(6, NUM_), bit(5, NUM_), bit(4, NUM_), bit(3, NUM_),      \
        bit(2, NUM_), bit(1, NUM_), bit(0, NUM_)

    printf(
        "RS = %" binfmt ", %" binfmt ", %" binfmt
        "\n"

        "CE = %" binfmt ", %" binfmt ", %" binfmt "\n\n",

        tobinfmt(states[0]),
        tobinfmt(states[1]),
        tobinfmt(states[2]),

        tobinfmt(counters[0]),
        tobinfmt(counters[1]),
        tobinfmt(counters[2])
    );
#undef binfmt
}

static void beep(unsigned frequency, unsigned duration_ms) {
    if (frequency) {
        frequency = 1193180l / frequency;

        outportb(0x43, 0xB6);

        outportb(0x42, (unsigned char)frequency),
            outportb(0x42, (unsigned char)(frequency >> 8));

        outportb(0x61, inportb(0x61) | 0x03);
    }

    delay(duration_ms);

    outportb(0x61, inportb(0x61) & ~0x03);

    print_timer_channels();
} */

/***************
 ** constants **
 ***************/

#define LOOP_ITER_LIMIT        (60 * 10)
#define LOADING_INDICATOR_FREQ (8192)
#define DELAY_LIMIT            (10000)

/************
 ** task 1 **
 ************/

#define CMOS_REG_READ(ADDR_) (outportb(0x70, (ADDR_)), inportb(0x71))
#define CMOS_REG_WRITE(ADDR_, VALUE_)                                          \
    (outportb(0x70, (ADDR_)), outportb(0x71, (VALUE_)))

int wait_til_regs_available(void) {
    static char const loading_indicator[] = {'-', '\\', '|', '/'};
    unsigned long i;

    for (i = 0; i < LOOP_ITER_LIMIT * 65536l; i++) {
        if (CMOS_REG_READ(0x0A) & (1 << 7)) return 0;
        if (i % LOADING_INDICATOR_FREQ == 0)
            printf(
                "%c \b\b",
                loading_indicator
                    [(i / LOADING_INDICATOR_FREQ) % lenof(loading_indicator)]
            );
    }

    return 1;
}

int get_time_task(void) {
    unsigned h, m, s;

    if (wait_til_regs_available() != 0) return printf("Regs unavailable!\n"), 1;

#define BCD2TIMECOMP(BCD_) ((BCD_) / 16 * 10 + (BCD_) % 16)
    h = BCD2TIMECOMP(CMOS_REG_READ(0x04));
    m = BCD2TIMECOMP(CMOS_REG_READ(0x02));
    s = BCD2TIMECOMP(CMOS_REG_READ(0x00));
#undef BCD2TIMECOMP

    printf("Time: %02u:%02u:%02u\n", h, m, s);

    return 0;
}

int set_time_task(void) {
    unsigned i;
    unsigned h, m, s;

    if (wait_til_regs_available() != 0) return printf("Regs unavailable!\n"), 1;

    printf("Input time in the following format - 'hh:mm:ss': ");
    while (scanf(" %u:%u:%u", &h, &m, &s) != 3 || h >= 24 || m >= 60 || s >= 60)
        fflush(stdin), printf("Invalid format! Try again: ");

    CMOS_REG_WRITE(0x0B, CMOS_REG_READ(0x0B) | (1 << 7));

#define TIMECOMP2BCD(TC_) ((TC_) / 10 * 16 + (TC_) % 10)
    CMOS_REG_WRITE(0x04, TIMECOMP2BCD(h));
    CMOS_REG_WRITE(0x02, TIMECOMP2BCD(m));
    CMOS_REG_WRITE(0x00, TIMECOMP2BCD(s));
#undef TIMECOMP2BCD

    CMOS_REG_WRITE(0x0B, CMOS_REG_READ(0x0B) & ~(1 << 7));

    return 0;
}

/**************
 ** task 2.1 **
 **************/

unsigned delay_remaining_ms = 0;

void interrupt (*old_rtc_intr_handler)(void) = NULL;
void interrupt new_rtc_intr_handler(void) {
    disable();
    delay_remaining_ms--;
    if (delay_remaining_ms == 0) {
        _dos_setvect(0x70, old_rtc_intr_handler), old_rtc_intr_handler = NULL;
        CMOS_REG_WRITE(0x0B, CMOS_REG_READ(0x0B) & ~(1 << 6));
        CMOS_REG_READ(0x0C);

        printf("\n(delay finished!)\n");
        goto end;
    }

    old_rtc_intr_handler();

end:
    outportb(0xA0, 0x20), outportb(0x20, 0x20), enable();
}
// `freq` (1 to 15), the real freq = `32768 >> (freq - 1)`
void my_delay(unsigned const ms, unsigned const freq) {
    if (ms == 0) return;

    CMOS_REG_WRITE(0x0A, CMOS_REG_READ(0x0A) & ~0xF | freq);
    CMOS_REG_WRITE(0x0B, CMOS_REG_READ(0x0B) | (1 << 6));

    delay_remaining_ms = (delay_remaining_ms + ms) >= DELAY_LIMIT
                           ? DELAY_LIMIT - 1
                           : delay_remaining_ms + ms;

    if (old_rtc_intr_handler) return;  // interrupt already configured

    old_rtc_intr_handler = _dos_getvect(0x70);
    _dos_setvect(0x70, new_rtc_intr_handler);
}
void delay_task(void) {
    unsigned delay;
    unsigned imr;

    printf("How many ms? ");
    scanf(" %u", &delay);

    my_delay(delay, 6);
}

/**************
 ** task 2.1 **
 **************/

void alarm_task(void) { printf("Alarm task not implemented!\n"); }

#undef CMOS_REG_WRITE
#undef CMOS_REG_READ

/**********
 ** main **
 **********/

int main() {
    int choice;

    do {
        printf(
            "Select action (0 - exit, 1 - get time, 2 - set time, 3 - delay, 4 - alarm): "
        );
        scanf(" %d", &choice);

        switch (choice) {
        case 1: get_time_task(); break;
        case 2: set_time_task(); break;
        case 3: delay_task(); break;
        case 4: alarm_task(); break;
        case 0: printf("byebye!\n"); break;
        default: fflush(stdin), printf("Invalid!\n"); break;
        }
    } while (choice != 0);

    return 0;
}
