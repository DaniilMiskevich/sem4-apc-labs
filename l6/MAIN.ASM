.386p
.model large


farjmp macro cs, lbl
    db  0EAh
    dd  offset lbl 
    dw  cs
endm


write MACRO msg
    push AX
    push DX

    mov AH, 09h
    mov DX, offset msg
    int 21h

    pop DX
    pop AX
ENDM


rcode segment para use16
RCODE_START equ $

assume CS:rcode, DS:data, ES:data
rstart:
    mov AX, data                                 
    mov DS, AX                                   
    mov ES, AX                          

    write msg_greet

    lgdt fword ptr gdtr
    ; lidt fword ptr idtr

    ; enable p-mode
    mov EAX, CR0
    or  AL, 1b 
    mov CR0, EAX

    farjmp CODE_DESC pstart

rcode ends


pcode segment para use32

assume CS:pcode, DS:data
pstart:
    mov AX, DATA_DESC                                 
    mov DS, AX                                   
    mov AX, VMEM_DESC                                 
    mov ES, AX                          

    xor  EDI, EDI
    mov  ECX, 80 * 25
    mov  AX, 700h
    rep  stosw

    mov AX, 0FEh 
    out 64h, AX

pcode ends


data segment para use16

    seg_desc struc                                   
        limit_l dw 0FFFFh ; low 16 of limit
        base_l dw 0000h ; |  
        base_m db 00h   ; |_ low 24 of base
        access db 0 ; |  is present (1), privelege level (2), 1
                    ; |  type flags: is code (1), allow lower priv. access / is stack (1), 
                    ; |_ readable / writeable (1), 0
        attrs_limit_h db 00001111b ; |  attrs: limit *= 0x1000 (1), 32 bits memory (1), 0, 0
                                   ; |_ hight 4 of limit
        base_h db 00h ; high 8 of base
    seg_desc ends        


    intr_desc struc                                   
        off_l dw 0 ; Адрес обработчика (0:15)
        selector dw 0 ; Селектор кода, содержащего код обработчика
        param_count db 0 ; Параметры
        access db 0 ; Уровень доступа
        off_h dw 0 ; Адрес обработчика (31:16)
    intr_desc ends        
    idtr struc        
        limit dw 0                            
        idt_l dw 0 ; Смещение биты (0-15)
        idt_h dw 0 ; Смещение биты (31-16)
    idtr ends


    gdt label
        gdt_null_desc seg_desc <0,0,0,0,0,0>                              
        gdt_code_desc seg_desc <,,,10011010b,,>             
        CODE_DESC equ gdt_code_desc - gdt
        gdt_data_desc seg_desc <,,,10010010b,,>      
        DATA_DESC equ gdt_data_desc - gdt
        gdt_vmem_desc seg_desc <4000h,8000h,0Bh,11110010b,0,0> 
        VMEM_DESC equ gdt_vmem_desc - gdt
    GDT_END equ $

    gdtr label
        gdt_size dw GDT_END - gdt - 1
        gdt_addr dd gdt

    CR equ 0Dh
    LF equ 0Ah
    CRLF equ CR, LF

    msg db "Hello world!", CR, LF
    msg_greet db "Hello world!", CRLF

data ends




end
