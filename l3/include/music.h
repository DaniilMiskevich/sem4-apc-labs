#ifndef MUSIC_H
#define MUSIC_H

#include <stdio.h>
#include <string.h>

int music_play(void (*const beep)(unsigned, unsigned));
void music_end(void);
void music_set_speed(int const speed);

#endif
