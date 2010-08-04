module runUnittests_dmd;

import tango.core.Array;
import tango.core.Atomic;
import tango.core.BitArray;
import tango.core.BitManip;
import tango.core.ByteSwap;
import tango.core.Exception;
import tango.core.Memory;
import tango.core.Runtime;
import tango.core.RuntimeTraits;
import tango.core.Signal;
import tango.core.sync.Atomic;
import tango.core.sync.Barrier;
import tango.core.sync.Condition;
import tango.core.sync.Config;
import tango.core.sync.Mutex;
import tango.core.sync.ReadWriteMutex;
import tango.core.sync.Semaphore;
import tango.core.Thread;
import tango.core.ThreadPool;
import tango.core.tools.Cpuid;
import tango.core.tools.Demangler;
import tango.core.tools.LinuxStackTrace;
import tango.core.tools.StackTrace;
import tango.core.tools.TraceExceptions;
import tango.core.tools.WinStackTrace;
import tango.core.Traits;
import tango.core.Tuple;
import tango.core.Vararg;
import tango.core.Variant;
import tango.core.Version;
import tango.core.WeakRef;
import tango.io.Console;
import tango.io.device.Array;
import tango.io.device.BitBucket;
import tango.io.device.Conduit;
import tango.io.device.Device;
import tango.io.device.File;
import tango.io.device.FileMap;
import tango.io.device.SerialPort;
import tango.io.device.TempFile;
import tango.io.device.ThreadPipe;
import tango.io.FilePath;
import tango.io.FileScan;
import tango.io.FileSystem;
import tango.io.model.IConduit;
import tango.io.model.IFile;
import tango.io.Path;
import tango.io.selector.AbstractSelector;
import tango.io.selector.EpollSelector;
import tango.io.selector.model.ISelector;
import tango.io.selector.PollSelector;
import tango.io.selector.Selector;
import tango.io.selector.SelectorException;
import tango.io.selector.SelectSelector;
import tango.io.Stdout;
import tango.io.stream.Buffered;
import tango.io.stream.Bzip;
import tango.io.stream.Data;
import tango.io.stream.DataFile;
import tango.io.stream.Delimiters;
import tango.io.stream.Digester;
import tango.io.stream.Endian;
import tango.io.stream.Format;
import tango.io.stream.Greedy;
import tango.io.stream.Iterator;
import tango.io.stream.Lines;
import tango.io.stream.Map;
import tango.io.stream.Patterns;
import tango.io.stream.Quotes;
import tango.io.stream.Snoop;
import tango.io.stream.Text;
import tango.io.stream.TextFile;
import tango.io.stream.Typed;
import tango.io.stream.Utf;
import tango.io.stream.Zlib;
import tango.io.UnicodeFile;
import tango.io.vfs.FileFolder;
import tango.io.vfs.FtpFolder;
import tango.io.vfs.LinkedFolder;
import tango.io.vfs.model.Vfs;
import tango.io.vfs.VirtualFolder;
import tango.io.vfs.ZipFolder;
import tango.math.Bessel;
import tango.math.BigInt;
import tango.math.Bracket;
import tango.math.Elliptic;
import tango.math.ErrorFunction;
import tango.math.GammaFunction;
import tango.math.IEEE;
import tango.math.internal.BignumNoAsm;
import tango.math.internal.BignumX86;
import tango.math.internal.BiguintCore;
import tango.math.Math;
import tango.math.Probability;
import tango.math.random.engines.ArraySource;
import tango.math.random.engines.CMWC;
import tango.math.random.engines.KISS;
import tango.math.random.engines.KissCmwc;
import tango.math.random.engines.Sync;
import tango.math.random.engines.Twister;
import tango.math.random.engines.URandom;
import tango.math.random.ExpSource;
import tango.math.random.Kiss;
import tango.math.random.NormalSource;
import tango.math.random.Random;
import tango.math.random.Twister;
import tango.math.random.Ziggurat;
import tango.net.device.Berkeley;
import tango.net.device.Datagram;
import tango.net.device.LocalSocket;
import tango.net.device.Multicast;
import tango.net.device.Socket;
import tango.net.device.SSLSocket;
import tango.net.ftp.FtpClient;
import tango.net.ftp.Telnet;
import tango.net.http.ChunkStream;
import tango.net.http.HttpClient;
import tango.net.http.HttpConst;
import tango.net.http.HttpCookies;
import tango.net.http.HttpGet;
import tango.net.http.HttpHeaders;
import tango.net.http.HttpParams;
import tango.net.http.HttpPost;
import tango.net.http.HttpStack;
import tango.net.http.HttpTokens;
import tango.net.http.HttpTriplet;
import tango.net.http.model.HttpParamsView;
import tango.net.InternetAddress;
import tango.net.model.UriView;
import tango.net.Uri;
import tango.net.util.c.OpenSSL;
import tango.net.util.MemCache;
import tango.net.util.PKI;
import tango.stdc.complex;
import tango.stdc.config;
import tango.stdc.ctype;
import tango.stdc.errno;
import tango.stdc.fenv;
import tango.stdc.inttypes;
import tango.stdc.limits;
import tango.stdc.locale;
import tango.stdc.math;
import tango.stdc.posix.arpa.inet;
import tango.stdc.posix.config;
import tango.stdc.posix.dirent;
import tango.stdc.posix.dlfcn;
import tango.stdc.posix.fcntl;
import tango.stdc.posix.inttypes;
import tango.stdc.posix.langinfo;
import tango.stdc.posix.net.if_;
import tango.stdc.posix.netinet.in_;
import tango.stdc.posix.netinet.tcp;
import tango.stdc.posix.poll;
import tango.stdc.posix.pthread;
import tango.stdc.posix.pwd;
import tango.stdc.posix.sched;
import tango.stdc.posix.semaphore;
import tango.stdc.posix.setjmp;
import tango.stdc.posix.signal;
import tango.stdc.posix.stdio;
import tango.stdc.posix.stdlib;
import tango.stdc.posix.sys.ipc;
import tango.stdc.posix.sys.mman;
import tango.stdc.posix.sys.select;
import tango.stdc.posix.sys.shm;
import tango.stdc.posix.sys.socket;
import tango.stdc.posix.sys.stat;
import tango.stdc.posix.sys.statvfs;
import tango.stdc.posix.sys.time;
import tango.stdc.posix.sys.types;
import tango.stdc.posix.sys.uio;
import tango.stdc.posix.sys.utsname;
import tango.stdc.posix.sys.wait;
import tango.stdc.posix.termios;
import tango.stdc.posix.time;
import tango.stdc.posix.ucontext;
import tango.stdc.posix.unistd;
import tango.stdc.posix.utime;
import tango.stdc.signal;
import tango.stdc.stdarg;
import tango.stdc.stddef;
import tango.stdc.stdint;
import tango.stdc.stdio;
import tango.stdc.stdlib;
import tango.stdc.string;
import tango.stdc.stringz;
import tango.stdc.tgmath;
import tango.stdc.time;
import tango.stdc.wctype;
import tango.sys.Common;
import tango.sys.consts.errno;
import tango.sys.consts.fcntl;
import tango.sys.consts.socket;
import tango.sys.consts.sysctl;
import tango.sys.consts.unistd;
import tango.sys.darwin.consts.errno;
import tango.sys.darwin.consts.fcntl;
import tango.sys.darwin.consts.machine;
import tango.sys.darwin.consts.socket;
import tango.sys.darwin.consts.sysctl;
import tango.sys.darwin.consts.unistd;
import tango.sys.darwin.darwin;
import tango.sys.Environment;
import tango.sys.freebsd.consts.errno;
import tango.sys.freebsd.consts.fcntl;
import tango.sys.freebsd.consts.socket;
import tango.sys.freebsd.consts.sysctl;
import tango.sys.freebsd.consts.unistd;
import tango.sys.freebsd.freebsd;
import tango.sys.HomeFolder;
import tango.sys.linux.consts.errno;
import tango.sys.linux.consts.fcntl;
import tango.sys.linux.consts.socket;
import tango.sys.linux.consts.sysctl;
import tango.sys.linux.consts.unistd;
import tango.sys.linux.epoll;
import tango.sys.linux.inotify;
import tango.sys.linux.linux;
import tango.sys.linux.tipc;
import tango.sys.Pipe;
import tango.sys.Process;
import tango.sys.SharedLib;
import tango.sys.solaris.consts.errno;
import tango.sys.solaris.consts.fcntl;
import tango.sys.solaris.consts.socket;
import tango.sys.solaris.consts.sysctl;
import tango.sys.solaris.consts.unistd;
import tango.sys.solaris.solaris;
import tango.text.Arguments;
import tango.text.Ascii;
import tango.text.convert.DateTime;
import tango.text.convert.Float;
import tango.text.convert.Format;
import tango.text.convert.Integer;
import tango.text.convert.Layout;
import tango.text.convert.TimeStamp;
import tango.text.convert.UnicodeBom;
import tango.text.convert.Utf;
import tango.text.json.Json;
import tango.text.json.JsonEscape;
import tango.text.json.JsonParser;
import tango.text.locale.Collation;
import tango.text.locale.Convert;
import tango.text.locale.Core;
import tango.text.locale.Data;
import tango.text.locale.Locale;
import tango.text.locale.Parse;
import tango.text.locale.Posix;
import tango.text.Regex;
import tango.text.Search;
import tango.text.Text;
import tango.text.Unicode;
import tango.text.UnicodeData;
import tango.text.Util;
import tango.text.xml.DocEntity;
import tango.text.xml.DocPrinter;
import tango.text.xml.DocTester;
import tango.text.xml.Document;
import tango.text.xml.PullParser;
import tango.text.xml.SaxParser;
import tango.time.chrono.Calendar;
import tango.time.chrono.Gregorian;
import tango.time.chrono.GregorianBased;
import tango.time.chrono.Hebrew;
import tango.time.chrono.Hijri;
import tango.time.chrono.Japanese;
import tango.time.chrono.Korean;
import tango.time.chrono.Taiwan;
import tango.time.chrono.ThaiBuddhist;
import tango.time.Clock;
import tango.time.ISO8601;
import tango.time.StopWatch;
import tango.time.Time;
import tango.time.WallClock;
import tango.util.cipher.AES;
import tango.util.cipher.Blowfish;
import tango.util.cipher.ChaCha;
import tango.util.cipher.Cipher;
import tango.util.cipher.RC4;
import tango.util.cipher.RC6;
import tango.util.cipher.Salsa20;
import tango.util.cipher.TEA;
import tango.util.cipher.XTEA;
import tango.util.compress.c.bzlib;
import tango.util.compress.c.zlib;
import tango.util.compress.Zip;
import tango.util.container.CircularList;
import tango.util.container.Clink;
import tango.util.container.Container;
import tango.util.container.HashMap;
import tango.util.container.HashSet;
import tango.util.container.LinkedList;
import tango.util.container.model.IContainer;
import tango.util.container.more.BitSet;
import tango.util.container.more.CacheMap;
import tango.util.container.more.HashFile;
import tango.util.container.more.Heap;
import tango.util.container.more.Stack;
import tango.util.container.more.StackMap;
import tango.util.container.more.Vector;
import tango.util.container.RedBlack;
import tango.util.container.Slink;
import tango.util.container.SortedMap;
import tango.util.Convert;
import tango.util.digest.Crc32;
import tango.util.digest.Digest;
import tango.util.digest.Md2;
import tango.util.digest.Md4;
import tango.util.digest.Md5;
import tango.util.digest.MerkleDamgard;
import tango.util.digest.Ripemd128;
import tango.util.digest.Ripemd160;
import tango.util.digest.Ripemd256;
import tango.util.digest.Ripemd320;
import tango.util.digest.Sha0;
import tango.util.digest.Sha01;
import tango.util.digest.Sha1;
import tango.util.digest.Sha256;
import tango.util.digest.Sha512;
import tango.util.digest.Tiger;
import tango.util.digest.Whirlpool;
import tango.util.encode.Base16;
import tango.util.encode.Base32;
import tango.util.encode.Base64;
import tango.util.log.AppendConsole;
import tango.util.log.AppendFile;
import tango.util.log.AppendFiles;
import tango.util.log.AppendMail;
import tango.util.log.AppendSocket;
import tango.util.log.Config;
import tango.util.log.ConfigProps;
import tango.util.log.LayoutChainsaw;
import tango.util.log.LayoutDate;
import tango.util.log.Log;
import tango.util.log.model.ILogger;
import tango.util.log.Trace;
import tango.util.MinMax;
import tango.util.uuid.NamespaceGenV3;
import tango.util.uuid.NamespaceGenV5;
import tango.util.uuid.RandomGen;
import tango.util.uuid.Uuid;

import tango.io.Stdout;
import tango.core.Runtime;
import tango.core.tools.TraceExceptions;

bool tangoUnitTester()
{
    uint countFailed = 0;
    uint countTotal = 1;
    Stdout ("NOTE: This is still fairly rudimentary, and will only report the").newline;
    Stdout ("    first error per module.").newline;
    foreach ( m; ModuleInfo )  // _moduleinfo_array )
    {
        if ( m.unitTest) {
            Stdout.format ("{}. Executing unittests in '{}' ", countTotal, m.name).flush;
            countTotal++;
            try {
               m.unitTest();
            }
            catch (Exception e) {
                countFailed++;
                Stdout(" - Unittest failed.").newline;
                e.writeOut(delegate void(char[]s){ Stdout(s); });
                continue;
            }
            Stdout(" - Success.").newline;
        }
    }

    Stdout.format ("{} out of {} tests failed.", countFailed, countTotal - 1).newline;
    return true;
}

static this() {
    Runtime.moduleUnitTester( &tangoUnitTester );
}

void main() {}
