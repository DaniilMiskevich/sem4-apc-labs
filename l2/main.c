#include <stdio.h>
#include <string.h>

#if (defined __BORLANDC__)
#  include <conio.h>
#  include <dos.h>
#else
#  include "include/borland/conio.h"
#  include "include/borland/dos.h"

#  define _dos_getvect(ADDR_)           ((void *)0)
#  define _dos_setvect(ADDR_, HANDLER_) ((void)0)
#endif

#define elsizeof(ARR_) (sizeof(*ARR_))
#define lenof(ARR_)    (sizeof(ARR_) / elsizeof(ARR_))

static void interrupt (*system_master_handlers[8])(void),
    (*system_slave_handlers[8])(void);

static void multi_interrupt_handler(
    int const port,
    unsigned const bottom_offset,
    void interrupt (**const system_handlers)(void)
) {
    static char far *const screenbuf = (char far *)0xB8000000;

    static char buf[80] = {0};
    static struct text_info info;

    unsigned char interrupt_request, interrupt_in_service, interrupt_mask;
    unsigned i;

    gettextinfo(&info);

    outportb(port, 0x0A), interrupt_request = inportb(port);
    outportb(port, 0x0B), interrupt_in_service = inportb(port);
    interrupt_mask = inportb(port + 1);

#define binfmt "1i%1i%1i%1i%1i%1i%1i%1i"
#define tobinfmt(BYTE_)                                                        \
    (BYTE_ >> 7) & 1, (BYTE_ >> 6) & 1, (BYTE_ >> 5) & 1, (BYTE_ >> 4) & 1,    \
        (BYTE_ >> 3) & 1, (BYTE_ >> 2) & 1, (BYTE_ >> 1) & 1, (BYTE_ >> 0) & 1
    sprintf(
        buf,
        "interrupt info: request = %" binfmt ", in service = %" binfmt
        ", mask = %" binfmt,
        tobinfmt(interrupt_request),
        tobinfmt(interrupt_in_service),
        tobinfmt(interrupt_mask)
    );
#undef binfmt
#undef tobinfmt

    /* if (port == 0x20 && interrupt_in_service == 1) {
        for (j = 0; j < 2; j++)
            for (i = 0; i < info.screenwidth; i++) {
                screenbuf
                    [2 * ((info.screenheight - 1 - 1) * info.screenwidth + i)] =
                        '!';
            }
    } */

    for (i = 0; buf[i] != '\0'; i++) {
        screenbuf
            [2 * ((info.screenheight - bottom_offset - 1) * info.screenwidth + i
                 )] = buf[i];
    }

    system_handlers[interrupt_in_service]();
}
static interrupt void my_master_handler() {
    multi_interrupt_handler(0x20, 0, system_master_handlers);
};
static interrupt void my_slave_handler() {
    multi_interrupt_handler(0xA0, 1, system_slave_handlers);
};

static void make_resident(void) {
#if (defined __BORLANDC__)
    unsigned far *fp;
    FP_SEG(fp) = _psp;  // получаем сегмент
    FP_OFF(fp) = 0x2c;  // и смещение сегмента данных с переменными среды
    _dos_freemem(*fp);  // чтобы его освободить

    _dos_keep(
        0,  // exit with 0
        (_DS - _CS) + (_SP / 16) + 1
    );  // оставляем резидентной, указывая
        // //первым параметром код завершения, а
        // //вторым - объем памяти, который должен
        // //быть зарезервирован для программы
        // //после ее завершения
#endif
}

static void start_rtc(void) {
    unsigned char rtc_val;

    outportb(0x70, 0x8B);
    rtc_val = inportb(0x71);
    outportb(0x70, 0x8B);

    outportb(0x71, rtc_val | 0x40);
}

int main() {
    unsigned i;

    start_rtc();

    outportb(0x21, 0x00), outportb(0xA1, 0x10);

    for (i = 0; i < lenof(system_master_handlers); i++) {
        // if (i == 2) continue;
        system_master_handlers[i] = _dos_getvect(0x08 + i);
        _dos_setvect(0x08 + i, my_master_handler);
    }
    for (i = 0; i < lenof(system_slave_handlers); i++) {
        system_slave_handlers[i] = _dos_getvect(0x70 + i);
        _dos_setvect(0x70 + i, my_slave_handler);
    }

    // transfer hardware interrupts to user ones
    // add user interrupt handlers to:
    //  - print following registers of main and additional controllers to
    //  the same screen location:
    //      - IRQ
    //      - handled interrupts
    //      - interrupt mask
    make_resident();
    return 0;
}
