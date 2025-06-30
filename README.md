# bfcz
This is a Brainfuck "compiler" writen in zig(0.14). It is not a real compiler because it just turns Brainfuck code into asm which needs further compilation.\
ex:
```bash 
zig build && ./zig-out/bin/BFCompiler program.bf | gcc -no-pie -x assembler -o program - && ./program
```
