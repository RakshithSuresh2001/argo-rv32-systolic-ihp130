`default_nettype none

module sg13cmos5l_IOPadIn (pad, p2c, iovdd, iovss, vdd, vss);
    inout  pad;
    output p2c;
    inout  iovdd;
    inout  iovss;
    inout  vdd;
    inout  vss;
endmodule

module sg13cmos5l_IOPadOut16mA (pad, c2p, iovdd, iovss, vdd, vss);
    inout  pad;
    input  c2p;
    inout  iovdd;
    inout  iovss;
    inout  vdd;
    inout  vss;
endmodule

module sg13cmos5l_IOPadVdd (iovdd, iovss, vdd, vss);
    inout iovdd;
    inout iovss;
    inout vdd;
    inout vss;
endmodule

module sg13cmos5l_IOPadVss (iovdd, iovss, vdd, vss);
    inout iovdd;
    inout iovss;
    inout vdd;
    inout vss;
endmodule

module sg13cmos5l_IOPadIOVdd (iovdd, iovss, vdd, vss);
    inout iovdd;
    inout iovss;
    inout vdd;
    inout vss;
endmodule

module sg13cmos5l_IOPadIOVss (iovdd, iovss, vdd, vss);
    inout iovdd;
    inout iovss;
    inout vdd;
    inout vss;
endmodule

`default_nettype wire
