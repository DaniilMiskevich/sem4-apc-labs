#include "include/music.h"

#if (!defined __BORLANDC__)
#include "include/borland/_null.h"
#endif

int music_speed = 200;

FILE *music_file;
char music_buffer[5];

unsigned sound_frequency, sound_duration;
unsigned char end;

int music_play(void (*const beep)(unsigned, unsigned)) {
  end = 0;
  music_file = fopen("theme.mus", "r");

  if (music_file == NULL)
    return -1;

  while (!end) {
    fscanf(music_file, "%s", music_buffer);

    if (strchr(music_buffer, ';'))
      break;

    if (strchr(music_buffer, ':'))
      fseek(music_file, 0, SEEK_SET);
    else {
      if (strstr(music_buffer, "..."))
        sound_duration = music_speed * 4;
      else if (strstr(music_buffer, ".."))
        sound_duration = music_speed * 3;
      else if (strchr(music_buffer, '.'))
        sound_duration = music_speed * 2;
      else
        sound_duration = music_speed;

      if (strstr(music_buffer, "Ab"))
        sound_frequency = 415;
      else if (strstr(music_buffer, "Bb"))
        sound_frequency = 466;
      else if (strstr(music_buffer, "Db"))
        sound_frequency = 554;
      else if (strstr(music_buffer, "Eb"))
        sound_frequency = 622;
      else if (strstr(music_buffer, "Gb"))
        sound_frequency = 740;
      else if (strstr(music_buffer, "ab"))
        sound_frequency = 831;
      else if (strstr(music_buffer, "bb"))
        sound_frequency = 932;

      else if (strchr(music_buffer, 'A'))
        sound_frequency = 440;
      else if (strchr(music_buffer, 'B'))
        sound_frequency = 494;
      else if (strchr(music_buffer, 'C'))
        sound_frequency = 523;
      else if (strchr(music_buffer, 'D'))
        sound_frequency = 587;
      else if (strchr(music_buffer, 'E'))
        sound_frequency = 659;
      else if (strchr(music_buffer, 'F'))
        sound_frequency = 699;
      else if (strchr(music_buffer, 'G'))
        sound_frequency = 784;
      else if (strchr(music_buffer, 'a'))
        sound_frequency = 880;
      else if (strchr(music_buffer, 'b'))
        sound_frequency = 988;
      else
        sound_frequency = 0;

      beep(sound_frequency, sound_duration);
    }
  }

  return 0;
}
void music_end() { end = 1; }
void music_set_speed(int const speed) { music_speed = speed; }
