rcode SEGMENT stack
assume CS:rcode, DS:rcode 


seg_desc STRUC                                   
    limit_l dw 0FFFFh ; low 16 of limit
    base_l dw 0000h ; low 16 of base
    base_m db 00h ; mid 8 of base
    access db -1 ; |  is present (1), privelege level (2), 1
                 ; |  type flags: is code (1), allow lower priv. access / is stack (1), 
                 ; |_ readable / writeable (1), 0
    attrs_limit_h db -1 ; |  attrs: limit *= 0x1000 (1), 32 bits memory (1), 0, 0
                        ; |_ hight 4 of limit
    base_h db 00h ; high 8 of base
seg_desc ENDS        


intr_desc STRUC                                   
    off_l dw 0 ; low 16 of offset
    seg_sel dw 0 ; segment selector inside the gdt
    db 0 ; reserved 8
    params db -1 ; |  is present (1), privelege level (2), 0
                 ; |_ gate type: 0b1110/0b1111 for 32-bit interrupt/trap
    off_h dw 0 ; high 16 of offset
intr_desc ENDS        


gdtr_idtr STRUC        
    limit dw 0                            
    addr dd 0 
gdtr_idtr ENDS


gdt LABEL qword
    seg_desc<0, 0, 0, 0, 0, 0>                              
    gdt_rcode seg_desc<,      ,    , 10011010b, 10001111b, >             
    gdt_rdata seg_desc<,      ,    , 10010010b, 10001111b, >       
    gdt_pcode seg_desc<,      ,    , 10011110b, 11001111b, >
    gdt_pdata seg_desc<,      ,    , 10010010b, 11001111b, >       
    gdt_text  seg_desc<, 8000h, 0Bh, 10010010b, 11001111b, > 
gdtr gdtr_idtr<(offset gdtr) - (offset gdt) - 1, (offset gdt)>

RCODE_SEG = (offset gdt_rcode) - (offset gdt)
RDATA_SEG = (offset gdt_rdata) - (offset gdt)
PCODE_SEG = (offset gdt_pcode) - (offset gdt)
PDATA_SEG = (offset gdt_pdata) - (offset gdt)
TEXT_SEG = (offset gdt_text) - (offset gdt)


EXCEPTION_COUNT = 32
IRQ_COUNT = 16

idt LABEL qword
    idt_exceptions intr_desc EXCEPTION_COUNT dup (<0, PCODE_SEG, , 10001111b, 0>)
    idt_irqs intr_desc IRQ_COUNT dup (<0, PCODE_SEG, , 10001110b, 0>)
idt_end LABEL 
idtr gdtr_idtr<(offset idtr) - (offset idt) - 1, (offset idt)>
null_idtr gdtr_idtr<0, 0>


START:
    .386p ; enable 32-bit extensions

    waitabit MACRO
        jmp $+2
        jmp $+2
    ENDM

    hang MACRO
        jmp $
    ENDM

    fj32 MACRO seg, lbl
        db 0EAh         ; |
        dd (offset lbl) ; |
        dw seg          ; |_ manually encoded jmp seg:lbl
    ENDM
    fj16 MACRO seg, lbl
        db 66h ; (additional to 16-bit mode) specify 32-bit operand
        fj32 seg, lbl
    ENDM

    disable_interrupts MACRO ; ->  AL - garbage
        push AX

        cli
        in AL, 70h       ; | 
        or AL, 10000000b ; |
        out 70h, AL      ; |_ set bit 7 in CMOS register to disable NMI
        nop

        pop AX
    ENDM
    enable_interrupts MACRO ; ->  AL - garbage
        push AX

        in AL, 70h              ; |
        and AL, (not 10000000b) ; |
        out 70h, AL             ; |_ clear bit 7 in CMOS register to enable NMI
        nop
        sti               

        pop AX
    ENDM

    write MACRO msg
        push AX
        push DX

        mov AH, 09h
        mov DX, (offset msg)
        int 21h

        pop DX
        pop AX
    ENDM
    newline MACRO
        push AX
        push DX

        mov AH, 02h
        mov DL, 0Ah
        int 21h
        mov AH, 02h
        mov DL, 0Dh
        int 21h

        pop DX
        pop AX
    ENDM
    read MACRO buf_suff
        push AX
        push BX
        push DX

        mov DX, (offset buf_suff)
        mov AH, 0Ah
        int 21h

        xor AH, AH
        mov AL, buf_suff[1]
        mov BX, (offset buf_suff) + 2
        add BX, AX
        mov byte ptr [BX], EOL

        pop DX
        pop BX
        pop AX
    ENDM


    mov AX, rcode               ; | 
    mov DS, AX                  ; |
    mov SS, AX                  ; |_ DS = SS = RCODE (single segment)
    mov SP, (offset rstack_end) ; |
    mov BP, SP                  ; |_ SP = BP = stack bottom, as stack grows up

    ; read timeout

    write msg_input_timeout 
    read timeout_buf_suff
    newline 

    mov SI, (offset timeout_buf)
    mov CX, 10
    call str2num
    mov CX, AX ; save result, as AL is used later

    disable_interrupts

    ; start rtc

    mov AL, 8Ah         ; |
    out 70h, AL         ; |
    in AL, 71h          ; |
    and AL, (not 1111b) ; |
    or AL, CL           ; |
    out 71h, AL         ; |_ set frequency

    mov AL, 8Bh         ; |
    out 70h, AL         ; |
    in AL, 71h          ; |
    or AL, (1 shl 6)    ; |
    out 71h, AL         ; |_ set periodic

    mov AL, 0Dh         ; |
    out 70h, AL         ; |
    in AL, 71h          ; |_ end command

    ; setup gdt

    mov EAX, rcode ; |         
    shl EAX, 4     ; |_ physical address of this segment

    add gdtr.addr, EAX ; |
    add idtr.addr, EAX ; |_ override GDTR and IDTR addrs to physical

    mov gdt_rcode.base_l, AX ; |
    mov gdt_rdata.base_l, AX ; |
    shr EAX, 16              ; |
    mov gdt_rcode.base_m, AL ; |
    mov gdt_rcode.base_h, AH ; |
    mov gdt_rdata.base_m, AL ; |
    mov gdt_rdata.base_h, AH ; |_ write physical base addr for RCODE and RDATA

    mov EAX, pcode ; |
    shl EAX, 4     ; |_ physical address of PCODE

    mov gdt_pcode.base_l, AX ; |
    mov gdt_pdata.base_l, AX ; |
    shr EAX, 16              ; |
    mov gdt_pcode.base_m, AL ; |
    mov gdt_pcode.base_h, AH ; |
    mov gdt_pdata.base_m, AL ; |
    mov gdt_pdata.base_h, AH ; |_ write physical base addr for PCODE and PDATA

    ; setup idtr

    ; exceptions
    xor BX, BX
    IRP I,<0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31>
        mov EAX, (offset exception_&I)
        mov idt_exceptions[BX].off_l, AX
        shr EAX, 16
        mov idt_exceptions[BX].off_h, AX

        add BX, 1*8 ; account for descriptor size
    ENDM

    ; default interrupts
    xor BX, BX
    setup_irq:
        mov EAX, (offset nop_intr_master)
        mov idt_irqs[BX].off_l, AX
        shr EAX, 16
        mov idt_irqs[BX].off_h, AX

        add BX, 1*8 ; account for descriptor size
        cmp BX, IRQ_COUNT*8 
        jl setup_irq        

    ; rtc interrupt
    mov EAX, (offset rtc_intr)
    mov idt_irqs[8*8].off_l, AX
    shr EAX, 16
    mov idt_irqs[8*8].off_h, AX

    ; keyboard interrupt
    mov EAX, (offset kb_intr)
    mov idt_irqs[1*8].off_l, AX
    shr EAX, 16
    mov idt_irqs[1*8].off_h, AX

    ; start entering pmode

    in AL, 92h  ; |
    or AL, 10b  ; |
    out 92h, AL ; |_ enable A20 line

    lidt idtr
    lgdt gdtr

    mov EAX, CR0 ; |
    or EAX, 1b   ; |
    mov CR0, EAX ; |_ set PMODE bit to enter pmode
    fj16 RCODE_SEG, next_after_pmode_set
    next_after_pmode_set:

    ; reprogram interrupt controller

    mov AL, 11h  ; |  init sequence for...
    out 20h, AL  ; |  
    waitabit     ; |_ ...master
    out 0A0h, AL ; |  
    waitabit     ; |_ ...slave

    mov AL, 20h  ; |
    out 21h, AL  ; |
    waitabit     ; |_ new hardware intr address for master
    add AL, 8    ; |
    out 0A1h, AL ; |
    waitabit     ; |_ new hardware intr address for slave

    mov AL, 04h  ; |
    out 21h, AL  ; |
    waitabit     ; |_ line 3?
    mov AL, 02h  ; |
    out 0A1h, AL ; |
    waitabit     ; |_ line 1?

    mov AL, 11h  ; |  
    out 21h, AL  ; |
    waitabit     ; |_ fully nested mode for master
    mov AL, 01h  ; |
    out 0A1h, AL ; |
    waitabit     ; |_ default mode for slave

    ; final steps

    in AL, 21h   ; | 
    shl AX, 8    ; |
    in AL, 0A1h  ; |
    push AX      ; |_ save interrupt masks

    mov AL, 0    ; |
    out 21h, AL  ; |
    waitabit     ; |
    out 0A1h, AL ; |
    waitabit     ; |_ unmask all interrupts

    enable_interrupts

    ; we are in pmode now!

    fj16 PCODE_SEG, pstart

continue:

    ; start exiting pmode (basically the opposite action)

    disable_interrupts

    ; reprogram interrupt controller back

    mov AL, 11h  ; |  init sequence for...
    out 20h, AL  ; |  
    waitabit     ; |_ ...master
    out 0A0h, AL ; |  
    waitabit     ; |_ ...slave

    mov AL, 8h   ; |
    out 21h, AL  ; |
    waitabit     ; |_ original hardware intr address for master
    mov AL, 70h  ; |
    out 0A1h, AL ; |
    waitabit     ; |_ original hardware intr address for slave

    mov AL, 04h  ; |
    out 21h, AL  ; |
    waitabit     ; |_ line 3?
    mov AL, 02h  ; |
    out 0A1h, AL ; |
    waitabit     ; |_ line 1?

    mov AL, 11h  ; |  
    out 21h, AL  ; |
    waitabit     ; |_ fully nested mode for master
    mov AL, 01h  ; |
    out 0A1h, AL ; |
    waitabit     ; |_ default mode for slave

    ; 

    mov EAX, CR0     ; |
    and AL, (not 1b) ; |
    mov CR0, EAX     ; |_ clear PMODE bit to exit pmode
    fj16 rcode, next_after_pmode_clear
    next_after_pmode_clear:

    mov AX, rcode               ; | 
    mov DS, AX                  ; |
    mov SS, AX                  ; |_ DS = CS = RCODE (single segment)
    mov SP, (offset rstack_end) ; | 
    mov BP, SP                  ; |_ SP = stack bottom, as stack grows up

    lidt null_idtr ; clear IDT

    in  AL, 92h       ; |
    and AL, (not 10b) ; |
    out 92h, AL       ; |_ disable A20 line

    sub SP, 2    ; |_ we have interrupt masks stored on the stack, so reserving a word
    pop AX       ; |
    out 0A1h, AL ; |
    shr AX, 8    ; |
    out 21h, AL  ; |_ restore interrupt masks

    enable_interrupts

    ; we are back in rmode!

    write msg_end

    mov AL, 00h
    exit:
        mov AH, 4Ch               
        int 21h                  

    CR = 0Dh
    LF = 0Ah
    EOL = "$"

    TIMEOUT_BUF_LEN equ (6+1)
    timeout_buf_suff db TIMEOUT_BUF_LEN, ?
    timeout_buf db TIMEOUT_BUF_LEN dup(EOL), EOL

    msg_input_timeout db "input protected mode timeout: ", EOL
    msg_end db "bye!", CR,LF, EOL


    str2num PROC ; DS:SI - string, CX - base (up to 10)  ->  AX - result
        push CX
        push DX 
        push SI

        ; move if the first char is a sign
        cmp byte ptr [SI], "-"
        je str2num_move_sign
        cmp byte ptr [SI], "+"
        jne str2num_skip_move_sign
        str2num_move_sign:
        inc SI
        str2num_skip_move_sign:

        xor AX, AX
        str2num_loop_next_char:
            mul CX

            xor DH, DH
            mov DL, [SI]
            sub DX, "0"
            ; NOTE here base might base overflow (DX > CX)
            add AX, DX
        
            inc SI
            cmp byte ptr [SI], EOL
            jne str2num_loop_next_char
            
        pop SI ; restoring SI to the start of a string

        cmp byte ptr [SI], "-" ; |
        jne str2num_skip_neg   ; |
        neg AX                 ; |
        str2num_skip_neg:      ; |_ first char was a minus, so negate result

        ; SI was already popped
        pop DX
        pop CX
        ret
    str2num ENDP


rstack dw 128 dup (?) 
rstack_end LABEL word


rcode ENDS   




pcode SEGMENT use32
assume CS:pcode, DS:pcode


pstart:

    mov AX, PDATA_SEG            ; |
    mov DS, AX                   ; |
    mov SS, AX                   ; |_ DS = SS = PDATA (virtual segments are different)
    mov ESP, (offset pstack_end) ; |
    mov EBP, ESP                 ; |_ SP = stack bottom, as stack grows up

    mov AX, TEXT_SEG ; |
    mov ES, AX       ; |_ ES = TEXT

    hang

    pexit:
        mov AH, 00000110b
        mov ESI, (offset pexit_msg_end)
        xor EDI, EDI
        call pputs
        call pnewline

        fj32 RCODE_SEG, continue

    pexit_msg_end db "[pmode] bye!", 0


    pnewline PROC ; AH - color, ES:EDI - any position on the cleared line  ->  ES:EDI - next line, [ES:EDI-80 .. ES:EDI] - cleared string
        push AX
        push ECX

        xor ECX, ECX

        pnewline_find_line:
            add ECX, 80*2
            cmp ECX, EDI
            jle pnewline_find_line

        mov AL, 0
        sub ECX, EDI ; | 
        shr ECX, 1   ; |_ char count til line end
        rep stosw ; fill til the end with colored zeroes

        pop ECX
        pop AX
        ret
    pnewline ENDP

    pputs PROC ; AH - color, DS:ESI - string, ES:EDI - start address  ->  DS:ESI - string end, [ES:EDI] - result
        push AX

        pputs_next:
            lodsb ; load char
            test AL, AL      ; |
            jz end_pputs_next ; |_ if zero, end 

            stosw
            jmp pputs_next
        end_pputs_next:

        pop AX
        ret
    pputs ENDP


    b2str PROC ; DH - value, ES:DI - start address  ->  [ES:DI] - result
        push AX

        mov AL, DH       ; |
        shr AL, 4        ; |
        call _b2str_half ; |
        stosw            ; |_ high halfbyte

        mov AL, DH       ; |
        call _b2str_half ; |
        stosw            ; |_ low halfbyte                         

        pop AX
        ret

        _b2str_half PROC ; AL - value to print  ->  AL - char to print
            and AL, 0Fh
            cmp AL, 0Ah
            jl _b2str_half_add_0
            jge _b2str_half_add_a
            _b2str_half_add_0:
            add AL, ("0" - 00h)
            jmp _b2str_half_end_add
            _b2str_half_add_a:
            add AL, ("A" - 0Ah)
            jmp _b2str_half_end_add
            _b2str_half_end_add:

            ret
        _b2str_half ENDP
    b2str ENDP

    w2str PROC ; DX - value, ES:DI - start address  ->  [ES:DI] - result
        push DX

        call b2str ; |_ high byte 
        shl DX, 8  ; |
        call b2str ; |_ low byte

        pop DX
        ret
    w2str ENDP

    dw2str PROC ; EDX - value, ES:DI - start address  ->  [ES:DI] - result
        push DX

        shr EDX, 16 ; |
        call w2str  ; |_ high word
        
        pop DX

        call w2str ; low word

        ret
    dw2str ENDP


    ; handlers

    ;exception_handlers:
    IRP I,<0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31>
    exception_&I:
        cli
        push dword I
        jmp exception
    ENDM

    exception PROC near
        mov AX, TEXT_SEG
        mov ES, AX
        xor EDI, EDI

        mov AH, 01110100b ; setup color

        call pnewline

        mov EBX, (offset exception_msgs)
        next_msg:
            mov ESI, [EBX]
            call pputs
            pop EDX
            call dw2str
            call pnewline

            add EBX, 4 ; next message offset (a double word)
            cmp EBX, (offset exception_msgs_end) ; |
            jl next_msg                          ; |_ loop til end

        call pnewline

        ; no need to sti, as rmode will do its own thing anyway
        fj32 RCODE_SEG, continue ; immediately return to rmode

        exception_msgs LABEL dword
            dd (offset exception_msg_exception)
            dd (offset exception_msg_eip)
            dd (offset exception_msg_cs)
            dd (offset exception_msg_flags)
        exception_msgs_end LABEL

        exception_msg_exception db "[pmode] exception: ", 0
        exception_msg_eip db "[pmode] eip: ", 0
        exception_msg_cs db "[pmode] cs: ", 0
        exception_msg_flags db "[pmode] flags: ", 0
    exception ENDP


    ; nop
    nop_intr_master PROC near
        push AX
        mov  AL, 20h
        out  20h, AL
        pop  AX
        iret
    nop_intr_master ENDP
    nop_intr_slave PROC near
        push AX
        mov  AL, 20h
        out  20h, AL
        out  0A0h, AL
        pop  AX
        iret
    nop_intr_slave ENDP


    ; keyboard
    kb_intr PROC near
        push AX
        push DX
        push ESI
        push EDI

        in AL, 60h ; get scancode

        cmp AL, 81h           ; |
        jne kb_intr_skip_exit ; |        
        mov AL, 20h           ; |
        out 20h, AL           ; |
        fj32 PCODE_SEG, pexit ; |
        kb_intr_skip_exit:    ; |_ if ESC was released, exit

        mov AH, 00000101b ; setup color

        mov EDI, 0*2 ; first line
        mov ESI, (offset kb_intr_msg_scancode)
        call pputs
        
        mov DH, AL ; |
        call b2str ; |_ print scancode

        mov AL, 20h
        out 20h, AL
        pop EDI
        pop ESI
        pop DX
        pop AX
        iret

        kb_intr_msg_scancode db "last scancode: ", 0
    kb_intr ENDP


    ; rtc
    rtc_intr PROC near
        push AX
        push DX
        push ESI
        push EDI

        dec CX
        jnz rtc_intr_skip_exit ; |        
        mov AL, 20h            ; |
        out 20h, AL            ; |
        out 0Ah, AL            ; |
        fj32 PCODE_SEG, pexit  ; |
        rtc_intr_skip_exit:    ; |_ if CX is decremented to zero (timeout passed), exit

        mov AH, 00000010b ; setup color

        mov EDI, 80*2 ; second line
        mov ESI, (offset rtc_msg_time_passed)
        call pputs
        
        mov DH, CL ; |
        call b2str ; |_ print remaining seconds

        mov AL, 20h
        out 20h, AL
        out 0Ah, AL
        pop EDI
        pop ESI
        pop DX
        pop AX
        iret

        rtc_msg_time_passed db "time remaining: ", 0
    rtc_intr ENDP


pstack dw 128 dup (?)            
pstack_end LABEL word


pcode ENDS


END START
