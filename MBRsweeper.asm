[org 0x7c00]
VIDEO_MEM equ 0xb800

UNCOVERED equ 0x61
COVERED equ 0x77
SELECTOR_UNCOVERED equ 0x2f
SELECTOR_COVERED equ 0x44

[bits 16]
main:
    mov ax, VIDEO_MEM
    mov es, ax      ;extra segment used for video memory access
    xor ax, ax      ;clear ax
    mov ds, ax      ;set Data Segment to 0
    mov ss, ax      ;set Stack Segment to 0
    mov bp, 0xb000  ;setup stack well above us
    mov sp, bp
    mov al, 0x03    ;set display mode(ah=00) to 3(al) to 80x25 color
    int 0x10

    mov si, title
    call print



    mov ah, 0x02    ;read realtime clock
    int 0x1a        ;read, ch=hrs, cl=min, dh=sec
    mov ch, dh
    mov [seed], cx

    mov bx, [cursor_offset] ;bx is the cursor register, it must always be maintained
    call generate
    
    call draw_cursor
loop:
    call get_input          ;sets key to ax
    call key_to_direction   ;converts key to direction in al
    cmp al, 4
    je handle_click         ;==4
    jl handle_direction     ;<4
    jmp loop                ;else
    handle_direction:
        call move_selector
        jmp loop
    handle_click:
        call click
        jmp loop

print:
    mov ah, 0x0e    ;BIOS tele-type output
print_loop:
    lodsb       ;move the byte at si, based on the data segment, into al
    cmp al, 0       ;compare al to 0
    je print_end    ;if equal to 0, string is done
    int 0x10        ;print character in al
    jmp print_loop

print_end:
    ret

generate:
    mov ah, COVERED
    generate_col_loop:
        generate_row_loop:
            call random ;get random num in (e)dx
            cmp edx, 0x2fff ;difficulty set here, increase for more difficulty
            mov al, '@'
            jg not_mine
            mov al, 'M'
            not_mine:
            mov [es:bx], ax
            add bx, 2
            call divmod
            cmp dx, 154
            jle generate_row_loop

        add bx, 8
        cmp cx, 23
        jl generate_col_loop

    sub bx, 0x692       
    ret

get_input:      ;waits for keyboard input and leaves it in ax
    mov ah, 0
    int 0x16    ;wait for keyboard input
    ret

key_to_direction: ;compares ah to arrow key scan codes
    ;sets al to correspoding direction, 4(enter), 5(bad key)
    mov al, 0
    cmp ah, 0x48
    je key_up
    cmp ah, 0x50
    je key_down
    cmp ah, 0x4b
    je key_left
    cmp ah, 0x4d
    je key_right
    cmp ah, 0x1c
    je key_ent

        inc al
    key_ent:
        inc al
    key_up:
        inc al
    key_down:
        inc al
    key_left:
        inc al
    key_right:
        ret

move_selector: ;moves selector based on direction al
    call undraw_cursor
    call divmod ;sets row(bx/160) in cx, col(bx%160) in dx
    cmp al, 2
    jl ltrt ;<2, left/right
    updn:
        je move_down
        move_up:
            cmp cx, 3
            jle move_selector_end
            sub bx, 160
            jmp move_selector_end
        move_down:
            cmp cx, 23
            jge move_selector_end
            add bx, 160
            jmp move_selector_end
    ltrt:
        cmp al, 0
        je move_right
        move_left:
            cmp dx, 4
            jle move_selector_end
            sub bx, 2
            jmp move_selector_end
        move_right:
            cmp dx, 154
            jge move_selector_end
            add bx, 2

move_selector_end:
    call draw_cursor
    ret


click:
    cmp byte [es:bx], '@'
    jg mine_hit
    je check_num
    jmp click_return
    
click_return:
    call draw_cursor
    ret

check_num:                  ;looks byte at bx, uncovers and calcs the
    sub byte [es:bx], 0x20
    push bx
    sub bx, 162     ;move bx to first position
    xor ax, ax
    mov cx, '0'
    mov si, places
    check_num_loop:
        cmp byte [es:bx], 'M'
        jl check_num_cont
        inc cx
        check_num_cont:
        lodsb       ;move the byte at si, based on the data segment, into al
        cmp al, 0
        je check_num_end
        add bx, ax
        jmp check_num_loop

    check_num_end:
    pop bx
    cmp cl, '0'
    je click_return
    mov [es:bx], cl
    jmp click_return


draw_cursor:    ;postion in bx
    mov ch, SELECTOR_COVERED
    mov cl, SELECTOR_UNCOVERED

    jmp draw

undraw_cursor:  ;position in bx
    mov ch, COVERED
    mov cl, UNCOVERED

draw:   ;position in bx, uncovered in cl and covered in ch
    pusha
    mov al,[es:bx]
    add bx, 1
    cmp al, 0x3a
    jg covered
    uncovered:
        mov [es:bx], cl
        jmp return
    covered:
        mov [es:bx], ch

return:
    popa
    ret

random: ;linear congruential generator(LCG)
    push ax
    xor edx, edx
    mov eax, [seed]
    mul dword [a]       ;a
    add eax, [c]        ;c
    div dword [m]       ;m
    mov [seed], edx
    jmp math_ret

divmod:     ;does bx/160, leaves qoutient(/) in cx and remainder(%) in dx
    push ax
    xor dx,dx
    mov ax, bx
    div word [MAX_COL]
    mov cx, ax

math_ret:
    pop ax
    ret

mine_hit:
    hlt ;reset

;number math numbers
places:
    db 2,2,156,4,156,2,2,0

;PRNG constants
a:
    dd 0x41c64e6d
c:
    dd 0x3039
m:
    dd 0x10000
MAX_COL:
    dw 160
cursor_offset:
    dw 0x01e4
seed:
    dd 0x09
title:
    db 0x0a,'                                     MBRsweeper',0


; Fill with 510 zeros minus the size of the previous code
times 510-($-$$) db 0
; Magic number
dw 0xAA55