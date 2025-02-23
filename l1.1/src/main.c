#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <termios.h>
#include <unistd.h>

#define elsizeof(ARR_)  (sizeof(ARR_[0]))
#define lenof(ARR_)     (sizeof(ARR_) / elsizeof(ARR_))
#define error(ARGS_...) (fprintf(stderr, ARGS_), fflush(stderr))

int com_configure(int const fd, int const baud, uint8_t const read_buf_len) {
    typedef struct termios termios;
    termios config = {0};

    config.c_cflag &= ~PARENB;                        // disable parity
    config.c_cflag &= ~CSTOPB;                        // single stop bit
    config.c_cflag &= ~CSIZE, config.c_cflag |= CS8;  // set symbol to be 8 bits
    // disable hardware control flow
#if (defined CRTSCTS)
    config.c_cflag &= ~CRTSCTS;
#endif
    config.c_cflag |= CLOCAL;  // disable modem-specific lines
    config.c_cflag |= CREAD;

    config.c_lflag &= ~ICANON;  // disable receiving data line-by-line
    // config.c_lflag &= ~ECHO & ~ECHOE & ~ECHONL;
    config.c_lflag &= ~ISIG;  // disable signals

    config.c_iflag &= ~(IXON | IXOFF | IXANY);  // disable software control flow
    config.c_iflag &= ~(IGNBRK | IGNCR | ICRNL | INLCR);  // keep special bytes
    config.c_iflag &= ~ISTRIP;                            // keep the eighth bit

    config.c_oflag &= ~(OPOST | ONLCR);  // keep special bytes

    // keep EOT
#if (defined ONOEOT)
    config.c_oflag &= ~ONOEOT;
#endif

    // keep tabs
#if (defined OXTABS)
    config.c_oflag &= ~OXTABS;
#elif (defined XTABS)
    config.c_oflag &= ~XTABS;
#endif

    config.c_cc[VMIN] = read_buf_len;

    cfsetispeed(&config, baud), cfsetospeed(&config, baud);

    return tcsetattr(fd, TCSADRAIN, &config);
}

int run(char const *const com_path) {
    int const com = open(com_path, O_RDWR);
    if (com < 0) {
        error("cannot open a port: %s\n", strerror(errno));
        return -1;
    }

    if (com_configure(com, B9600, 1) != 0)
        return close(com), error("error configuring the port\n"), 1;

    char data[256] = {0};

    // send
    fgets(data, lenof(data), stdin);
    if (write(com, data, strlen(data)) < 0)
        return close(com), error("error while sending data\n"), 2;

    // receive
    ssize_t read_len = 0;
    do {
        read_len = read(com, data, lenof(data));
        if (read_len < 0)
            return close(com), error("error while receiving data\n"), 3;
        fwrite(data, 1, read_len, stdout), fflush(stdout);
    } while (read_len > 0);
    printf("\n");

    close(com);

    return 0;
}

int main(int const argc, char const *const *const argv) {
    char const *const *const args = argv + 1;
    size_t const args_len = argc - 1;

    if (args_len < 1) return error("missing argument [0]\n"), -1;

    return run(args[0]);
}
