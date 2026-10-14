import machine68k as m, sys
N=int(sys.argv[1])
mc=m.Machine(m.CPUType.M68030,4096)
mem=mc.mem; cpu=mc.cpu
img=open('ie.bin','rb').read(); mem.w_block(0,img)
W=open('mu_ie.txt','w'); PC=open('mu_iepc.txt','w')
def tr(mode,width,addr,val):
    if mode=='W' or mode==1: W.write('%08X %d %08X\n'%(addr,width,val))
    return 0
mem.set_trace_func(tr); mem.set_trace_mode(True)
cnt=[0]
def ih(pc):
    PC.write('%08X\n'%pc); cnt[0]+=1
cpu.set_instr_hook_callback(ih)
cpu.pulse_reset()
cpu.execute(N)
print('pc',hex(cpu.r_pc()),'instrs',cnt[0],'d0',hex(cpu.r_reg(m.Register.D0)))
