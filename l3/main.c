#include "include/music.h"
#include <stdio.h>

/***********************************
 ** dos headers (fake on non-dos) **
 ***********************************/

#if (defined __BORLANDC__)
#include <conio.h>
#include <dos.h>

#define bool unsigned char
#define false (0)
#define true (1)
#else
#include <stdbool.h>

#include "include/borland/conio.h"
#include "include/borland/dos.h"

#define _dos_getvect(ADDR_) ((void *)0)
#define _dos_setvect(ADDR_, HANDLER_) ((void)0)

#define FP_SEG(FP_) (*(FP_ + 1))
#define FP_OFF(FP_) (*FP_)

#define _SP (0)
#define _DS ((void *)0)
#define _CS ((void *)0)
#endif

/***********************
 ** program constants **
 ***********************/

/******************
 ** conviniences **
 ******************/

#define elsizeof(ARR_) (sizeof(*ARR_))
#define lenof(ARR_) (sizeof(ARR_) / elsizeof(ARR_))

/*************
 ** program **
 *************/

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

static void beep(unsigned sound_frequency, unsigned sound_duration_ms) {
  if (sound_frequency == 0)
    return;

  sound_frequency = 1193180l / sound_frequency;

  outportb(0x43, 0xB6);

  outportb(0x42, (unsigned char)sound_frequency);
  outportb(0x42, (unsigned char)(sound_frequency >> 8));

  outportb(0x61, inportb(0x61) | 0x03);

  delay(sound_duration_ms);

  outportb(0x61, inportb(0x61) & ~0x03);
}

static void print_timer_channels(void) {
  unsigned state[3];

  state[0] = (outportb(0x43, 0xE2), inportb(0x40));
  state[1] = (outportb(0x43, 0xE4), inportb(0x41));
  state[2] = (outportb(0x43, 0xE8), inportb(0x42));

#define binfmt "i%i%i%i%i%i%i%i"
#define tobinfmt(NUM_)                                                         \
  ((NUM_ >> 7) & 1), ((NUM_ >> 6) & 1), ((NUM_ >> 5) & 1), ((NUM_ >> 4) & 1),  \
      ((NUM_ >> 3) & 1), ((NUM_ >> 2) & 1), ((NUM_ >> 1) & 1), (NUM_ & 1)
  printf("channel state: %" binfmt ", %" binfmt ", %" binfmt "\n",
         tobinfmt(state[0]), tobinfmt(state[1]), tobinfmt(state[2]));
#undef binfmt
}

int main(int const argc, char *const _[]) {
  if (argc > 1)
    music_play(beep);
  else
    print_timer_channels();

  return 0;
}
