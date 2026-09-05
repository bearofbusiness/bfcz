# bfcz
This is a Brainfuck "compiler" writen in zig(0.16.0). It is not a real compiler because it just turns Brainfuck code into asm which needs further compilation.\
ex:
```bash 
zig build && ./zig-out/bin/BFCompiler --input bf-tests/cat.bf --output cat --optimize
```

## Roadmap 
- add extensions that adds more instructions like syscalls
- add preprocessing for function like macros
- add more optimization
