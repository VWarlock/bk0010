`define WITH_DE1_JTAG
`define JTAG_AUTOHOLD


module bk0010(
		clk50,
		clk25,
		reset_in,
		PS2_Clk, PS2_Data,
		button0,
		pdb,
		astb,
		dstb,
		pwr,
		pwait,
		iTCK,
		oTDO,
		iTDI,
		iTCS,
		led,
		switch,
		ram_addr,
		ram_a_data,
		ram_a_ce,
		ram_a_lb,
		ram_a_ub,
		ram_we,
		ram_oe,
		RED,GREEN,BLUE,vs,hs,
		tape_out,
		tape_in,
		clk_cpu_buff,
		cpu_rd,
		cpu_wt,
		cpu_oe,
		_cpu_inst,
		cpu_adr
	);

input 				clk50, clk25;
input 				button0;
input 				PS2_Clk, PS2_Data;

inout	[7:0] 		pdb;
input 				astb;
input 				dstb;
input 				pwr;
output 				pwait;
input 				iTCK, iTDI, iTCS;
output 				oTDO;

output 				clk_cpu_buff,cpu_rd,cpu_wt,cpu_oe;
output	[7:0] 		led;
output 				_cpu_inst;
output 	[15:0]		cpu_adr;
input	[7:0] 		switch;

output 	[17:0] 		ram_addr;
inout 	[15:0] 		ram_a_data;
output 				ram_a_ce;
output 				ram_a_lb;
output 				ram_a_ub;
output 				ram_we;
output 				ram_oe;

output				tape_out;
input				tape_in;

input 				reset_in;

output 				RED,GREEN,BLUE,vs,hs;
reg 				RED,GREEN,BLUE;

wire 			kbd_data_wr;
wire 			video_access;
wire[9:0] 		x;
wire[9:0] 		y;
wire       		hs;
wire       		vs;
wire       		valid;
wire       		R,G,B;
wire        	color;
wire        	load;
wire 			vga_oe;
reg [1:0] 		vga_state;
reg [1:0] 		next_vga_state;

wire[17:0] 		usb_addr;
wire[15:0] 		usb_a_data;
wire 			usb_a_lb;
wire 			usb_a_ub;
wire 			usb_we;
wire 			usb_oe;
reg [1:0] 		usb_clk;

wire[12:0] 		vga_addr;
reg [15:0] 		data_to_interface;

wire 			RST_IN;
wire 			AUD_CLK;

wire 			kbd_available;


reg [23:0] 		cntr; // slow counter for heartbeat LED

wire 			b0_debounced;
wire 			stop_run;

wire [7:0] 		led_from_usb;

wire 			cpu_lb, cpu_ub;


wire [15:0] 	cpu_out;
wire 			cpu_wt;
wire 			cpu_rd;
wire 			cpu_byte;
wire 			single_step;
wire 			cpu_clock_en;
wire 			clk_cpu;
wire 			clk_cpu_buff;
reg [4:0] 		clk_cpu_count;
wire 			cpu_oe;
wire 			cpu_we;
wire 			read_kbd;
wire [7:0] 		roll;

reg [15:0] 		latched_ram_data;
reg [15:0] 		data_from_cpu;

reg [2:0] 		seq;
reg [1:0] 		one_shot;

assign led = {cpu_rdy, b0_debounced, kbd_available, single_step, stop_run, jtag_hold, 1'b0, cntr[23]};

assign cpu_lb = cpu_byte & cpu_adr[0];  // if byte LOW, lb low. If even addr, low too 
assign cpu_ub = cpu_byte & ~cpu_adr[0];


/*
   debounce debounce(.pb_debounced(b0_debounced), .pb(button0), .clock_100Hz(cntr[16]));
  
   run_control run_control (.clk(clk_cpu_count[2]),.reset_in(reset_in), 
   					.start(b0_debounced), .stop(stop_run), .active(cpu_rdy ));
				//	.start(button0), .stop(stop_run));

				//	assign cpu_rdy = 1;

	wire cpu_rdy = 1;
*/
	

reg cpu_rdy;

always @(posedge clk25) begin
	if (reset_in) begin
		cpu_rdy <= 1;
		jtag_hlda <= 0;
	end else begin
		if (jtag_hold | single_step) begin
			//if (_cpu_inst) begin
				cpu_rdy <= 0;
				jtag_hlda <= 1;
			//end
		end
		else begin
			cpu_rdy <= 1;
			jtag_hlda <= 0;
		end
	end
end

 
// vga state machine runs on 50 MHz clock
always @(posedge clk50) begin
	if(reset_in) 
		vga_state <= 0;
	else 
	if(switch[1])
		vga_state <= next_vga_state;
end

assign single_step = switch[6];
assign cpu_clock_en = switch[7];

assign clk_cpu = (switch[5] ? x[3] : x[4]) & cpu_clock_en; 

/*
  BUFG CLKCPU_BUFG_INST(
    .I (clk_cpu),
    .O (clk_cpu_buff));
*/

CLK_LOCK(.inclk(clk_cpu), .outclk(clk_cpu_buff));

// synthesis attribute clock_signal of clk_cpu is yes; 
wire [6:0] ascii;
wire [7:0] kbd_data;
assign kbd_data = {1'b0, ascii};

wire CPU_reset;

wire [15:0] match_val_u;
wire [15:0] match_mask_u;
wire match_hit,cpu_rdy_final;

assign CPU_reset = reset_in | led_from_usb[0]; 
assign stop_run = (cpu_rd & single_step) | (match_hit & led_from_usb[2]) ;
assign cpu_rdy_final = cpu_rdy; /* & ~led_from_usb[1]; */
   
/*
   match bp_match (
    .inp_val(inp_val), 
    .match_val(match_val_u), 
    .mask(match_mask_u), 
    .hit(match_hit)
    );
*/ 

wire kbd_stopkey;
wire kbd_keydown;
wire kbd_ar2;

 bkcore core (
    .p_reset(CPU_reset), 
    .m_clock(clk_cpu_buff), 
    .cpu_rdy(cpu_rdy_final), 
    .wt(cpu_wt), 
    .rd(cpu_rd), 
    .in(latched_ram_data), 
    .out(cpu_out), 
    .adr(cpu_adr), 
    .byte(cpu_byte),
    ._cpu_inst(_cpu_inst),
    .kbd_data(kbd_data), 
    .kbd_available(kbd_available),
    .read_kbd(read_kbd),
    .roll_out(roll),
	.stopkey(kbd_stopkey),
	.keydown(kbd_keydown),
	.kbd_ar2(kbd_ar2),
	.tape_out(tape_out),
	.tape_in(tape_in),
    );

assign cpu_oe = ~(cpu_rd & (seq[2] == 0) & (seq[0] == 1) & cpu_rdy ); 
assign cpu_we = ~(cpu_wt & (seq[1:0]== 2'b01) );


kbd_intf kbd_intf (
    .mclk25(clk25), 
    .reset_in(reset_in), 
    .PS2_Clk(PS2_Clk), 
    .PS2_Data(PS2_Data), 
    .ascii(ascii), 
    .kbd_available(kbd_available), 
    .read_kb(read_kbd),
	.key_stop(kbd_stopkey),
	.key_down(kbd_keydown),
	.ar2(kbd_ar2),
    );


always @(posedge clk25) begin
	if(~cpu_oe & (seq == 3'b001))
		latched_ram_data <= ram_a_data;
end

always @(posedge clk25) begin
	if(~usb_oe)
		data_to_interface = ram_a_data;
end

always @(negedge clk25) begin
	if(cpu_wt)
	   data_from_cpu <= cpu_out;
end

always @(posedge clk25) begin
	if(reset_in) begin
		clk_cpu_count <= 0;
		seq <= 0;
		one_shot <= 0;
	end
	else begin
		clk_cpu_count <= clk_cpu_count + 1;
		seq <= {seq[1:0],( cpu_rd | cpu_wt) & clk_cpu };
		one_shot <= {one_shot[0], ( cpu_rd | cpu_wt)};
	end
end  

    wire [7:0]read_cap;
    wire [2:0]cap_rd_sel;
    wire cap_rd;

    wire [3:0] capt_flags;
    wire cap_wr;
    assign cap_wr = ((cpu_rd | cpu_wt) & (seq[1:0] == 2'b01) & cpu_rdy);

    assign capt_flags = { cpu_byte, _cpu_inst, cpu_rd , cpu_wt};
/*
   capture capture (
    .res(reset_in), 
    .clk25(clk25), 
    .cap_addr(cpu_adr), 
    .cap_dat(ram_a_data),
    .flags(capt_flags), 
    .cap_wr(cap_wr), 
    .read_cap_l(read_cap), 
    .cap_rd(cap_rd), 
    .cap_rd_sel(cap_rd_sel)
    );

*/   
   
`ifdef WITH_USB
usbintf usb_intf (
    .mclk(usb_clk[1]), 
    .reset_in(reset_in), 
    .pdb(pdb), 
    .astb(astb), 
    .dstb(dstb), 
    .pwr(pwr), 
    .pwait(pwait), 
    .led(led_from_usb), 
    .switch(read_cap), 	// use this input for captured data
    .ram_addr(usb_addr), 
    .usb_ouT_data(usb_a_data),
    .in_ramdata(data_to_interface), 
    .ram_a_lb(usb_a_lb), 
    .ram_a_ub(usb_a_ub), 
    .ram_we(usb_we), 
    .ram_oe(usb_oe),
    .cap_rd(cap_rd), 
    .cap_rd_sel(cap_rd_sel),
    .match_val_u(match_val_u),
	.match_mask_u (match_mask_u)
 );
`endif
`ifdef WITH_DE1_JTAG

wire jtag_hold;
reg  jtag_hlda;
wire jtag_oe; // active high
wire jtag_we_n; // active low
assign usb_oe = ~jtag_oe;
assign usb_we = jtag_we_n;

jtag_top jtagger(
	.clk24(clk25),
	.reset_n(~reset_in),
	.oHOLD(jtag_hold),
	.iHLDA(jtag_hlda),
	.iTCK(iTCK),
	.oTDO(oTDO),
	.iTDI(iTDI),
	.iTCS(iTCS),
	.oJTAG_ADDR(usb_addr),
	.iJTAG_DATA_TO_HOST(data_to_interface),
	.oJTAG_DATA_FROM_HOST(usb_a_data),
	.oJTAG_SRAM_WR_N(jtag_we_n),
	.oJTAG_SELECT(jtag_oe)
);
assign usb_a_lb = 0;
assign usb_a_ub = 0;
`else
assign usb_we = 1;
assign usb_oe = 1;
`endif
   
   sync_gen25 syncgen( .clk(clk25), .res(reset_in), .CounterX(x), .CounterY(y), 
		       .Valid(valid), .vga_h_sync(hs), .vga_v_sync(vs));


   shifter shifter(.clk25(clk25),.color(color),.R(R),.G(G),.B(B),
		   .valid(valid),.data(ram_a_data),.x(x),.load(load));


assign RST_IN = 1'b0;
assign vga_addr = { y[8:1] - 'o0330 + roll , x[8:4]};
assign ram_a_ce = 0; // always on

assign ram_addr = ~(cpu_oe & cpu_we) ? {1'b0, cpu_adr[15:1]}: // cpu has top priority
	~(usb_we & usb_oe)? usb_addr:			// usb if needed 
	 {5'b00001, vga_addr};
  				 
assign ram_a_data =  ~cpu_we? data_from_cpu: 
				~usb_we ? usb_a_data : 
				16'b zzzzzzzzzzzzzzzz ;

assign ram_a_lb = ~( cpu_oe & cpu_we )? cpu_lb:
			~( usb_oe & usb_we )? usb_a_lb: 0;
  	  
assign ram_a_ub = ~( cpu_oe & cpu_we )? cpu_ub:
			~( usb_oe & usb_we )? usb_a_ub: 0;
  
  
assign ram_oe = usb_oe & vga_oe & cpu_oe; // either one active low
assign ram_we = usb_we & cpu_we; // video never writes


assign      color = switch[0];

assign      video_access = load & switch[1];  // always read video data at the first half of a cycle 
   
assign vga_oe = ~	video_access;

always @(posedge clk25) begin
	if(reset_in)
		usb_clk <= 0;
	else
		usb_clk <= usb_clk + 1;
end
   


always @(posedge clk25) begin
	if (valid) begin
			RED = R;
			GREEN = G;
			BLUE	=B;
	end  
	else	begin
	  if(show_char_line) begin
			RED = char_bit;
			GREEN = char_bit;
			BLUE	= char_bit;
		end
		else begin
			RED = 0;
			GREEN = 0;
			BLUE	=0;
		end
	end
end

   
always @(posedge clk25) begin
	cntr <= cntr + 1'b 1;
end

`ifdef WITH_CHAR_ROM
wire 		char_rom_cs, char_rom_rw; 
wire [10:0] char_rom_addr; 
wire [7:0] 	char_rom_rdata; 
wire [7:0] 	char_rom_wdata;
wire 		show_char_line;
wire [3:0] 	char_line;
wire 		char_bit;
wire [6:0] 	char_code;

wire [2:0] 	sel_bit;

assign  char_rom_rw = 1;
assign  char_rom_cs = 1;
assign  char_rom_wdata = 0;
assign 	show_char_line = ((y[9:4] == 6'b 100001) & ~x[9]); // line after the valid screen
assign 	char_line = y[3:0];

assign  sel_bit = ~x[2:0];
assign  char_code = x[9:3]+ 'h30;
assign  char_rom_addr = {char_code, char_line};
assign  char_bit = char_rom_rdata[sel_bit];

char_rom char_rom (
	.clk(clk25), 
	.rst(reset_in), 
	.cs(char_rom_cs), 
	.rw(char_rom_rw), 
	.addr(char_rom_addr), 
	.rdata(char_rom_rdata), 
	.wdata(char_rom_wdata)
	);
`else
assign show_char_line = 0;
`endif


endmodule
