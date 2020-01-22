// FETCH --------------------------------------------
module fetch (input rst, clk, pc_src, jump, flush, input w_stall, input [31:0] add_res, jaddr, output [31:0] d_inst, d_pc, output d_stall);
   
  wire [31:0] pc_4;
  wire [31:0] inst;
  reg [31:0] pc;
  reg stall;

  initial begin
    stall <= 1;
    pc <= 32'd0;
  end
  
  assign pc_4 = 4 + pc;

  always @(posedge clk) begin
    if (stall)
      pc <= pc;
    else if (jump == 1'b1)
      pc <= jaddr;
    else if (pc_src == 1'b1)
      pc <= add_res;
    else
      pc <= pc_4;
    if (w_stall != "x")
      stall <= w_stall;
  end

  reg [31:0] inst_mem [0:31];

  assign inst = inst_mem[pc[31:2]];

  initial begin
    // Exemplos 
    /*
    inst_mem[0] <= 32'h00000000; // nop
    inst_mem[1] <= 32'h8c010000; // lw r1, 0(r0)   =>   r1 = m[r0+0] 
    inst_mem[2] <= 32'h8c020004; // lw r2, 4(r0)   =>   r2 = m[r0+4] 
    inst_mem[3] <= 32'h00220820; // add r1,r1,r2   =>   r1 = r1 + r2 
    inst_mem[4] <= 32'hac010008; // sw r1, 8(r0)   =>   m[r0+8] = r1
    */

    inst_mem[0] <= 32'h00000000; // nop
    inst_mem[1] <= 32'h200a0005; // addi $t2,$zero,5
    inst_mem[2] <= 32'h200b0007; // addi $t3,$zero,7
    inst_mem[3] <= 32'h200c0002; // addi $t4,$zero,2
    inst_mem[4] <= 32'h200d0003; // addi $t5,$zero,3
    inst_mem[5] <= 32'h014b5020; // add $t2,$t2,$t3
    inst_mem[6] <= 32'h016c5820; // add $t3,$t3,$t4
    inst_mem[7] <= 32'h018c6020; // add $t4,$t4,$t4
    inst_mem[8] <= 32'h01aa6820; // add $t5,$t5,$t2 
  end

  // PIPE F -> D
  IFID IFID (clk, flush, stall, pc, inst, d_pc, d_inst, d_stall);
endmodule

// pipe1 F -> D
module IFID (input f_clk, flush, f_stall, input [31:0] f_pc, f_inst, output reg [31:0] d_pc, d_inst, output reg d_stall);
  always @(posedge f_clk) begin
    d_stall <= f_stall;
    if (~flush || f_stall) begin
      d_inst <= f_inst;
      d_pc   <= f_pc;
    end 
    else begin
      d_inst <= 0;
      d_pc   <= 0;
    end
  end
endmodule

//----------------------------------------------------
// DECODE --------------------------------------------
//----------------------------------------------------
module decode (input d_clk, regwrite, e_memread_in, m_jump, pc_src, d_stall, input [31:0] inst, pc, writedata, input [4:0] muxRegDst, output [31:0] e_rd1, e_rd2, e_sigext, e_pc, e_jaddr, output [4:0] e_rs, e_rt, e_rd, output [1:0] e_aluop, output e_alusrc, e_regdst, e_regwrite, e_memread, e_memtoreg, e_memwrite, e_branch, flush, e_jump, e_stall);
  
  wire [31:0] data1, data2, sig_ext, jaddr;
  wire [4:0] rs, rt, rd;
  wire [5:0] opcode;
  wire [1:0] aluop;
  wire branch, memread, memtoreg, MemWrite, regdst, alusrc, regwrite, jump;
  wire hazard_detected;
  reg flush;
  
  assign opcode = inst[31:26];
  assign rs     = inst[25:21];
  assign rt     = inst[20:16];
  assign rd     = inst[15:11];
  assign imm    = inst[15:0];
  assign jaddr  = {pc[31:28], inst[25:0], {2{1'b0}}};

  assign sig_ext = (inst[15]) ? {16'hFFFF,imm} : {16'd0,imm};
  
  // hazard
  assign hazard_detected = (e_memread_in && (e_rt == rs || e_rt == rt)) ? 1 : 0;

  ControlUnit control (opcode, hazard_detected, regdst, alusrc, memtoreg, regwrite_out, memread, memwrite, branch, jump, aluop);

  always @(*) begin
    flush <= 0;
    if (m_jump || pc_src) 
      flush <= 1;
  end

  Register_Bank Registers (d_clk, regwrite, rs, rt, muxRegDst, writedata, data1, data2);

  // PIPE D -> E
  IDEX IDEX (d_clk, regwrite_out, memtoreg, branch, memwrite, memread, regdst, alusrc, jump, flush, d_stall, aluop, pc, data1, data2, sig_ext, jaddr, rs, rt, rd, e_regwrite, e_memtoreg, e_branch, e_memwrite, e_memread, e_regdst, e_alusrc, e_jump, e_stall, e_aluop, e_pc, e_rd1, e_rd2, e_sigext, e_jaddr, e_rs, e_rt, e_rd);

endmodule

// pipe2 D -> E
module IDEX (input d_clk, d_regwrite, d_memtoreg, d_branch, d_memwrite, d_memread, d_regdst, d_alusrc, d_jump, flush, d_stall, input [1:0] d_aluop, input [31:0] d_pc, d_rd1, d_rd2, d_sigext, d_jaddr, input [4:0] d_rs, d_rt, d_rd, output reg e_regwrite, e_memtoreg, e_branch, e_memwrite, e_memread, e_regdst, e_alusrc, e_jump, e_stall, output reg [1:0] e_aluop, output reg [31:0] e_pc, e_rd1, e_rd2, e_sigext, e_jaddr, output reg [4:0] e_rs, e_rt, e_rd);
  always @(posedge d_clk) begin
    e_stall <= d_stall;
    if (~flush || d_stall) begin
      e_regwrite <= d_regwrite;
      e_memtoreg <= d_memtoreg;
      e_branch   <= d_branch;
      e_memwrite <= d_memwrite;
      e_memread  <= d_memread;
      e_regdst   <= d_regdst;
      e_aluop    <= d_aluop;
      e_alusrc   <= d_alusrc;
      e_pc       <= d_pc;
      e_jaddr    <= d_jaddr;
      e_rd1      <= d_rd1;
      e_rd2      <= d_rd2;
      e_sigext   <= d_sigext;
      e_rs       <= d_rs;
      e_rt       <= d_rt;
      e_rd       <= d_rd;
      e_jump     <= d_jump;
    end
    else begin
      e_regwrite <= 0;
      e_memtoreg <= 0;
      e_branch   <= 0;
      e_memwrite <= 0;
      e_memread  <= 0;
      e_regdst   <= 0;
      e_aluop    <= 0;
      e_alusrc   <= 0;
      e_pc       <= 0;
      e_jaddr    <= 0;
      e_rd1      <= 0;
      e_rd2      <= 0;
      e_sigext   <= 0;
      e_rs       <= 0;
      e_rt       <= 0;
      e_rd       <= 0;
      e_jump     <= 0;
    end 
  end
endmodule

module ControlUnit (input [5:0] opcode, input hazard_detected, output reg regdst, alusrc, memtoreg, regwrite, memread, memwrite, branch, jump, output reg [1:0] aluop);
  
  always @(*) begin
    // defaults - NOP
    regdst   <= 0;
    alusrc   <= 0;
    memtoreg <= 0;
    regwrite <= 0;
    memread  <= 0;
    memwrite <= 0;
    branch   <= 0;
    aluop    <= 0;
    jump     <= 0;
    if (!hazard_detected) begin
      case(opcode) 
        6'd0: begin // R type
          regdst <= 1 ;
          regwrite <= 1 ;
          aluop <= 2 ;
        end
        6'd4: begin // beq
          branch <= 1 ;
          aluop <= 1 ;
        end
        6'd8: begin // addi
          alusrc <= 1 ;
          regwrite <= 1 ;
        end
        6'd35: begin // lw
          alusrc <= 1 ;
          memtoreg <= 1 ;
          regwrite <= 1 ;
          memread <= 1 ;
        end
        6'd43: begin // sw
          alusrc <= 1 ;
          memwrite <= 1 ;
        end
        6'd2: begin // jump
          jump <= 1;
        end
      endcase
    end
  end

endmodule 

module Register_Bank (input clk, regwrite, input [4:0] read1, read2, writereg, input [31:0] writedata, output [31:0] data1, data2);

  integer i;
  reg [31:0] memory [0:31]; // 32 registers de 32 bits cada

  // fill the memory
  initial begin
    for (i = 0; i <= 31; i++) 
      memory[i] = i;
  end

  assign data1 = (regwrite && read1==writereg) ? writedata : memory[read1];
  assign data2 = (regwrite && read2==writereg) ? writedata : memory[read2];
	
  always @(posedge clk) begin
    if (regwrite)
      memory[writereg] <= writedata;
  end
  
endmodule

// EXECUTE STAGE -------------------------------------
module execute (
  input e_clk, e_alusrc, e_regdst, e_regwrite, e_memread, e_memtoreg, e_memwrite, e_branch, e_jump, m_regw, w_regw, flush, e_stall, input [31:0] e_in1, e_in2, e_sigext, e_pc, m_data, w_data, e_jaddr, input [4:0] e_rs, e_rt, e_rd, m_rd, w_rd, input [1:0] e_aluop,
  output [31:0] m_alures, m_rd2, m_addres, m_jaddr, output [4:0] m_muxRegDst, output m_branch, m_zero, m_regwrite, m_memtoreg, m_memread, m_memwrite, m_jump, m_stall
);

  wire [31:0] alu_B, e_addres, e_aluout;
  reg  [31:0] A, B;
  wire [3:0] aluctrl;
  wire [4:0] e_muxRegDst;
  wire e_zero;
  wire [1:0] forwardA, forwardB;

  // forward
  forward forward_unit(e_rs, e_rt, e_rd, m_rd, w_rd, m_regw, w_regw, forwardA, forwardB);

  always @(*) begin
    case (forwardA)
      2'b00 : A <= e_in1;
      2'b01 : A <= w_data;
      2'b10 : A <= m_data;
      default : A <= e_in1; 
    endcase
    case (forwardB)
      2'b00 : B <= alu_B;
      2'b01 : B <= w_data;
      2'b10 : B <= m_data;
      default : B <= e_in1; 
    endcase
  end

  assign alu_B = (e_alusrc) ? e_sigext : B;

  Add Add (e_pc, e_sigext, e_addres);

  //Unidade Lógico Aritimética
  ALU alu (aluctrl, A, alu_B, e_aluout, e_zero);

  alucontrol alucontrol (e_aluop, e_sigext[5:0], aluctrl);
  
  assign e_muxRegDst = (e_regdst) ? e_rd : e_rt;

  // PIPE E -> M
  EXMEM EXMEM (
    .e_clk(e_clk),
    .e_regwrite(e_regwrite),
    .e_memtoreg(e_memtoreg),
    .e_addRes(e_addres),
    .e_zero(e_zero),
    .e_branch(e_branch),
    .e_alures(e_aluout),
    .e_rd2(B),
    .e_muxRegDst(e_muxRegDst),
    .e_memread(e_memread),
    .e_memwrite(e_memwrite),
    .e_jump(e_jump),
    .flush(flush),
    .e_stall(e_stall),
    .m_regwrite(m_regwrite),
    .m_memtoreg(m_memtoreg),
    .m_addRes(m_addres),
    .m_zero(m_zero),
    .m_alures(m_alures),
    .m_rd2(m_rd2),
    .m_muxRegDst(m_muxRegDst),
    .m_memread(m_memread),
    .m_memwrite(m_memwrite),
    .m_branch(m_branch),
    .m_jump(m_jump),
    .m_stall(m_stall)
  );
endmodule

module forward (
  input [4:0] e_rs,
  input [4:0] e_rt,
  input [4:0] e_rd,
  input [4:0] m_rd,
  input [4:0] w_rd,
  input m_regwrite, w_regwrite, 
  output reg [1:0] forwardA, forwardB
);

  always @(*) begin
    forwardA <= (m_regwrite && m_rd != 0 && m_rd == e_rs) ? 2'b10 : (w_regwrite && w_rd == e_rs) ? 2'b01 : 2'b00;
    forwardB <= (m_regwrite && m_rd != 0 && m_rd == e_rt) ? 2'b10 : (w_regwrite && w_rd == e_rt) ? 2'b01 : 2'b00;
  end  

endmodule

module Add (input [31:0] pc, shiftleft2, output [31:0] add_result);
  assign add_result = pc + (shiftleft2 << 2);
endmodule

module alucontrol (input [1:0] aluop, input [5:0] funct, output [3:0] alucontrol);

  reg [3:0] alucontrol;
   
  always @(aluop or funct) begin
    case (aluop)
      0: alucontrol <= 4'd2; // ADD para sw e lw
      1: alucontrol <= 4'd6; // SUB para branch
      default: begin
        case (funct)
          32: alucontrol <= 4'd2; // ADD
          34: alucontrol <= 4'd6; // SUB
          36: alucontrol <= 4'd0; // AND
          37: alucontrol <= 4'd1; // OR
          39: alucontrol <= 4'd12; // NOR
          42: alucontrol <= 4'd7; // SLT
          default: alucontrol <= 4'd15; // Nada acontece
        endcase
      end
    endcase
  end
endmodule

module ALU (input [3:0] alucontrol, input [31:0] A, B, output [31:0] aluout, output zero);

  reg [31:0] aluout;
  
  // Zero recebe um valor lógico caso aluout seja igual a zero.
  assign zero = (aluout == 0); 
  
  always @(alucontrol, A, B) begin
    //verifica qual o valor do controle para determinar o que fazer com a saída
    case (alucontrol)
      0: aluout <= A & B; // AND
      1: aluout <= A | B; // OR
      2: aluout <= A + B; // ADD
      6: aluout <= A - B; // SUB
      7: aluout <= A < B ? 32'd1 : 32'd0; //SLT
      12: aluout <= ~(A | B); // NOR
      default: aluout <= 0; //default 0, Nada acontece;
    endcase
  end
endmodule

// pipe2 E -> M
module EXMEM (
  input e_clk,
  input e_regwrite,
  input e_memtoreg,
  input e_branch,
  input [31:0] e_addRes,
  input e_zero,
  input [31:0] e_alures,
  input [31:0] e_rd2,
  input [31:0] e_jaddr,
  input [4:0]  e_muxRegDst,
  input e_memread,
  input e_memwrite,
  input e_jump,
  input flush,
  input e_stall,
  output reg m_regwrite,
  output reg m_memtoreg,
  output reg [31:0] m_addRes,
  output reg m_zero,
  output reg [31:0] m_alures,
  output reg [31:0] m_rd2,
  output reg [31:0] m_jaddr,
  output reg [4:0]  m_muxRegDst,
  output reg m_memread,
  output reg m_memwrite,
  output reg m_branch,
  output reg m_jump,
  output reg m_stall
);
  always @(posedge e_clk) begin
    m_stall <= e_stall;
    if (~flush || e_stall) begin
      m_regwrite  <= e_regwrite;
      m_memtoreg  <= e_memtoreg;
      m_addRes    <= e_addRes;
      m_zero      <= e_zero;
      m_alures    <= e_alures;
      m_rd2       <= e_rd2;
      m_muxRegDst <= e_muxRegDst;
      m_memread   <= e_memread;
      m_memwrite  <= e_memwrite;
      m_branch    <= e_branch;
      m_jump      <= e_jump;
      m_jaddr     <= e_jaddr;
    end
    else begin
      m_regwrite  <= 0;
      m_memtoreg  <= 0;
      m_addRes    <= 0;
      m_zero      <= 0;
      m_alures    <= 0;
      m_rd2       <= 0;
      m_muxRegDst <= 0;
      m_memread   <= 0;
      m_memwrite  <= 0;
      m_branch    <= 0;
      m_jump      <= 0;
      m_jaddr     <= 0;
    end
  end
endmodule

// MEMORY STAGE ----------------------------------------
module memory (input m_clk, m_branch, m_zero, m_regwrite, m_memtoreg, m_memread, m_memwrite, m_stall, input [31:0] m_alures, writedata, e_jaddr, input [4:0] m_muxRegDst, output [31:0] w_readdata, w_alures, output w_memtoreg, w_regwrite, pc_src, output reg w_stall, output [4:0] w_muxRegDst);

  wire [31:0] m_readdata;
  reg [31:0] memory [0:127]; 
  integer i;

  // fill the memory
  initial begin
    for (i = 0; i <= 127; i++) 
      memory[i] = i;
  end

  always @(*) begin
    if (m_memread && !m_stall) 
      w_stall <= m_stall;
    else
      w_stall <= 0;
  end

  assign pc_src = (m_zero & m_branch) ? 1 : 0;

  assign m_readdata = (m_memread) ? memory[m_alures[31:2]] : 0;

  always @(posedge m_clk) begin
    if (m_memwrite)
      memory[m_alures[31:2]] = writedata;
  end

  // pip4 M -> W
  MEMWB MEMWB (m_clk, m_regwrite, m_memtoreg, m_readdata, m_alures, m_muxRegDst, w_readdata, w_alures, w_muxRegDst, w_regwrite, w_memtoreg); 

endmodule

// pip3 M -> W
module MEMWB (input m_clk, m_regwrite, m_memtoreg, input [31:0] m_readData, m_alures, input [4:0] m_muxRegDst, output reg [31:0] w_readData, w_alures, output reg [4:0] w_muxRegDst, output reg w_regwrite, w_memtoreg);
  always @(posedge m_clk) begin
    w_readData <= m_readData;
    w_alures <= m_alures;
    w_regwrite <= m_regwrite;
    w_memtoreg <= m_memtoreg;
    w_muxRegDst <= m_muxRegDst;
  end
endmodule

// WRITE-BACK -----------------------------------
module writeback (input [31:0] readdata, aluout, input memtoreg, output [31:0] write_data);
  assign write_data = (memtoreg) ? readdata : aluout;
endmodule

// TOP -------------------------------------------
module pipemips (input clk, rst, output [31:0] reg_writedata);

  wire [31:0] d_inst, e_jaddr, m_jaddr, d_pc, e_pc, e_rd1, e_rd2, sig_ext, write_data, m_addRes, add_res, m_alures, m_readdata, w_readData, w_alures, reg_writedata;
  wire d_stall, e_stall, m_stall, w_stall, flush, e_jump, e_regwrite, e_memtoreg, e_branch, e_memwrite, e_memread, e_regdst, e_alusrc, m_regWrite, m_memtoreg, m_zero, m_memread, m_memwrite, w_regwrite, w_memtoreg, m_branch;
  wire [1:0] e_aluop;
  wire [4:0] e_rs, e_rt, e_rd, e_muxRegDst, m_muxRegDst, w_muxRegDst;

  // FETCH STAGE
  fetch fetch (rst, clk, pc_src, m_jump, flush, w_stall, m_addRes, m_jaddr, d_inst, d_pc, d_stall);
  
  // DECODE STAGE
  decode decode (clk, w_regwrite, e_memread, m_jump, d_stall, pc_src, d_inst, d_pc, reg_writedata, w_muxRegDst, e_rd1, e_rd2, sig_ext, e_pc, e_jaddr, e_rs, e_rt, e_rd, e_aluop, e_alusrc, e_regdst, e_regwrite, e_memread, e_memtoreg, e_memwrite, e_branch, flush, e_jump, e_stall);
  
  // EXECUTE STAGE
  execute execute (clk, e_alusrc, e_regdst, e_regwrite, e_memread, e_memtoreg, e_memwrite, e_branch, e_jump, e_stall, m_regwrite, m_regwrite, flush, e_rd1, e_rd2, sig_ext, e_pc, m_alures, reg_writedata, e_jaddr, e_rs, e_rt, e_rd, m_muxRegDst, w_muxRegDst, e_aluop, m_alures, write_data, m_jaddr, m_addRes, m_muxRegDst, m_branch, m_zero, m_regwrite, m_memtoreg, m_memread, m_memwrite, m_jump, m_stall);

  // MEMORY STAGE
  memory memory (clk, m_branch, m_zero, m_regwrite, m_memtoreg, m_memread, m_memwrite, m_stall, m_alures, write_data, e_jaddr, m_muxRegDst, w_readData, w_alures, w_memtoreg, w_regwrite, pc_src, w_stall, w_muxRegDst);
  
  // WRITEBACK STAGE
  writeback writeback (w_readData, w_alures, w_memtoreg, reg_writedata);

endmodule
