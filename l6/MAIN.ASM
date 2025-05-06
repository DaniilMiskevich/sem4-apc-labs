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
    gdt_null seg_desc<0, 0, 0, 0, 0, 0>                              
    gdt_rcode seg_desc<,      ,    , 10011010b, 10001111b, >             
    gdt_rdata seg_desc<,      ,    , 10010010b, 10001111b, >       
    gdt_pcode seg_desc<,      ,    , 10011110b, 11001111b, >
    gdt_pdata seg_desc<,      ,    , 10010010b, 11001111b, >       
    gdt_text  seg_desc<, 8000h, 0Bh, 10010010b, 11001111b, > 
    ;gdt_idt seg_desc<,      ,    ,          ,          , >                  
gdtr gdtr_idtr<(offset gdtr) - (offset gdt) - 1, (offset gdt)>

PCODE_SEG = (offset gdt_pcode) - (offset gdt)
PDATA_SEG = (offset gdt_pdata) - (offset gdt)
RCODE_SEG = (offset gdt_rcode) - (offset gdt)
RDATA_SEG = (offset gdt_rdata) - (offset gdt)
TEXT_SEG = (offset gdt_text) - (offset gdt)


idt LABEL qword
    IRPC N, 0123456789ABCDEF
        idt_0&N intr_desc<0, PCODE_SEG, , 10001111b, 0>
    ENDM
    IRPC N, 0123456789ABCDEF
        idt_1&N intr_desc<0, PCODE_SEG, , 10001111b, 0> 
    ENDM
    idt_rtc intr_desc<0, PCODE_SEG, , 10001110b, 0>
    idt_kb  intr_desc<0, PCODE_SEG, , 10001110b, 0>
    IRPC N, 23456789ABCDEF
        idt_2&N intr_desc<0, PCODE_SEG, , 10001110b, 0>
    ENDM
idtr gdtr_idtr<(offset idtr) - (offset idt) - 1, (offset idt)>
null_idtr gdtr_idtr<0, 0>


START:
    .386p ; enable 32-bit extensions

    fj16 MACRO seg, lbl
        db 0EAh         ; |
        dd (offset lbl) ; |
        dw seg          ; |_ manually encoded jmp seg:lbl
    ENDM
    fj32 MACRO seg, lbl
        db 66h ; specify 32-bit operand
        fj16 seg, lbl
    ENDM

    disable_interrupts MACRO 
        cli
        in AL, 70h       ; | 
        or AL, 10000000b ; |
        out 70h, AL      ; |_ set bit 7 in CMOS register to disable nmi 
    ENDM
    enable_interrupts MACRO
        in AL, 70h        ; |
        and AL, 01111111b ; |
        out 70h, AL       ; |_ clear bit 7 in CMOS register to enable nmi 
        sti               
    ENDM


    mov AX, CS ; | 
    mov DS, AX ; |_ DS = CS, single segment

    ; setup gdt

    ; calculate physical addr for this segment
    mov EAX, CS          
    shl EAX, 4          

    add gdtr.addr, EAX 
    add idtr.addr, EAX 

    ; write physical addresses for rmode into gdt
    mov gdt_rcode.base_l, AX
    mov gdt_rdata.base_l, AX 
    shr EAX, 16
    mov gdt_rcode.base_m, AL
    mov gdt_rcode.base_h, AH
    mov gdt_rdata.base_m, AL
    mov gdt_rdata.base_h, AH

    ; calculate physical addr of protected segment
    mov EAX, pcode                
    shl EAX, 4                  

    ; write physical addresses for pmode into gdt
    mov gdt_pcode.base_l, AX   
    mov gdt_pdata.base_l, AX
    shr EAX, 16
    mov gdt_pcode.base_m, AL
    mov gdt_pcode.base_h, AH
    mov gdt_pdata.base_m, AL
    mov gdt_pdata.base_h, AH

    ; setup idtr

    IRPC N, 0123456789ABCDEF                 ;Заполнить векторы 00-0F исключениями
        mov EAX, offset exception_0&N
        mov idt_0&N.off_l, AX
        shr EAX, 16
        mov idt_0&N.off_h, AX
    ENDM
    IRPC N, 0123456789ABCDEF                 ;Заполнить векторы 10-1F исключениями
        mov EAX, offset exception_1&N
        mov idt_1&N.off_l, AX
        shr EAX, 16
        mov idt_1&N.off_h, AX
    ENDM

    mov EAX, offset nop_irq_master                      ;Поместить обработчик прерывания таймера на 20 шлюз
    mov idt_rtc.off_l, AX
    shr EAX, 16
    mov idt_rtc.off_h, AX

    mov EAX, offset kb_handler                   ;Поместить обработчик прерывания клавиатуры на 21 шлюз
    mov idt_kb.off_l, AX
    shr EAX, 16
    mov idt_kb.off_h, AX

    ; other master interrupts
    IRPC N, 234567
        mov EAX, offset nop_irq_master
        mov idt_2&N.off_l, AX
        shr EAX, 16
        mov idt_2&N.off_h, AX
    ENDM
    
    ; slave interrupts
    IRPC N, 89ABCDEF
        mov EAX, offset nop_irq_slave
        mov idt_2&N.off_l, AX
        shr EAX, 16
        mov idt_2&N.off_h, AX
    ENDM

    in AL, 92h  ; |
    or AL, 10b  ; |
    out 92h, AL ; |_ set bit 1 in PS/2 to enable A20 line

    ; save interrupt masks
    ;in AL, 21h
    ;shl AX, 8
    ;in AL, 0A1h
    ;push AX
    disable_interrupts

    ; enter pmode
    lidt idtr
    lgdt gdtr
    mov EAX, CR0 
    or EAX, 1b  
    mov CR0, EAX 

    ; STOLEN PART
    mov al,00010001b                            ;ICW1 - переинициализация контроллера прерываний
    out 20h,al                                  ;Переинициализируем ведущий контроллер
    out 0A0h,al                                 ;Переинициализируем ведомый контроллер
    mov al,20h                                  ;ICW2 - номер базового вектора прерываний
    out 21h,al                                  ;ведущего контроллера
    mov al,28h                                  ;ICW2 - номер базового вектора прерываний
    out 0A1h,al                                 ;ведомого контроллера
    mov al,04h                                  ;ICW3 - ведущий контроллер подключен к 3 линии
    out 21h,al       
    mov al,02h                                  ;ICW3 - ведомый контроллер подключен к 3 линии
    out 0A1h,al      
    mov al,11h                                  ;ICW4 - режим специальной полной вложенности для ведущего контроллера
    out 21h,al        
    mov al,01h                                  ;ICW4 - режим обычной полной вложенности для ведомого контроллера
    out 0A1h,al       
    mov al, 0                                   ;Размаскировать прерывания
    out 21h,al                                  ;Ведущего контроллера
    out 0A1h,al                                 ;Ведомого контроллера
    ; END STOLEN PART

    enable_interrupts

    fj32 PCODE_SEG, pstart

continue:
    disable_interrupts
    ; STOLEN PART
    mov al,00010001b                            ;ICW1 - переинициализация контроллера прерываний
    out 20h,al                                  ;Переинициализируем ведущий контроллер
    out 0A0h,al                                 ;Переинициализируем ведомый контроллер
    mov al,8h                                   ;ICW2 - номер базового вектора прерываний
    out 21h,al                                  ;ведущего контроллера
    mov al,70h                                  ;ICW2 - номер базового вектора прерываний
    out 0A1h,al                                 ;ведомого контроллера
    mov al,04h                                  ;ICW3 - ведущий контроллер подключен к 3 линии
    out 21h,al       
    mov al,02h                                  ;ICW3 - ведомый контроллер подключен к 3 линии
    out 0A1h,al      
    mov al,11h                                  ;ICW4 - режим специальной полной вложенности для ведущего контроллера
    out 21h,al        
    mov al,01h                                  ;ICW4 - режим обычной полной вложенности для ведомого контроллера
    out 0A1h,al
    ; END STOLEN PART
    enable_interrupts

    ; setup segments
    mov AX, CS ; | 
    mov DS, AX ; |_ DS = CS, single segment
    mov SS, AX  
    mov SP, (offset rstack_end) ; setup stack 

    mov AL, 00h
    rexit:
        mov AH, 4Ch               
        int 21h                  


return_to_rmode PROC
    lidt null_idtr

    ; back to rmode
    mov EAX, CR0
    and AL, (not 1b)
    mov CR0, EAX 

    fj32 rcode, continue
return_to_rmode ENDP


rstack db 256 dup (?) 
rstack_end:


rcode ENDS   


pcode SEGMENT use32
assume CS:pcode, DS:pcode


pstart:

    ; setup segments
    mov AX, PDATA_SEG ; |
    mov DS, AX        ; |
    mov SS, AX        ; |_ DS = SS = pdata
    mov ESP, (offset pstack_end) ; setup stack
    mov AX, TEXT_SEG ; |
    mov ES, AX       ; |_ ES = TEXT

    mov DX, 0141h
    lp:
        push AX
        mov AX, DX
        xor EDI, EDI
        mov ECX, 80*3
        rep stosw
        pop AX
        ;inc DX
        jmp lp

    pexit:
        fj16 RCODE_SEG, return_to_rmode


    phexb PROC ; DH - value, ES:DI - start address  ->  [ES:DI] - result
        push AX

        mov AL, DH
        shr AL, 4
        call phexhalf
        stosw
        mov AL, DH
        call phexhalf
        stosw

        pop AX
        ret

        phexhalf PROC ; AL - value to print  ->  AL - char to print
            and AL, 0Fh
            cmp AL, 09h
            jle phexhalf_add_0
            jg phexhalf_add_a

            phexhalf_add_0:
            add AL, ("0" - 00h)
            jmp phexhalf_end_add

            phexhalf_add_a:
            add AL, ("A" - 0Ah)
            jmp phexhalf_end_add

            phexhalf_end_add:
            ret
        phexhalf ENDP
    phexb ENDP

    phexw PROC ; DX - value, ES:DI - start address  ->  [ES:DI] - result
        push DX
        call phexb
        shl DX, 8
        call phexb
        pop DX
        ret
    phexw ENDP

    phexdw PROC ; EDX - value, ES:DI - start address  ->  [ES:DI] - result
        push DX
        shr EDX, 16
        call phexw
        pop DX
        call phexw
        ret
    phexdw ENDP


    ; interrupt handlers

    M = 0                           
    IRPC N, 0123456789ABCDEF
    exception_0&N LABEL word                              
        cli
        push dword 0&N&h
        jmp exception_handler
    ENDM
    M = 010H
    IRPC N, 0123456789ABCDEF                        
    exception_1&N LABEL word
        cli
        push dword 1&N&h
        jmp exception_handler
    ENDM

    exception_handler PROC near
        mov AX, TEXT_SEG
        mov ES, AX
        xor EDI, EDI

        printc MACRO c
            mov AL, c
            stosw
        ENDM

        ; output color
        mov AH, 01110100b

        printc " "

        ; print just pushed exception index

        printc "E"
        printc "x"
        printc "c"
        printc ":"
        printc " "

        pop EDX
        call phexdw

        printc ";"
        printc " "

        ; print eip

        printc "E"
        printc "I"
        printc "P"
        printc ":"
        printc " "

        pop EDX
        call phexdw

        printc ";"
        printc " "

        ; print cs

        printc "C"
        printc "S"
        printc ":"
        printc " "

        pop EDX
        call phexdw

        printc ";"
        printc " "

        ; print flags

        printc "F"
        printc "l"
        printc "a"
        printc "g"
        printc "s"
        printc ":"
        printc " "

        pop EDX
        call phexdw

        printc "."

        printc " "

        ; back to rmode
        sti
        fj16 PCODE_SEG, pexit
    exception_handler ENDP

    kb_handler PROC near
        push EAX

        in AL, 60h ; get scancode
        shl AX, 8
        mov AL, 20h
        out 20h, AL
        shr AX, 8

        cmp AL, 01h
        jne skip_exit
        fj16 PCODE_SEG, pexit
        skip_exit:

        inc DX

        pop EAX
        iretd
    kb_handler ENDP

    nop_irq_master PROC near                      ;Заглушка для аппаратных прерываний ведущего контроллера
        push EAX

        mov  AL, 20h
        out  20h, AL

        pop  EAX
        iretd
    nop_irq_master ENDP

    nop_irq_slave PROC near                      ;Заглушка для аппаратных прерываний ведомого контроллера
        push EAX
        mov  AL, 20h
        out  20h, AL
        out  0A0h, AL
        pop  EAX
        iretd
    nop_irq_slave ENDP


pstack db 256 dup (?)            
pstack_end:


pcode ENDS


END START
