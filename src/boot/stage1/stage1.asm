;=======================================
; stage 1 bootloader
;
; This stage have 2 blocks: One 16 bits and other 32.
; This stage will switch to protected mode.
;=======================================

; This is required since the GDT will map ALL memory from
; physical address 0 to 4 GiB - 1.
S1_OFFSET equ 0x600
%define S1_ADDR(x) ((x)+S1_OFFSET)

bits 16

org 0

_start:
  push  cs
  pop   ds

  ; OBS: At this point SS still points to 0x9000!

  ; TODO...

  cli

  ; Try to enable Gate A20.
  call  enable_gate_a20_int15h
  jnc   .gate_a20_enabled
  call  enable_gate_a20_kbdc
  jnc   .gate_a20_enabled
  call  enable_gate_a20_fast
.gate_a20_enabled:
  call  check_enabled_a20
  jc    error_enabling_gate_a20

  lgdt  [global_descriptors_table_struct]
  mov   eax,cr0
  or    ax,1                  ; Set PE bit.
  mov   cr0,eax
  jmp   8:S1_ADDR(go32)       ; Is this correct?!

error_enabling_gate_a20:
  mov   si,error_enabling_gate_a20_msg
  call  puts

sys_halt:
  hlt
  jmp   sys_halt

error_enabling_gate_a20_msg:
  db    "error enable Gate A20.",13,10,0

;------------------
; puts(char *s)
; Entry: SI=s
;------------------
puts:
  lodsb
  test  al,al
  jz    .puts_exit
  mov   ah,0x0e
  int   0x10
  jmp   puts
.puts_exit:
  ret

;===============================================
; Gate A20 routines
;===============================================
;-------------------
; Enable Gate A20 (Fast Gate A20 method)
;-------------------
enable_gate_a20_fast:
  in    al,0x92
  bts   ax,1
  jc    .enable_gate_a20_fast_exit
  and   al,0xfe
  out   0x92,al
.enable_gate_a20_fast_exit:
  ret

;--------------------
; Enable GateA20 (KBDC method)
;--------------------
enable_gate_a20_kbdc:
  call  .kbdc_wait1
  mov   al,0xad       ; Disable Keyboard.
  out   0x64,al
  call  .kbdc_wait1
  mov   al,0xd0       ; Read output port
  out   0x64,al
  call  .kbdc_wait2
  in    al,0x60
  mov   dl,al
  call  .kbdc_wait1
  mov   al,0xd1       ; Write output port
  out   0x64,al
  call  .kbdc_wait1
  mov   al,dl
  or    al,2          ; Set Gate A20 bit
  out   0x60,al
  call  .kbdc_wait1
  mov   al,0xae       ; Re-enable keyboard.
  out   0x64,al
  call  .kbdc_wait1
  ret

.kbdc_wait1:
  in    al,0x64
  test  al,2
  jnz   .kbdc_wait1
  ret
.kbdc_wait2:
  in    al,0x64
  test  al,1
  jz    .kbdc_wait2
  ret

;-------------------
; Enable Gate A20 (INT 0x15 method)
; Returns CF=0 if successful.
;-------------------
enable_gate_a20_int15h:
  mov   ax,0x2403     ; Query Gate A20 Support.
  int   0x15
  jc    .enabled_gate_a20_int15h_exit
  or    ah,ah
  jnz   .enabled_gate_a20_int15h_not_supported

  mov   ax,0x2402     ; Get GateA20 Status
  int   0x15
  jc    .enabled_gate_a20_int15h_exit
  or    ah,ah
  jnz   .enabled_gate_a20_int15h_not_supported

  mov   ax,0x2401     ; Enable Gate A20.
  int   0x15

.enabled_gate_a20_int15h_exit:
  ret

.enabled_gate_a20_int15h_not_supported:
  stc
  ret

;-------------------
; Checks if Gate A20 is enabled by writing the inverse of
; data located at 0xffff:0x510 on itself and comparing with
; data located at 0x0000:0x500.
;
; Returns CF=1 if A20 isn't enabled or CF=0 if it is!
;-------------------
check_enabled_a20:
  push  ds
  mov   si,0x500
  mov   di,0x510
  xor   ax,ax
  mov   ds,ax
  not   ax
  mov   es,ax

  lodsb
  mov   ah,[es:di]
  not   ah
  mov   [es:di],ah
  not   ah
  cmp   [si],al
  mov   [es:di],ah
  jne   .a20_enabled

  stc  
  pop   ds
  ret

.a20_enabled:
  clc
  pop   ds
  ret

;-------
; Global Descriptors Table
;
;     3                   2                   1  
;   1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
;  +---------------+-+-+-+-+-------+-+---+-+-------+---------------+
;  |               | |D| |A|  Seg  | | D | |       |               |
;  |  Base 31:24   |G|\|L|V| Limit |P| P |S|  Type |   Base 23:16  | +4
;  |               | |B| |L| 19:16 | | L | |       |               |
;  +---------------+-+-+-+-+-------+-+---+-+-------+---------------+
;  +-------------------------------+-------------------------------+
;  |                               |                               |
;  |         Base 15:0             |    Segment Limit 15:0         | +0
;  |                               |                               |
;  +-------------------------------+-------------------------------+
;-------
global_descriptors_table_struct:
  dw  global_descritors_table_end - global_descriptors_table - 1  ; Limit
  dd  S1_ADDR(global_descriptors_table)                           ; Address.

  align 8
global_descriptors_table:
  ; NULL descriptor
  dd  0,0

  ; Selector 0x08: CS DPL=0,32b,4 GiB Limit,Base=0
  dw  0xffff, 0
  db  0
  db  0x9a        ; Codeseg, execute/read, DPL=0
  db  0xcf        ; 4 GiB, 32 bits
  db  0

  ; Selector 0x10: DS DPL=0,32b,4 GiB limit,Base=0
  dw  0xffff, 0
  db  0
  db  0x92        ; Dataseg, read/write, DPL=0
  db  0xcf        ; 4 GiB, 32 bits
  db  0
global_descritors_table_end:

;===============================================
; All 32 bits protected mode routines goes below!
;===============================================

bits 32

; FIXME: Maybe is sufficient that the Stack is at the end
;        of usable lower RAM at this point...
STKTOP equ  0x9fffc

;===============================================
; Protected mode starts here.
;===============================================
  align 4
go32:
  ; We must jump here with IF disabled!!!
  ; Probably with NMI and all IRQ masked as well...
  mov   ax,0x10   ; Data selector
  mov   ds,ax
  mov   es,ax
  ;mov   fs,ax
  ;mov   gs,ax

  ; FIXME: Must choose an appropriate stack region!
  mov   ss,ax
  mov   esp,STKTOP

  ;TODO...
  ;...

  ; if everything is ok until now...
  jmp   8:0x100000    ; ...Jumps to kernel!

;===============================================
; Screen routines.
;===============================================

;-------
; Screen vars
;-------
current_x:  db  0
current_y:  db  0

;------
; Get current page address
; Returns EDI with base address.
; Destroys EAX and EDX.
;------
get_screen_page_base_addr:
  movzx edi,byte [0x462]    ; Current Video Page.
  mov   eax,4096
  inc   edi
  mul   edi
  add   eax,0xb8000
  mov   edi,eax
  ret

;-------
; Get current cursor position address.
; Destroys EAX, EDX, ESI, EDI and EBX.
;-------
get_current_cursor_position_addr:
  call  S1_ADDR(get_screen_page_base_addr)
  mov   esi,edi
  movzx ebx,byte [S1_ADDR(current_x)]
  movzx ecx,byte [S1_ADDR(current_y)]
  mov   eax,160
  mul   ecx
  mov   edi,eax
  shl   ebx,1
  add   edi,esi
  add   edi,ebx
  ret
  
;-------
; Advance cursor 1 char
;-------
advance_cursor:
  mov   ah,[S1_ADDR(current_x)]
  inc   ah
  cmp   ah,80
  jae   .next_line
.advance_cursor_exit:
  mov   [S1_ADDR(current_x)],ah
  ret
.next_line:
  xor   ah,ah
  mov   al,[S1_ADDR(current_y)]
  cmp   al,25
  jae   .scroll_up
  inc   al
  mov   [S1_ADDR(current_y)],al
  jmp   .advance_cursor_exit
.scroll_up:
  mov   [S1_ADDR(current_x)],ah
  call S1_ADDR(scroll_up)
  ret

;-------
; Scrolls page 1 line up:
;-------
scroll_up:
  call  S1_ADDR(get_screen_page_base_addr)
  mov   esi,edi
  add   esi,160
  mov   ecx,160*24
  rep   movsb
  mov   ax,0x0720
  mov   edi,esi
  mov   ecx,160
  rep   stosw
  ret

;-------
; Simple clear_screen
; Destroys: EDI, EDX, ECX and EAX.
;-------
clear_screen:
  ; DF is always zero?!
  call  S1_ADDR(get_screen_page_base_addr)
  mov   ecx,4000
  mov   ax,0x0720
  rep   stosw
  ret

;-------
; setup_current_pos (Gets the cursor current position from BIOS).
; Destroys EAX and EBX.
; Called only once!
;-------
_setup_current_pos:
  movzx ebx,byte [0x462]  ; Current Video Page.
  mov   ax,[0x450+ebx]    ; Current Page cursor position.
  mov   [S1_ADDR(current_x)],ah
  mov   [S1_ADDR(current_y)],al
  ret

;-------
; putchar
; Entry: AL = char.
;-------
putchar:
  mov   ecx,eax
  call  S1_ADDR(get_current_cursor_position_addr)
  mov   eax,ecx
  mov   ah,0x07
  stosw
  call  S1_ADDR(advance_cursor)
  ret

;===============================================
; Disk I/O routines.
;===============================================
hdd_io_ports:
  dw  0x1f0, 0x1f0, 0x170, 0x170

; Gets controller info.
;   Entry:
;           AL = drive
;   Exit:
;           EDX:EAX = sectors count.
;           CF=0, ok; CF=1, error
;           ZF=0, support LBA48; ZF=1, only LBA28
;
;   Destroys: EAX, EBX, ECX, EDX, ESI
;
get_hdd_info:
  sub     esp,8         ; Local var (sectors_count).

  movzx   ebx,al
  mov     bx,[S1_ADDR(hdd_io_ports)+ebx*2]
  and     al,1
  shl     al,4
  or      al,0x40       ; LBA bit set.
  lea     edx,[ebx+6]
  out     dx,al
  inc     edx
  mov     al,0xec       ; IDENTIFY_DEVICE command.
  out     dx,al

  ; Waits 400ns and waits for (!BSY | RDY)
  times 4 in al,dx
.wait_until_notbusy:
  in    al,dx
  mov   ch,al
  and   al,0xc0
  cmp   al,0x40
  jne   .wait_until_notbusy
  test  ch,1
  jnz   .error
  
  ; Is ATA device?
  lea   edx,[ebx]
  in    ax,dx
  test  ax,0x8000
  jnz   .error

  ; Gets maximum LBA28 sectors count.
  xor   esi,esi
  mov   cl,59          ; Discards the next 59 registers.
.loop1:
  in    ax,dx
  dec   cl
  jnz   .loop1
  in    eax,dx
  mov   [esp],eax       ; Save LBA28 sectors count on local var.
  mov   dword [esp+4],0
  
  ; Supports LBA48?
  mov   cl,21          ; Discards the next 21 registers.
.loop2:
  in    ax,dx
  dec   cl
  jnz   .loop2
  in    ax,dx           ; Gets register 83.
  test  ax,1
  jz    .only_lba28
  inc   esi             ; ESI=0 (lba28), ESI != 0 (lba48). 
.only_lba28:  

  ; if LBA48 is supported, read
  or    esi,esi
  jz    .exit
  mov   cl,16          ; Discards the next 16 registers.
.loop3:
  in    ax,dx
  dec   cl
  jnz   .loop3
  in    eax,dx           ; Gets register 100.
  mov   [esp],eax        ; Saves LBA48 sectors count on local var.
  in    eax,dx
  mov   [esp+4],eax

.exit:
  mov   eax,[esp]
  mov   edx,[esp+4]
  add   esp,8
  or    esi,esi
  clc
  ret

.error:
  add   esp,8
  stc
  ret

; Entry (C calling convention):
;   int read_sectors(uint8_t drive,
;                    uint64_t lba,
;                    uint16_t sectors,
;                    void *bufferptr);
;
struc read_sectors_stk
.oldbp:     resd  1
.drive:     resd  1
.lba:       resq  1
.sectors:   resd  1
.bufferptr: resd  1
endstruc
;
; Exit: CF=1 (error), CF=0 (ok)
;
; Destroys ALL GPRs
;
; Note: Don't deal with specific errors here.
;
read_sectors:
  push  ebp

  mov   ebp,[esp+read_sectors_stk.drive]  
  mov   eax,[esp+read_sectors_stk.lba+4]  
  mov   esi,[esp+read_sectors_stk.lba]
  mov   ecx,[esp+read_sectors_stk.sectors]
  mov   edi,[esp+read_sectors_stk.bufferptr]  

  ; TODO: To check the maximum sectors transfer count!

  ; Check LBA
  test  eax,eax           ; TODO: LBA48 not yet implemented
  jnz   .error

  cmp   esi,0x0fffffff    ; Checks if can use LBA28...
  jbe   .read_lba28

.error:
  pop   ebp
  stc
  ret
  
.read_lba28:
  ; Get I/O port based on drive.
  mov   eax,ebp
  and   eax,3
  movzx ebx,word [S1_ADDR(hdd_io_ports)+eax*2]
  lea   edx,[ebx+2]

  ; Write Sectors Reg.
  mov   eax,ecx
  out   dx,al

  ; Write LBA Lo, Med & Hi Regs.
  inc   edx
  mov   eax,esi
  out   dx,al
  mov   eax,esi
  inc   edx
  shr   eax,8
  out   dx,al
  mov   eax,esi
  inc   edx
  shr   eax,16
  out   dx,al

  inc   edx
  shr   esi,24      ; Separate LBA[27:24]
  and   esi,0x0f
  mov   eax,ebp     ; Separate device bit.
  and   eax,1
  sal   eax,4       
  or    eax,esi     ; Write them.
  out   dx,al

  ; Write Command READ_MULTIPLE.
  inc   edx
  mov   al,0xc4
  out   dx,al
  
  ; Waits 400ns and waits for (!BSY | RDY)
  times 4 in al,dx
.wait_until_notbusy:
  in    al,dx
  mov   ch,al
  and   al,0xc0
  cmp   al,0x40
  jne   .wait_until_notbusy

  ; Checks for errors.
  test  ch,1
  jnz   .error

  ; Read the sectors.
  movzx ecx,cl
  shl   ecx,8             ; Each sector has 256 words.
  lea   edx,[ebx]         ; Points to data port.
  cld                     ; Make sure transfers are forward.
  rep   insw

.read_lba_exit:
  pop   ebp
  clc
  ret

;===============================================
; FileSystem Routines.
;===============================================
; TODO: ...