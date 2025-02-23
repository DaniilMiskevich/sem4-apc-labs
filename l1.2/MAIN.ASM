.model small

.stack 100h

.data 
    port dw 0000h
    read_indicator_period dw 0FFFFh
    max_read_bytes dw 12

    msg db "Hello world!", 0Ah, 0Dh, 00h

.code

_start:
    mov AX, @data
    mov DS, AX

    ; init 
    mov AH, 00h
    mov AL, 11100011b
    mov DX, port
    int 14h

    ; send bytes
    mov BX, offset msg
    write_loop:
        mov AL, [BX]
        mov DX, port
        call com_write

        inc BX

        cmp byte ptr [BX], 00h
        jne write_loop

    ; receive bytes
    mov CX, max_read_bytes
    read_loop:
        mov DX, port
        call com_read

        ; break if received EOT
        cmp AL, 04h
        je end_read_loop

        ; print read byte
        mov AH, 02h
        mov DL, AL 
        int 21h

        loop read_loop
    end_read_loop:

    mov AL, 04h
    mov DX, port
    call com_write

    ; exit with code 0
    exit:
        mov AH, 4Ch
        mov AL, 00h
        int 21h


com_read:; (DX: port) -> (AH: garbage, AL: read byte)
    mov CX, read_indicator_period
    wait_for_data:
        dec CX
        test CX, CX
        jnz skip_print_dot

        push DX
        mov CX, read_indicator_period
        mov AH, 02h
        mov DL, "." 
        int 21h
        pop DX
        skip_print_dot:

        mov AH, 03h
        int 14h
        
        test AH, 00000001b
        jz wait_for_data

    ; read byte
    mov AH, 02h
    mov AL, 04h ; if not read, will be EOT
    int 14h

    ret 


com_write:; (AL: char to send, DX: port) -> ()
    push AX

    ; send byte
    mov AH, 01h
    int 14h

    pop AX
    ret


end
