.model small

.stack 100h

.data 
    msg db "Hello world!", 0Ah, 0Dh, 00h
    port dw 0000h

.code

_start:
    mov AX, @data
    mov DS, AX
    xor AX, AX

    ; init COM
    mov AH, 00h
    mov AL, 11100011b
    mov DX, port
    int 14h

    ; send bytes
    mov BX, offset msg
    send_loop:
        mov AL, [BX]
        call com_write

        inc BX

        cmp byte ptr [BX], 00h
        jne send_loop



    ; exit with code 0
    mov AH, 4Ch
    mov AL, 00h
    int 21h

com_write:; (AL: char to send)
    push AX

    ; send byte
    mov AH, 01h
    mov DX, port
    int 14h

    ; debug write to screen
    mov AH, 02h
    mov DL, AL
    int 21h

    pop AX
    ret

end
