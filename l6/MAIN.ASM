single segment stack                                                      
assume CS:single, DS:single 

seg_desc struc                                   
    limit_l dw 0FFFFh ; low 16 of limit
    base_l dw 0000h ; low 16 of base
    base_m db 00h ; mid 8 of base
    access db -1 ; |  is present (1), privelege level (2), 1
                ; |  type flags: is code (1), allow lower priv. access / is stack (1), 
                ; |_ readable / writeable (1), 0
    attrs_limit_h db -1 ; |  attrs: limit *= 0x1000 (1), 32 bits memory (1), 0, 0
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

gdt seg_desc <0,0,0,0,0,0>                              
gdt_pcode seg_desc <,      ,    , 10011110b, 11001111b, >
gdt_pdata seg_desc <,      ,    , 10010010b, 11001111b, >       
gdt_rcode seg_desc <,      ,    , 10011010b, 10001111b, >             
gdt_rdata seg_desc <,      ,    , 10010010b, 10001111b, >       
gdt_text seg_desc  <, 8000h, 0Bh, 10010010b, 11001111b, > 
; gdt_idt seg_desc <,      ,    ,          ,          , >                  
gdt_size  dw offset gdt_size - offset gdt - 1
gdt_addr dd offset gdt

RCODE_SEG equ offset gdt_rcode - offset gdt
RDATA_SEG equ offset gdt_rdata - offset gdt 
PCODE_SEG equ offset gdt_pcode - offset gdt
PDATA_SEG equ offset gdt_pdata - offset gdt 
TEXT_DESC equ offset gdt_text - offset gdt  
;IDT_SEG equ offset gdt_idt - offset gdt

start:
    mov AX, CS ; | 
    mov DS, AX ; |_ DS = CS, single segment

    .386p ; enable 32-bit extensions

    ; setup gdt

    ; calculate physical addr for this segment
    xor EAX, EAX 
    mov AX, CS          
    shl EAX, 4          

    add [gdt_addr], EAX 

    ; write physical addresses for rmode into gdt
    mov word ptr [gdt_rcode+2], AX  
    mov word ptr [gdt_rdata+2], AX 
    shr EAX, 16
    mov byte ptr [gdt_rcode+4], AL
    mov byte ptr [gdt_rcode+7], AH
    mov byte ptr [gdt_rdata+4], AL
    mov byte ptr [gdt_rdata+7], AH

    ; calculate physical addr of protected segment
    xor EAX, EAX 
    mov AX, seg32                
    shl EAX, 4                  

    ; write physical addresses for pmode into gdt
    mov word ptr [gdt_pcode+2], AX   
    mov word ptr [gdt_pdata+2], AX
    shr EAX, 16
    mov byte ptr [gdt_pcode+4], AL
    mov byte ptr [gdt_pcode+7], AH
    mov byte ptr [gdt_pdata+4], AL
    mov byte ptr [gdt_pdata+7], AH

    ; prepare interrupts

    cli
    in al, 70h                   ;al <- cmos ram index register port
    or al, 80h                   ;set bit 7 to disable nmi 
    out 70h, al                  ;nmi disabled
    in al, 92h                   ;al <- ps/2 system control port
    or al, 2                     ;set bit 1 to enable a20
    out 92h, al                  ;a20 enabled

    lgdt qword ptr [gdt_size]             ;load gdt 
    mov eax, cr0                  
    or eax, 1b                    ;set pe bit
    mov cr0, eax                 ;enter protected mode
    db 66h                       ;specify 32-bit operand
    db 0eah                      ;manually encoded jmp 8h:0, jump to offset 0 of seg32
    dd offset enter_32                  
    dw 8 

ret_real:
    mov eax, cr0
    and al, 11111110b            ;clear pe bit
    mov cr0, eax                 ;real mode enabled     
    db 0eah                      ;jmp single:real_cs to load cs:ip
    dw offset real_cs
    dw seg single  

real_cs:
    mov ax, cs                      
    mov ds, ax                   ;ds = cs
    mov ss, ax                   ;ss = cs
    mov sp, offset s16_end       ;top of stack is end of stack
    in al, 70h                   ;al <- cmos ram index register port
    and al, 01111111b            ;clear bit 7 to enable nmi 
    out 70h, al                  ;nmi enabled
    sti                          ;enable interrupts

    mov ax, 40h
    mov es, ax                   ;access kbd data area via segment 40h
    mov word ptr es:[1ah], 1eh   ;set the kbd buff head to start of buff
    mov word ptr es:[1ch], 1eh   ;set kbd buff tail to same as buff head
                                 ;now the keyboard buffer is cleared.
    xor ah, ah                   ;select video mode function
    mov al, 3                    ;select 80x25 16 colors
    int 10h                      ;restore vga compatible text mode
    mov ax, 4c00h                ;Terminate process function selected
    int 21h                      ;return to ms-dos

s16 db 256 dup (0ffh)            ;needed 256 bytes to call int 10h on fx5200 vga bios
s16_end: 
single ends   


seg32 segment use32
assume cs:seg32,ds:seg32

enter_32:
    mov ax, 10h                  ;protected mode data segment selector
    mov ds, ax                   ;ds references main data segment
    mov ss, ax                   ;stack is in main data segment 
    mov esp, offset s32_end      ;initial top of stack is end of stack

    mov ax, 28h                  ;vga buffer selector
    mov es, ax                   ;es references vga buffer  

    xor  edi,edi
    mov  ecx, 80*25                              ;Количество символов в окне
    mov  AX, 0F65h
    rep  stosw
    jmp wait_esc

write_scr:
    inc al
    inc ah
    rol eax, 16
    inc al
    inc ah                       ;increment each byte of eax
    xor edi, edi                 ;init index
    mov ecx, 320*200/4           ;vga buffer length in bytes

    push eax
    mov dx, 03DAh                 ;dx <- vga status register
vrb_set:
    in al, dx                    ;al <- status byte
    test al, 8                   ;is bit vertical retrace bit set
    jnz vrb_set                  ;if so, wait for it to clear
vrb_clr:                         ;when clear, wait for it to be set
    in al, dx
    test al, 8
    jz vrb_clr                   ;loop back until vertical retrace bit has been set
    pop eax
    rep stosd                    ;fill vga buffer

wait_esc:
    push eax
    in al, 60h                   ;al <- keyboard data port
    mov ebx, eax                 
    pop eax                     
    cmp bl, 1                    ;escape key scancode? 
    jne wait_esc                ;if not, update screen
    mov ax, 20h                  ;real mode data selector
    mov ds, ax                   
    mov es, ax                   ;setup ds and es for real mode

    exit:
        db 0EAh                      ;jmp 18h:ret_real to load real mode code descriptor 
        dd offset ret_real
        dw 18h

s32 db 128 dup (0ffh)            ;128 byte stack
s32_end:
seg32 ends

end start
