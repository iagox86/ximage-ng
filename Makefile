all: load run

run: run.c
	gcc -m32 -Wall -g -Os -o run run.c

load: load.asm
	nasm -o load load.asm

clean:
	rm -f load run test_code* core
