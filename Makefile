all: load run run_raw_code

run: run.c
	gcc -m32 -Wall -g -Os -o run run.c

run_raw_code: run_raw_code.c
	gcc -m32 -Wall -g -Os -o run_raw_code.c

load: load.asm
	nasm -o load load.asm

clean:
	rm -f load run test_code* core run_raw_code
