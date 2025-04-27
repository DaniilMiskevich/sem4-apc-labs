#include <stdio.h>
#include <stdlib.h>

#include <assert.h>

#if (defined __BORLANDC__)
__asm {
#  include <PMODE.ASM>
}
#endif

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

/************
 ** consts **
 ************/

#define LED_SL (1 << 0)
#define LED_NL (1 << 1)
#define LED_CL (1 << 2)

#define SCANCODE_ESC (0x01)

#define MAX_KB_SEND_ATTEMPT_COUNT (3)

/**********
 ** task **
 **********/

static unsigned volatile do_run = 0;
static int volatile send_result = 0;

static void interrupt (*old_intr_handler)(void) = NULL;
static void interrupt new_intr_handler(void) {
    unsigned ret_code = inportb(0x60);
    switch (ret_code) {
    case 0xFA: send_result = 1; break;
    case 0xFE: send_result = -1; break;

    case SCANCODE_ESC: do_run = 0; break;
    }

    printf("0x%X\n", ret_code);

    if (old_intr_handler) old_intr_handler();
    disable(), outportb(0xA0, 0x20), outportb(0x20, 0x20), enable();
}

static void intr_handler_set(void) {
    assert(old_intr_handler == NULL);
    old_intr_handler = _dos_getvect(0x09);
    _dos_setvect(0x09, new_intr_handler);
}
static void intr_handler_restore(void) {
    _dos_setvect(0x09, old_intr_handler), old_intr_handler = NULL;
}

static void kb_send(unsigned char cmd) {
    unsigned kb_send_attempt_count = 0;
    while (kb_send_attempt_count < MAX_KB_SEND_ATTEMPT_COUNT) {
        while (inportb(0x64) & (1 << 1));
        outportb(0x60, cmd);
        while (!send_result);

        switch (send_result) {
        case -1: send_result = 0, kb_send_attempt_count++; break;
        case 1: send_result = 0; return;
        }
    }

    printf("error sending byte. exiting...\n");
    intr_handler_restore(), exit(1);
}
static void kb_set_leds(unsigned leds) { kb_send(0xED), kb_send(leds); }

/**********
 ** main **
 **********/

int main() {
    unsigned i = 0;

    intr_handler_set();

    do_run = 1;
    while (do_run) {
        kb_set_leds(i++ & 7);
        delay(300);
    }

    intr_handler_restore();
    return 0;
}
