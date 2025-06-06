CC = gcc
CFLAGS = -std=c99 -m32 -shared -fPIC -ldl -D_POSIX_PTHREAD_SEMANTICS
TARGET = mailq.so
SRC = src/execve-log.c
OS := $(shell uname)

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)
