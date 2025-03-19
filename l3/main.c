#include <stdio.h>

#include "include/music.h"

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

/***********************
 ** program constants **
 ***********************/

/******************
 ** conviniences **
 ******************/

#define elsizeof(ARR_) (sizeof(*ARR_))
#define lenof(ARR_)    (sizeof(ARR_) / elsizeof(ARR_))

/*************
 ** program **
 *************/

static void print_timer_channels(void) {
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
}

int main(int const argc, char *const argv[]) {
    if (argc - 1 < 1) return 0;

    {
        FILE *file;
        MusicPlayer player = {0};

        file = fopen(argv[1], "r");
        if (!file) return 1;

        music_player_init(&player, 132, beep);
        music_player_play(&player, file);

        fclose(file);
    }

    return 0;
}
