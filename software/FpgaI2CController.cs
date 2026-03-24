using System;
using System.Collections.Generic;
using System.Threading;
using FTD2XX_NET;

namespace I2CJtagEngine
{
    /// <summary>
    /// FPGA-accelerated I2C controller via FT2232H Async FIFO (Channel B)
    /// No CLKOUT, no OE# - uses async 245 FIFO mode
    /// </summary>
    public class FpgaI2CController : IDisposable
    {
        private FTDI _ftdi;
        private bool _disposed;

        // Command codes
        private const byte CMD_JTAG_RESET     = 0x01;
        private const byte CMD_READ_IDCODE    = 0x02;
        private const byte CMD_I2C_WRITE      = 0x20;
        private const byte CMD_I2C_READ       = 0x21;
        private const byte CMD_I2C_WRITE_READ = 0x22;
        private const byte CMD_I2C_SCAN       = 0x23;
        private const byte CMD_LED_CTRL       = 0x40;

        // Response codes
        private const byte RESP_ACK  = 0xA0;
        private const byte RESP_NACK = 0xA1;

        /// <summary>
        /// Open FT2232H Channel B (index 1) in async FIFO mode
        /// </summary>
        public FpgaI2CController(uint deviceIndex = 1)  // Channel B = index 1
        {
            _ftdi = new FTDI();
            
            var status = _ftdi.OpenByIndex(deviceIndex);
            if (status != FTDI.FT_STATUS.FT_OK)
                throw new Exception($"Failed to open device: {status}");

            ConfigureAsyncFifo();
        }

        public FpgaI2CController(string serialNumber)
        {
            _ftdi = new FTDI();
            
            // Channel B typically has serial + "B" suffix
            var status = _ftdi.OpenBySerialNumber(serialNumber);
            if (status != FTDI.FT_STATUS.FT_OK)
                throw new Exception($"Failed to open device: {status}");

            ConfigureAsyncFifo();
        }

        private void ConfigureAsyncFifo()
        {
            CheckStatus(_ftdi.ResetDevice());
            CheckStatus(_ftdi.SetLatency(2));
            CheckStatus(_ftdi.InTransferSize(65536));
            CheckStatus(_ftdi.SetTimeouts(1000, 1000));
            CheckStatus(_ftdi.Purge(FTDI.FT_PURGE.FT_PURGE_RX | FTDI.FT_PURGE.FT_PURGE_TX));
            
            // Async 245 FIFO mode (NOT sync - no clock available)
            CheckStatus(_ftdi.SetBitMode(0xFF, FTDI.FT_BIT_MODES.FT_BIT_MODE_ASYNC_BITBANG));
            Thread.Sleep(10);
            CheckStatus(_ftdi.SetBitMode(0x00, FTDI.FT_BIT_MODES.FT_BIT_MODE_RESET));
            Thread.Sleep(10);
            
            // Now in standard 245 FIFO mode (async)
        }

        /// <summary>
        /// Reset the JTAG TAP state machine
        /// </summary>
        public void ResetJtag()
        {
            Send(new byte[] { CMD_JTAG_RESET });
            var resp = Read(1);
            if (resp[0] != 0x81)
                throw new Exception("JTAG reset failed");
        }

        /// <summary>
        /// Read target device IDCODE
        /// </summary>
        public uint ReadIdCode()
        {
            Send(new byte[] { CMD_READ_IDCODE });
            var resp = Read(5);
            
            if (resp[0] != 0x82)
                throw new Exception("IDCODE read failed");
            
            return (uint)(resp[1] | (resp[2] << 8) | (resp[3] << 16) | (resp[4] << 24));
        }

        /// <summary>
        /// Write data to I2C device
        /// </summary>
        public bool Write(byte address, params byte[] data)
        {
            if (data.Length > 32)
                throw new ArgumentException("Maximum 32 bytes per transaction");

            var cmd = new byte[3 + data.Length];
            cmd[0] = CMD_I2C_WRITE;
            cmd[1] = address;
            cmd[2] = (byte)data.Length;
            Array.Copy(data, 0, cmd, 3, data.Length);
            
            Send(cmd);
            var resp = Read(1);
            
            return resp[0] == RESP_ACK;
        }

        /// <summary>
        /// Read data from I2C device
        /// </summary>
        public byte[]? Read(byte address, int count)
        {
            if (count > 32)
                throw new ArgumentException("Maximum 32 bytes per transaction");

            Send(new byte[] { CMD_I2C_READ, address, (byte)count });
            var resp = Read(1 + count);
            
            if (resp[0] != RESP_ACK)
                return null;
            
            var data = new byte[count];
            Array.Copy(resp, 1, data, 0, count);
            return data;
        }

        /// <summary>
        /// Write then read
        /// </summary>
        public byte[]? WriteRead(byte address, byte[] writeData, int readCount)
        {
            if (writeData.Length > 32 || readCount > 32)
                throw new ArgumentException("Maximum 32 bytes per transaction");

            var cmd = new byte[4 + writeData.Length];
            cmd[0] = CMD_I2C_WRITE_READ;
            cmd[1] = address;
            cmd[2] = (byte)writeData.Length;
            cmd[3] = (byte)readCount;
            Array.Copy(writeData, 0, cmd, 4, writeData.Length);
            
            Send(cmd);
            var resp = Read(1 + readCount);
            
            if (resp[0] != RESP_ACK)
                return null;
            
            var data = new byte[readCount];
            Array.Copy(resp, 1, data, 0, readCount);
            return data;
        }

        /// <summary>
        /// Scan I2C bus
        /// </summary>
        public List<byte> ScanBus(byte startAddr = 0x08, byte endAddr = 0x77)
        {
            var found = new List<byte>();
            
            for (byte addr = startAddr; addr <= endAddr; addr++)
            {
                Send(new byte[] { CMD_I2C_WRITE, addr, 0 });
                var resp = Read(1);
                
                if (resp[0] == RESP_ACK)
                    found.Add(addr);
            }
            
            return found;
        }

        /// <summary>
        /// Control debug LEDs
        /// </summary>
        public void SetLeds(bool led1, bool led2)
        {
            byte value = (byte)((led1 ? 1 : 0) | (led2 ? 2 : 0));
            Send(new byte[] { CMD_LED_CTRL, value });
            Read(1);
        }

        private void Send(byte[] data)
        {
            uint written = 0;
            var status = _ftdi.Write(data, data.Length, ref written);
            if (status != FTDI.FT_STATUS.FT_OK || written != data.Length)
                throw new Exception($"Write failed: {status}");
        }

        private byte[] Read(int count)
        {
            var buffer = new byte[count];
            uint totalRead = 0;
            int attempts = 0;

            while (totalRead < count && attempts < 200)
            {
                uint read = 0;
                var tmpBuf = new byte[count - totalRead];
                _ftdi.Read(tmpBuf, (uint)(count - totalRead), ref read);
                
                if (read > 0)
                {
                    Array.Copy(tmpBuf, 0, buffer, totalRead, read);
                    totalRead += read;
                }
                else
                {
                    Thread.Sleep(5);
                    attempts++;
                }
            }

            if (totalRead < count)
                throw new Exception($"Read timeout: got {totalRead}/{count} bytes");

            return buffer;
        }

        private void CheckStatus(FTDI.FT_STATUS status)
        {
            if (status != FTDI.FT_STATUS.FT_OK)
                throw new Exception($"FTDI error: {status}");
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                _ftdi?.Close();
                _disposed = true;
            }
        }
    }
}
