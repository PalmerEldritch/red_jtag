//using System;
//using FTD2XX_NET;

//class Program
//{
//    static FTDI ftdi = new FTDI();

//    static void Main()
//    {
//        Console.WriteLine("=== Full I2C/JTAG Engine Test ===\n");

//        ftdi.OpenByIndex(1);
//        Configure();

//        // Ping
//        Console.WriteLine("Ping...");
//        var r = SendCmd(new byte[] { 0xFF }, 1);
//        Console.WriteLine($"  Got: 0x{r[0]:X2}\n");

//        // JTAG Reset
//        Console.WriteLine("JTAG Reset...");
//        r = SendCmd(new byte[] { 0x10 }, 1);
//        Console.WriteLine($"  Got: 0x{r[0]:X2}\n");

//        // Read IDCODE
//        Console.WriteLine("Read IDCODE...");
//        r = SendCmd(new byte[] { 0x11 }, 4);
//        uint id = (uint)(r[0] | (r[1] << 8) | (r[2] << 16) | (r[3] << 24));
//        Console.WriteLine($"  IDCODE: 0x{id:X8}\n");

//        // Load IR (SAMPLE = 0x05)
//        Console.WriteLine("Load IR (SAMPLE=0x05)...");
//        r = SendCmd(new byte[] { 0x12, 0x05 }, 1);
//        Console.WriteLine($"  Got: 0x{r[0]:X2}\n");

//        // Sample BSR (362 bits = 46 bytes)
//        Console.WriteLine("Sample BSR...");
//        r = SendCmd(new byte[] { 0x14 }, 46);
//        Console.Write("  BSR: ");
//        for (int i = 0; i < Math.Min(8, r.Length); i++)
//            Console.Write($"{r[i]:X2} ");
//        Console.WriteLine("...\n");

//        // Read single pin (bit 10)
//        Console.WriteLine("Read pin 10...");
//        r = SendCmd(new byte[] { 0x17, 10, 0 }, 1);
//        Console.WriteLine($"  Pin 10 = {r[0]}\n");

//        // Set pin 100 to 1 (will go through EXTEST)
//        Console.WriteLine("Set pin 100 = 1...");
//        r = SendCmd(new byte[] { 0x16, 100, 0, 1 }, 1);
//        Console.WriteLine($"  Got: 0x{r[0]:X2}\n");

//        ftdi.Close();
//        Console.WriteLine("Done!");
//        Console.ReadKey();
//    }

//    static void Configure()
//    {
//        ftdi.ResetDevice();
//        ftdi.SetLatency(2);
//        ftdi.InTransferSize(65536);
//        ftdi.SetTimeouts(1000, 1000);
//        ftdi.Purge(FTDI.FT_PURGE.FT_PURGE_RX | FTDI.FT_PURGE.FT_PURGE_TX);
//        ftdi.SetBitMode(0x00, FTDI.FT_BIT_MODES.FT_BIT_MODE_RESET);
//    }

//    static byte[] SendCmd(byte[] cmd, int expectLen)
//    {
//        uint written = 0, read = 0, actual = 0;
//        byte[] buf = new byte[expectLen];

//        ftdi.Write(cmd, cmd.Length, ref written);
//        System.Threading.Thread.Sleep(200);

//        ftdi.GetRxBytesAvailable(ref read);
//        if (read > 0)
//            ftdi.Read(buf, (uint)expectLen, ref actual);
//        return buf;
//    }
//}

using System;
using FTD2XX_NET;

class Program
{
    static FTDI ftdi = new FTDI();

    static void Main()
    {
        // Quick IDCODE test
        //Console.WriteLine("=== IDCODE Test ===");

        ftdi.OpenByIndex(1);
        Configure();

        Console.WriteLine("=== I2C Engine Test ===");

        ftdi.Purge(FTDI.FT_PURGE.FT_PURGE_RX | FTDI.FT_PURGE.FT_PURGE_TX);

        // Ping first
        var r = SendCmd(new byte[] { 0xFF }, 1);
        Console.WriteLine("Ping: 0x" + r[0].ToString("X2"));

        // Setup JTAG
        SendCmd(new byte[] { 0x10 }, 1);
        SendCmd(new byte[] { 0x12, 0x0F }, 1);

        Console.WriteLine("Hold RESET, press Enter...");
        Console.ReadLine();

        // I2C probe address 0x3C
        var sw = System.Diagnostics.Stopwatch.StartNew();
        byte[] cmd = new byte[] { 0x20, 0x3C, 0x00 };
        r = SendCmd(cmd, 1);
        sw.Stop();

        Console.WriteLine("I2C Result: 0x" + r[0].ToString("X2"));
        Console.WriteLine("Time: " + sw.ElapsedMilliseconds + " ms");

        if (r[0] == 0x01)
            Console.WriteLine("ACK - SSD1306 found!");
        else
            Console.WriteLine("NACK - not found");





        // If EXTEST loaded correctly, this should be BSR data, not IDCODE

        //Console.WriteLine("=== Simple Pattern Test ===");

        //// Test with patterns that reveal bit position
        //SendCmd(new byte[] { 0x10 }, 1);
        //var r = SendCmd(new byte[] { 0x13, 8, 0, 0x01 }, 1);
        //Console.WriteLine("0x01 -> 0x" + r[0].ToString("X2"));

        //SendCmd(new byte[] { 0x10 }, 1);
        //r = SendCmd(new byte[] { 0x13, 8, 0, 0x80 }, 1);
        //Console.WriteLine("0x80 -> 0x" + r[0].ToString("X2"));

        //SendCmd(new byte[] { 0x10 }, 1);
        //r = SendCmd(new byte[] { 0x13, 8, 0, 0xFF }, 1);
        //Console.WriteLine("0xFF -> 0x" + r[0].ToString("X2"));

        //SendCmd(new byte[] { 0x10 }, 1);
        //r = SendCmd(new byte[] { 0x13, 8, 0, 0x00 }, 1);
        //Console.WriteLine("0x00 -> 0x" + r[0].ToString("X2"));



        //Console.WriteLine("=== IDCODE Consistency Test ===");

        //for (int i = 0; i < 5; i++)
        //{
        //    SendCmd(new byte[] { 0x10 }, 1);  // Reset
        //    var r = SendCmd(new byte[] { 0x11 }, 4);
        //    uint idcode = (uint)(r[0] | (r[1] << 8) | (r[2] << 16) | (r[3] << 24));
        //    Console.WriteLine("Run " + (i + 1) + ": 0x" + idcode.ToString("X8"));
        //}
        // Ping
        //byte[] r = SendCmd(new byte[] { 0xFF }, 1);
        //Console.WriteLine("Ping: 0x" + r[0].ToString("X2"));

        //// JTAG Reset
        //SendCmd(new byte[] { 0x10 }, 1);
        //Console.WriteLine("JTAG Reset done");

        //// Read IDCODE
        //r = SendCmd(new byte[] { 0x11 }, 4);
        //uint idcode = (uint)(r[0] | (r[1] << 8) | (r[2] << 16) | (r[3] << 24));
        //Console.WriteLine("IDCODE: 0x" + idcode.ToString("X8"));

        //if (idcode == 0x06413041)
        //    Console.WriteLine("  -> STM32F4 Boundary Scan TAP detected!");
        //else if (idcode == 0x2BA01477)
        //    Console.WriteLine("  -> ARM Cortex-M4 DAP detected!");
        //else if (idcode == 0x00000000)
        //    Console.WriteLine("  -> No response (check wiring)");
        //else
        //    Console.WriteLine("  -> Unknown device");

        //Console.WriteLine("=== Loopback with 0x13 DR Shift ===");
        //Console.WriteLine("Bridge TDI to TDO, press Enter...");
        //Console.ReadLine();

        //// Reset
        //SendCmd(new byte[] { 0x10 }, 1);
        //Console.WriteLine("Reset done");

        //// Shift 32 bits of 0xAA55AA55
        //var r = SendCmd(new byte[] { 0x13, 32, 0, 0x55, 0xAA, 0x55, 0xAA }, 4);
        //uint result = (uint)(r[0] | (r[1] << 8) | (r[2] << 16) | (r[3] << 24));
        //Console.WriteLine("Sent: 0xAA55AA55");
        //Console.WriteLine("Got:  0x" + result.ToString("X8"));

        //if (result == 0xAA55AA55)
        //    Console.WriteLine("PASS - DR shift working!");
        //else if (result == 0x00000000)
        //    Console.WriteLine("FAIL - TDO stuck low");
        //else
        //    Console.WriteLine("PARTIAL - Some bits shifted");

        //Console.WriteLine("=== Bit Alignment Tests ===");
        //Console.WriteLine("Keep TDI-TDO bridged");
        //Console.WriteLine();

        //SendCmd(new byte[] { 0x10 }, 1);
        //SendCmd(new byte[] { 0x13, 8, 0, 0xAA }, 1);  // Should see 10101010 pattern on TDI

        //Console.WriteLine("=== Consistency Test ===");

        //for (int i = 0; i < 3; i++)
        //{
        //    Console.WriteLine("Run " + (i + 1) + ":");

        //    ftdi.Purge(FTDI.FT_PURGE.FT_PURGE_RX | FTDI.FT_PURGE.FT_PURGE_TX);
        //    System.Threading.Thread.Sleep(100);

        //    SendCmd(new byte[] { 0x10 }, 1);  // Reset
        //    System.Threading.Thread.Sleep(50);

        //    var r = SendCmd(new byte[] { 0x13, 8, 0, 0xA5 }, 1);
        //    Console.WriteLine("  Sent 0xA5, Got: 0x" + r[0].ToString("X2"));

        //    System.Threading.Thread.Sleep(100);
        //}

        //SendCmd(new byte[] { 0x10 }, 1);
        //var r = SendCmd(new byte[] { 0x11 }, 4);
        //uint idcode = (uint)(r[0] | (r[1] << 8) | (r[2] << 16) | (r[3] << 24));

        //Console.WriteLine("Raw:    0x" + idcode.ToString("X8"));
        //Console.WriteLine(">> 1:   0x" + (idcode >> 1).ToString("X8"));
        //Console.WriteLine(">> 2:   0x" + (idcode >> 2).ToString("X8"));
        //Console.WriteLine(">> 3:   0x" + (idcode >> 3).ToString("X8"));
        //Console.WriteLine("<< 1:   0x" + (idcode << 1).ToString("X8"));
        //Console.WriteLine("<< 2:   0x" + (idcode << 2).ToString("X8"));
        //Console.WriteLine("<< 3:   0x" + (idcode << 3).ToString("X8"));

        //// Reset
        //SendCmd(new byte[] { 0x10 }, 1);

        //// Test 1: All ones
        //var r = SendCmd(new byte[] { 0x13, 32, 0, 0xFF, 0xFF, 0xFF, 0xFF }, 4);
        //uint result = (uint)(r[0] | (r[1] << 8) | (r[2] << 16) | (r[3] << 24));
        //Console.WriteLine("Sent: 0xFFFFFFFF");
        //Console.WriteLine("Got:  0x" + result.ToString("X8"));
        //Console.WriteLine();

        //// Test 2: All zeros
        //SendCmd(new byte[] { 0x10 }, 1);
        //r = SendCmd(new byte[] { 0x13, 32, 0, 0x00, 0x00, 0x00, 0x00 }, 4);
        //result = (uint)(r[0] | (r[1] << 8) | (r[2] << 16) | (r[3] << 24));
        //Console.WriteLine("Sent: 0x00000000");
        //Console.WriteLine("Got:  0x" + result.ToString("X8"));
        //Console.WriteLine();

        //// Test 3: Single bit
        //SendCmd(new byte[] { 0x10 }, 1);
        //r = SendCmd(new byte[] { 0x13, 32, 0, 0x01, 0x00, 0x00, 0x00 }, 4);
        //result = (uint)(r[0] | (r[1] << 8) | (r[2] << 16) | (r[3] << 24));
        //Console.WriteLine("Sent: 0x00000001");
        //Console.WriteLine("Got:  0x" + result.ToString("X8"));
        //Console.WriteLine();

        //// Test 4: Another single bit
        //SendCmd(new byte[] { 0x10 }, 1);
        //r = SendCmd(new byte[] { 0x13, 32, 0, 0x00, 0x00, 0x00, 0x80 }, 4);
        //result = (uint)(r[0] | (r[1] << 8) | (r[2] << 16) | (r[3] << 24));
        //Console.WriteLine("Sent: 0x80000000");
        //Console.WriteLine("Got:  0x" + result.ToString("X8"));

        //Console.WriteLine("=== 8-bit Tests ===");

        //SendCmd(new byte[] { 0x10 }, 1);
        //var rr = SendCmd(new byte[] { 0x13, 8, 0, 0x01 }, 1);
        //Console.WriteLine("Sent: 0x01, Got: 0x" + rr[0].ToString("X2"));

        //SendCmd(new byte[] { 0x10 }, 1);
        //rr = SendCmd(new byte[] { 0x13, 8, 0, 0x02 }, 1);
        //Console.WriteLine("Sent: 0x02, Got: 0x" + rr[0].ToString("X2"));

        //SendCmd(new byte[] { 0x10 }, 1);
        //rr = SendCmd(new byte[] { 0x13, 8, 0, 0x80 }, 1);
        //Console.WriteLine("Sent: 0x80, Got: 0x" + rr[0].ToString("X2"));

        //SendCmd(new byte[] { 0x10 }, 1);
        //rr = SendCmd(new byte[] { 0x13, 8, 0, 0x55 }, 1);
        //Console.WriteLine("Sent: 0x55, Got: 0x" + rr[0].ToString("X2"));

        //SendCmd(new byte[] { 0x10 }, 1);
        //rr = SendCmd(new byte[] { 0x13, 8, 0, 0xAA }, 1);
        //Console.WriteLine("Sent: 0xAA, Got: 0x" + rr[0].ToString("X2"));

        ftdi.Close();

    }

    static void Configure()
    {
        ftdi.ResetDevice();
        ftdi.SetLatency(2);
        ftdi.InTransferSize(65536);
        ftdi.SetTimeouts(1000, 1000);
        ftdi.Purge(FTDI.FT_PURGE.FT_PURGE_RX | FTDI.FT_PURGE.FT_PURGE_TX);
        ftdi.SetBitMode(0x00, FTDI.FT_BIT_MODES.FT_BIT_MODE_RESET);
    }

    static byte[] SendCmd(byte[] cmd, int expectLen)
    {
        uint written = 0;
        uint actual = 0;
        byte[] buf = new byte[expectLen];

        ftdi.Write(cmd, cmd.Length, ref written);
        System.Threading.Thread.Sleep(300);
        ftdi.Read(buf, (uint)expectLen, ref actual);

        return buf;
    }
}
