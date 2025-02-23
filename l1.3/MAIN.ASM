; https://courses.cs.umbc.edu/undergraduate/211/Spring00/Burt/lectures/CntlHardware/serialPorts.html
; https://www.plantation-productions.com/Webster/www.artofasm.com/DOS/pdf/ch22.pdf

.model small

.stack 100h

.data 
    port_addr dw 03F8h
    port_lcr_addr dw 03FBh
    port_lsr_addr dw 03FDh

    msg db "Hello world!", 0Ah, 0Dh, 00h

.code

_start:
    mov AX, @data
    mov DS, AX

    ; init 
    mov AL, 10000011b
    mov DX, port_lcr_addr
    out DX, AL

    mov AX, 000Ch
    mov DX, port_addr
    out DX, AX

    mov AL, 00000011b
    mov DX, port_lcr_addr
    out DX, AL

    ; send bytes
    mov BX, offset msg
    write_loop:
        mov AL, [BX]
        call com_write

        inc BX

        cmp byte ptr [BX], 00h
        jne write_loop

    ; receive bytes
    read_loop:
        call com_read

        ; break if received EOT
        cmp AL, 04h
        je end_read_loop

        ; print read byte
        mov AH, 02h
        mov DL, AL 
        int 21h

        jmp read_loop
    end_read_loop:

    ; exit with code 0
    exit:
        mov AH, 4Ch
        mov AL, 00h
        int 21h


com_read:; () -> (AH: garbage, AL: read byte)
    push DX

    mov DX, port_lsr_addr
    wait_for_data:
        ; read line status
        in AL, DX
        
        ; check if data is available
        test AL, 00000001b
        jz wait_for_data

    ; receive byte
    mov AL, 04h ; if not read, will be EOT
    mov DX, port_addr
    in AL, DX

    pop DX
    ret 


com_write:; (AL: char to send) -> ()
    push DX

    push AX
    mov DX, port_lsr_addr
    wait_for_no_data:
        ; read line status
        in AL, DX
        
        ; check if transmission is available
        test AL, 00100000b
        jz wait_for_no_data
    pop AX

    ; send byte
    mov DX, port_addr
    out DX, AL

    pop DX
    ret

end
