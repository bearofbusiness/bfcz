```bash 
zig build && ./zig-out/bin/BFCompiler program.bf | gcc -no-pie -x assembler -o program - && ./program
```
