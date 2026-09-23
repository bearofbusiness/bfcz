; accepts a connection on port 8080(from 127.0.0.1).
; replies with an echo of the message recieved.

mac set(cell x){
  >cell[-]+x<cell
}
mac move(cells){
  >cells
}
; clears a given amount of cells (gt zero)
mac clear(bytes){
  [-]+bytes-[->[-]<[->+<]>]<bytes>
}
mac setptr(cell){
  !clear(8)
  +cell
  &
}
mac setptr2(high low){
  !clear(8)
  +low>+high<
  &
}

; clobbers all memory in the syscall region
; except for the registers specified by a value of -1
mac syscall(a b c d e f g){
  [-]++g[
    !move(48)
	!clear(8)
	+g
    !move(-48)
	[-]
  ]
  [-]++f[
    !move(40)
	!clear(8)
	+f
    !move(-40)
	[-]
  ]
  [-]++e[
    !move(32)
	!clear(8)
	+e
    !move(-32)
	[-]
  ]
  [-]++d[
    !move(24)
	!clear(8)
	+d
    !move(-24)
	[-]
  ]
  [-]++c[
    !move(16)
	!clear(8)
	+c
    !move(-16)
	[-]
  ]
  [-]++b[
    !move(8)
	!clear(8)
	+b
    !move(-8)
	[-]
  ]
  !clear(8)
  +a
  $
}

; 8 byte memory transfer
mac transfer8(from to){
  >to>to>to>to>to>to>to>to[-]>[-]>[-]>[-]>[-]>[-]>[-]>[-]<<<<<<<<to<to<to<to<to<to<to<to
  >from>from>from>from>from>from>from>from
  [-<from<from<from<from<from<from<from<from>to>to>to>to>to>to>to>to+<to<to<to<to<to<to<to<to>from>from>from>from>from>from>from>from]
  >[-<from<from<from<from<from<from<from<from>to>to>to>to>to>to>to>to+<to<to<to<to<to<to<to<to>from>from>from>from>from>from>from>from]
  >[-<from<from<from<from<from<from<from<from>to>to>to>to>to>to>to>to+<to<to<to<to<to<to<to<to>from>from>from>from>from>from>from>from]
  >[-<from<from<from<from<from<from<from<from>to>to>to>to>to>to>to>to+<to<to<to<to<to<to<to<to>from>from>from>from>from>from>from>from]
  >[-<from<from<from<from<from<from<from<from>to>to>to>to>to>to>to>to+<to<to<to<to<to<to<to<to>from>from>from>from>from>from>from>from]
  >[-<from<from<from<from<from<from<from<from>to>to>to>to>to>to>to>to+<to<to<to<to<to<to<to<to>from>from>from>from>from>from>from>from]
  >[-<from<from<from<from<from<from<from<from>to>to>to>to>to>to>to>to+<to<to<to<to<to<to<to<to>from>from>from>from>from>from>from>from]
  >[-<from<from<from<from<from<from<from<from>to>to>to>to>to>to>to>to+<to<to<to<to<to<to<to<to>from>from>from>from>from>from>from>from]
  <<<<<<<<from<from<from<from<from<from<from<from
}

; i just assume that if the high byte of the return is non zero, then it is negative
; TODO: actual check
mac checkerror(num){
  !move(63)
  [
    !set(0 69)
    !set(1 82)
    !set(2 82)
    !set(3 48)>>>+num<<<
    !set(4 10)
	.>.>.>.>.<<<
	!clear(8)
	+num
	!move(-8)
	!syscall(60 -1 0 0 0 0 0)
  ]
  !move(-63)
}

; create a socket
!syscall(41 2 1 0 -1 -1 -1)
!checkerror(0)
    ;!set(0 70)
    ;!set(1 82)
    ;!set(2 82)
    ;!set(3 10)
	;.>.>.>.
	;[]

; move socket_fd from output to input of next
!transfer8(7 1)

!move(104)

; set the addr to 127.0.0.1:8080
!set(0 2)
!set(2 31)
!set(3 144)
!set(4 127)
!set(7 1)
!move(-88)
!setptr(88)
!move(-16)

; bind to said socket
!syscall(49 -1 -1 16 -1 -1 -1)
!checkerror(1)

; listen for connection
!syscall(50 -1 5 -1 -1 -1 -1)
!checkerror(2)

!move(16)
!setptr(104)
!move(8)
!setptr(112)
!move(-24)

; accept the connection
!syscall(43 -1 -1 -1 -1 -1 -1)
!checkerror(3)

!transfer8(1 50)
!transfer8(7 1)

; read from the connection to a free region of memory
!move(16)
; 10000
!setptr2(39 16)
!move(-16)
!syscall(0 -1 -1 1000 -1 -1 -1)
!checkerror(4)

; write back what was read
!transfer8(7 3)
!syscall(1 -1 -1 -1 -1 -1 -1)
!checkerror(5)

!syscall(3 -1 0 0 0 0 0)
!transfer8(50 1)
!syscall(3 -1 0 0 0 0 0)
