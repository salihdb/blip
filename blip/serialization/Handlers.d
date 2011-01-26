/// methods that handle the i/o of the basic types.
/// Serializers/unserializers are built on the top of these.
/// at the moment they are quite ugly, and their realization
/// does suffer from a series of bugs in using interfaces, templates and aliases
/// should be rewritten once the compiler improves
///
/// author: fawzi 
//
// Copyright 2008-2010 the blip developer group
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
module blip.serialization.Handlers;
import tango.core.Version;
import tango.core.Tuple;
import blip.io.BasicIO;
import tango.io.model.IConduit;
import tango.text.json.JsonEscape: escape;
static if (Tango.Major==1){
  import tango.util.encode.Base64: encode,decode,allocateEncodeSize;
} else {
  import tango.io.encode.Base64: encode,decode,allocateEncodeSize;
}
import blip.core.Variant;
import tango.core.ByteSwap;
import blip.core.Traits: RealTypeOf,ctfe_i2a, ElementTypeOfArray;
import blip.math.Math:min;
import tango.core.Exception: IOException;
import blip.text.TextParser;
import blip.text.UtfUtils;
import blip.BasicModels;
import blip.io.StreamConverters: ReadHandler;
import blip.Comp;

/// the non array core types
template isBasicCoreType(T){
    const bool isBasicCoreType=is(T==bool)||is(T==byte)||is(T==ubyte)||is(T==short)
     ||is(T==ushort)||is(T==int)||is(T==uint)||is(T==float)
     ||is(T==long)||is(T==ulong)||is(T==double)||is(T==real)
     ||is(T==ifloat)||is(T==idouble)||is(T==ireal)||is(T==cfloat)
     ||is(T==cdouble)||is(T==creal)||is(T==char[])||is(T==wchar[])||is(T==dchar[]);
}
/// the basic types, out of these more complex types are built
template isCoreType(T){
    const bool isCoreType=is(T==bool)||is(T==byte)||is(T==ubyte)||is(T==short)
     ||is(T==ushort)||is(T==int)||is(T==uint)||is(T==float)
     ||is(T==long)||is(T==ulong)||is(T==double)||is(T==real)
     ||is(T==ifloat)||is(T==idouble)||is(T==ireal)||is(T==cfloat)
     ||is(T==cdouble)||is(T==creal)||is(T==char[])||is(T==wchar[])
     ||is(T==dchar[])||is(T==ubyte[])||is(T==void[]);
}

alias Tuple!(bool,byte,ubyte,short,ushort,int,uint,long,ulong,
    float,double,real,ifloat,idouble,ireal,cfloat,cdouble,creal,ubyte[],
    char[],wchar[],dchar[],void[]) CoreTypes;
alias Tuple!(char[],wchar[],dchar[]) CoreStringTypes;

/// string suitable to build names for the core type T
template strForCoreType(T){
    static if (is(T S:S[])){
        static if (is(T==ubyte[])){
            const istring strForCoreType="binaryBlob";
        } else static if (is(T==void[])){
            const istring strForCoreType="binaryBlob2";
        } else {
            const istring strForCoreType=S.stringof~"Str";
        }
    } else{
        const istring strForCoreType=T.stringof;
    }
}

/// generates a delegate for each type, this can be used to buid a kind of VTable
/// and hide the use of templates
string coreTypeDelegates(string indent="    "){
    string res="".dup;
    foreach (T;CoreTypes){
        res~=indent~"void delegate(ref "~T.stringof~" el) coreHandler_"~strForCoreType!(T)~";\n";
    }
    return res;
}

/// transfers all template implementations to the "V-table"
string coreHandlerSetFromTemplateMixinStr(string templateCall, string templateStr=null, string indent="    "){
    string res="".dup;
    if (templateStr is null) templateStr=templateCall;
    res~=indent~"void setCoreHandlersFrom_"~templateStr~"(){\n";
    foreach (T;CoreTypes){
        res~=indent~"    coreHandler_"~strForCoreType!(T)~"= &("~templateCall~"!("~T.stringof~"));\n";
    }
    res~=indent~"}\n";
    return res;
}

/// class to have dynamic dispatching of methods generated by templates
/// basically this is a V-table that can be initialized from a template
/// this trick removes the template dependence
class CoreHandlers{
    this(){}
    
    mixin(coreTypeDelegates());

    void handle(T)(ref T t){
        static if (is(T==OutWriter)){
            handleOutWriter(t);
        } else static if (is(T==BinWriter)){
            handleBinWriter(t);
        } else static if (is(T==CharReader)){
            handleCharReader(t);
        } else static if (is(T==BinReader)){
            handleBinReader(t);
        } else {
            static assert(isCoreType!(T),T.stringof~" is not a core type");
            mixin("coreHandler_"~strForCoreType!(T)~"(t);");
        }
    }
    void handleOutWriter(OutWriter w){
        assert(0,"unimplemented");
    }
    void handleBinWriter(BinWriter w){
        assert(0,"unimplemented");
    }
    void handleCharReader(CharReader w){
        assert(0,"unimplemented");
    }
    void handleBinReader(BinReader w){
        assert(0,"unimplemented");
    }
}

/// handlers for writing
class WriteHandlers: CoreHandlers,OutStreamI{
    void delegate() flusher;
    
    this(void delegate() f){ flusher=f; }
    
    /// flushes the underlying stream if possible
    void flush(){
        if (flusher !is null) flusher();
    }
    /// nicer way to write out
    WriteHandlers opCall(T)(T t){
        static assert(isCoreType!(T),T.stringof~" is not a core type");
        mixin("coreHandler_"~strForCoreType!(T)~"(t);");
        return this;
    }
    /// returns if the current protocol is binary or not
    bool binary(){
        assert(0,"unimplemented");
    }
    /// writes a raw sequence of bytes
    void rawWrite(void[] data){
        assert(0,"unimplemented");
    }
    /// writes a raw string
    void rawWriteStrC(cstring data){
        assert(0,"unimplemented");
    }
    void rawWriteStrW(cstringw data){
        assert(0,"unimplemented");
    }
    void rawWriteStrD(cstringd data){
        assert(0,"unimplemented");
    }
    //alias rawWriteStrC rawWriteStr;
    //alias rawWriteStrW rawWriteStr;
    //alias rawWriteStrD rawWriteStr;
    void rawWriteStr(cstring data){
        assert(0,"unimplemented");
    }
    void rawWriteStr(cstringw data){
        assert(0,"unimplemented");
    }
    void rawWriteStr(cstringd data){
        assert(0,"unimplemented");
    }
    override void handleOutWriter(OutWriter w){
        w(&rawWriteStr);
    }
    override void handleBinWriter(BinWriter w){
        w(&rawWrite);
    }
    CharSink charSink(){
        return cast(void delegate(cstring))&this.rawWriteStr;
    }
    BinSink binSink(){
        return &this.rawWrite;
    }
    void close(){
        assert(0,"unimplemented");
    }
}

/// handlers for reading
class ReadHandlers: CoreHandlers{
    this(){}
    /// nicer way to read in
    ReadHandlers opCall(T)(ref T t){
        static assert(isCoreType!(T),T.stringof~" is not a core type");
        mixin("coreHandler_"~strForCoreType!(T)~"(t);");
        return this;
    }
    /// returns if the current protocol is binary or not
    bool binary(){
        assert(0,"unimplemented");
    }
    /// reads a raw sequence of bytes
    ubyte[] rawRead(size_t amount){
        assert(0,"unimplemented");
    }
    /// reads a raw string
    char[] rawReadStr(size_t amount){
        assert(0,"unimplemented");
    }
    /// skips the given string from the input
    bool skipString(cstring str,bool shouldThrow){
        auto res=rawReadStr(nCodePoints(str));
        if (res!=str){
            if (shouldThrow)
                throw new Exception("could not skip string '"~str~"'",__FILE__,__LINE__);
            else
                throw new Exception("failed skip string '"~str~"' unimplemented",__FILE__,__LINE__);
        }
        return true;
    }
    /// skips the given bit pattern from the input
    bool skipBytes(ubyte[]str,bool shouldThrow){
        auto res=rawRead(str.length);
        if (res!=str){
            if (shouldThrow)
                throw new Exception("could not skip bytes",__FILE__,__LINE__);
            else
                throw new Exception("failed skip bytes unimplemented",__FILE__,__LINE__);
        }
        return true;
    }
    /// current read position (only informative)
    void parserPos(void delegate(cstring) s){
    }
    void handleCharReader(CharReader r){
        throw new Exception("unimplemented",__FILE__,__LINE__);
    }
    void handleBinReader(BinReader r){
        throw new Exception("unimplemented",__FILE__,__LINE__);
    }
}

version (BigEndian){
    enum:bool{ isSmallEndian=false }
} else {
    enum:bool{ isSmallEndian=true }
}

/// binary write handlers
/// build it on the top of OutputBuffer? would spare a buffer and its copy if SwapBytes is true
final class BinaryWriteHandlers(bool SwapBytes=isSmallEndian):WriteHandlers{
    void delegate(void[]) writer;
    void delegate() _close;
    
    this (void delegate(void[]) writer, void delegate() flusher=null, void delegate() _close=null)
    {
        super(flusher);
        this.writer=writer;
        this.flusher=flusher;
        this._close=_close;
        setCoreHandlersFrom_basicWrite();
    }
    this (OutStreamI w){
        this(&w.rawWrite,&w.flush,&w.close);
    }

    /+ /// guartees the given alignment
    void alignStream(int i){
        assert(i>0&&i<=32);
        if (i==1) return;
        auto pos=writer.seek(0,Anchor.Current);
        if (pos==Eof) return;
        auto rest=pos & (~((~0)<<i));
        if (rest==0) return;
        ubyte u=0;
        for (int j=(1<<(i-1))-rest;j!=0;--j)
            writer.handle(u);
    }+/
    
    void writeExact(void[]d){
        writer(d);
    }
    
    /// writes an ulong compressed, useful if the value is expected to be small
    void writeCompressed(ulong l){
        while (1){
            ubyte u=cast(ubyte)(l & 0x7FFF);
            l=l>>7;
            if (l!=0){
                ubyte u2=u|0x8000;
                handle(u2);
            } else {
                handle(u);
                break;
            }
        }
    }

    /// writes a core type
    void basicWrite(T)(ref T t){
        static assert(isCoreType!(T),"only core types supported, not "~T.stringof);
        static if (is(T==cfloat)||is(T==cdouble)||is(T==creal)){
            RealTypeOf!(T) tt=t.re;
            basicWrite!(RealTypeOf!(T))(tt);
            tt=t.im;
            basicWrite!(RealTypeOf!(T))(tt);
        } else static if (is(T U:U[])){
            if (!is(U==ubyte)){
                writeCompressed(cast(ulong)t.length*U.sizeof);
            }
            static if ((! SwapBytes) || U.sizeof==1){
                writeExact((cast(void*)t.ptr)[0..t.length*U.sizeof]);
            } else {
                ubyte[1024] buf;
                size_t written=0;
                size_t toWrite=min(t.length*U.sizeof,buf.length);
                while(toWrite>0){
                    buf[0..toWrite]=(cast(ubyte*)t.ptr)[written..written+toWrite];
                    written+=toWrite;
                    static if (U.sizeof==2) {
                        ByteSwap.swap16(buf.ptr,toWrite);
                    } else static if (U.sizeof==4){
                        ByteSwap.swap32(buf.ptr,toWrite);
                    } else {
                        static assert(0,"unexpected size");
                    }
                    writeExact(buf[0..toWrite]);
                    toWrite=min(buf.length,t.length*U.sizeof-written);
                }
            }
        } else{
            static if ((! SwapBytes) || T.sizeof==1){
                writeExact((cast(ubyte*)&t)[0..T.sizeof]);
            } else {
                ubyte[T.sizeof] buf;
                ubyte* a=cast(ubyte*)&t;
                for (size_t i=0;i!=T.sizeof;++i) buf[T.sizeof-1-i]=a[i];
                writeExact(buf);
            }
        }
    }
    
    mixin(coreHandlerSetFromTemplateMixinStr("basicWrite"));
    
    /// returns if the current protocol is binary or not
    bool binary(){
        return true;
    }
    /// writes a raw sequence of bytes
    void rawWrite(void[] data){
        basicWrite(data);
    }
    /// writes a raw string
    void rawWriteStrC(cstring data){
        writer(data);
    }
    void rawWriteStrW(cstringw data){
        writer(data);
    }
    void rawWriteStrD(cstringd data){
        writer(data);
    }
    //alias rawWriteStrC rawWriteStr;
    //alias rawWriteStrW rawWriteStr;
    //alias rawWriteStrD rawWriteStr;
    void rawWriteStr(cstring data){
        writer(data);
    }
    void rawWriteStr(cstringw data){
        writer(data);
    }
    void rawWriteStr(cstringd data){
        writer(data);
    }
    CharSink charSink(){
        return &this.rawWriteStrC;
    }
    BinSink binSink(){
        return writer;
    }
    void close(){
        flush();
        if (_close !is null)
            _close();
    }
}

/// binary read handlers
/// build it on the top of InputBuffer? would spare a buffer and its copy if SwapBytes
final class BinaryReadHandlers(bool SwapBytes=isSmallEndian):ReadHandlers{
    InputStream       tangoReader;
    Reader!(void)     reader;
    void delegate(void[]dest) readExact;
    
    this (Reader!(void) reader)
    {
        this.reader=reader;
        auto tReader=cast(ReadHandler!(void))reader;
        if (tReader is null){ 
            readExact=&this.readExactReader;
        } else {
            this.tangoReader=((tReader.buf is null)?cast(InputStream)tReader.arr:cast(InputStream)tReader.buf);
            readExact=&this.readExactTango;
        }
        setCoreHandlersFrom_basicRead();
    }
    this (void delegate(void[])readExact){
        this.readExact=readExact;
        setCoreHandlersFrom_basicRead();
    }
    
    void readExactReader(void[] dest){
        blip.io.BasicIO.readExact(&reader.readSome,dest);
    }
    void readExactTango(void[] dest){
        auto read=tangoReader.read(dest);
        if (read!=dest.length){
            if (read==OutputStream.Eof){
                throw new Exception("unexpected Eof",__FILE__,__LINE__);
            }
            uint countEmpty=0;
            while (1){
                auto readNow=tangoReader.read(dest[read..$]);
                if (readNow==OutputStream.Eof){
                    throw new Exception("unexpected Eof",__FILE__,__LINE__);
                } else if (readNow==0){
                    if (countEmpty==100)
                        throw new Exception("unexpected suspension",__FILE__,__LINE__);
                    else
                        ++countEmpty;
                } else {
                    countEmpty=0;
                }
                read+=readNow;
                if (read>=dest.length) break;
            }
        }
    }
    
    /// returns if the current protocol is binary or not
    bool binary(){
        return true;
    }
    /// reads a compressed ulong (useful for numbers that are likely to be small)
    void readCompressed(ref ulong l){
        while (1){
            ubyte u;
            handle(u);
            l=(l<<7)|(cast(ulong)(u & 0x7FFF));
            if (!(u&0x8000)) break;
        }
    }
    /// reads a core type
    void basicRead(T)(ref T t){
        static assert(isCoreType!(T),"only core types supported");
        static if (is(T==cfloat)||is(T==cdouble)||is(T==creal)){
            RealTypeOf!(T)* tt=cast(RealTypeOf!(T)*)&t;
            basicRead(*tt);
            basicRead(tt[1]);
        } else static if (is(T U:U[])){
            if (!is(U==ubyte)){
                ulong length;
                readCompressed(length);
                if (length>=size_t.max){
                    throw new Exception("string too long for 32 bit",__FILE__,__LINE__);
                }
                t.length=cast(size_t)length/U.sizeof;
                if (length%U.sizeof != 0){
                    throw new Exception("bad length",__FILE__,__LINE__);
                }
            }
            void[] buf=(cast(void*)t.ptr)[0..t.length*U.sizeof];
            readExact(buf);
            static if ( SwapBytes && U.sizeof!=1){
                static if (U.sizeof==2) {
                    ByteSwap.swap16(buf);
                } else static if (U.sizeof==4){
                    ByteSwap.swap32(buf);
                } else {
                    static assert(0,"unexpected size");
                }
            }
        } else{
            static if ( (!SwapBytes) || T.sizeof==1){
                void[] buf=(cast(void*)&t)[0..T.sizeof];
                readExact(buf);
            } else {
                ubyte[T.sizeof] buf;
                readExact(buf);
                ubyte* a=cast(ubyte*)&t;
                for (int i=0;i!=T.sizeof;++i) a[T.sizeof-1-i]=buf[i];
            }
        }
    }
    mixin(coreHandlerSetFromTemplateMixinStr("basicRead"));

    /// reads a raw sequence of bytes
    ubyte[] rawRead(size_t amount){
        ubyte[] data;
        basicRead(data);
        return data;
    }
    /// reads a raw string, amount is the number of *codepoints*!
    char[] rawReadStr(size_t amount){
        char[] data;
        basicRead(data);
        return data;
    }
    /// the current position (for information purposes)
    void parserPos(void delegate(cstring) s){
        long pos=0;
        try {
            if (tangoReader!is null)
                pos=tangoReader.seek(0,tangoReader.Anchor.Current);
            writeOut(s,(cast(Object)reader)); s("@"); writeOut(s,pos);
        } catch (IOException e){
            pos=-1;
            writeOut(s,"reader"); s("@"); writeOut(s,pos);
        }
    }
}

/// formatted write handlers written on the top of a simple sink
class FormattedWriteHandlers(U=char): WriteHandlers{
    void delegate(U[]) writer;
    void delegate() _close;
    this(OutStreamI w){
        static if (is(U==char)){
            this(&w.rawWriteStrC,&w.flush,&w.close);
        } else static if (is(U==wchar)){
            this(&w.rawWriteStrW,&w.flush,&w.close);
        } else static if (is(U==dchar)){
            this(&w.rawWriteStrD,&w.flush,&w.close);
        } else {
            static assert(0,U.stringof~" unsupported");
        }
    }
    this(void delegate(U[]) writer,void delegate() flusher=null,void delegate() _close=null){
        super(flusher);
        this.writer=writer;
        this._close=_close;
        setCoreHandlersFrom_basicWrite();
    }
    /// writes a basic type (basic types are atomic types or strings)
    void basicWrite(T)(ref T t){
        static assert(!(is(T==char) || is(T==wchar) || is(T==dchar)),
            "single character writes not supported, only string writes");
        static if (is(T==U[])){
            writer("\"");
            writer(escape!(char)(t));//escape(t, cast(void delegate(T))&writer.stream.write);
            writer("\"");
        } else static if (is(T==char[])||is(T==wchar[])||is(T==dchar[])){
            auto s=convertToString!(U)(t);
            basicWrite(s);
        } else static if (is(T==ubyte[])||is(T==void[])){
            scope char[] buf=new char[](allocateEncodeSize(cast(ubyte[])t));
            writer("\"");
            writer(cast(U[])encode(cast(ubyte[])t,buf));
            writer("\"");
        } else static if (isBasicCoreType!(T)){
            writeOut(writer,t);
        } else {
            static assert(0,"invalid basic type "~T.stringof);
        }
    }
    
    mixin(coreHandlerSetFromTemplateMixinStr("basicWrite"));

    /// returns if the current protocol is binary or not
    bool binary(){
        return false;
    }
    /// writes a raw sequence of bytes
    void rawWrite(void[] data){
        basicWrite(data); // should encode it in base 64 or something like it
    }
    /// writes a raw string
    void writeStr(T)(T[]data){
        static if (is(T==U)){
            writer(data);
        } else static if (is(T==char)||is(T==wchar)||is(T==dchar)){
            U[] s;
            if (data.length<240){
                U[256] buf;
                s=convertToString!(U)(data,buf);
            } else {
                s=convertToString!(U)(data);
            }
            writer(s);
        } else {
            assert(0,"unsupported type "~T.stringof);
        }
    }
    override void rawWriteStrC(cstring s){
        writeStr(s);
    }
    override void rawWriteStrW(cstringw s){
        writeStr(s);
    }
    override void rawWriteStrD(cstringd s){
        writeStr(s);
    }
    //alias rawWriteStrC rawWriteStr;
    //alias rawWriteStrW rawWriteStr;
    //alias rawWriteStrD rawWriteStr;
    override void rawWriteStr(cstring s){
        writeStr(s);
    }
    override void rawWriteStr(cstringw s){
        writeStr(s);
    }
    override void rawWriteStr(cstringd s){
        writeStr(s);
    }
    CharSink charSink(){
        static if (is(U==char)){
            return writer;
        } else {
            return &this.writeStr!(char);
        }
    }
    BinSink binSink(){
        return &this.rawWrite;
    }
    void close(){
        if (_close !is null){
            _close();
        }
    }
}

/// formatted read handlers build on the top of TextParser
final class FormattedReadHandlers(T):ReadHandlers{
    TextParser!(T)       reader;
    
    this (TextParser!(T) reader)
    {
        this.reader=reader;
        setCoreHandlersFrom_basicRead();
    }
    
    /// returns if the current protocol is binary or not
    bool binary(){
        return false;
    }
    /// reads a basic type
    void basicRead(U)(ref U t){
        static if (is(U==CharReader)){
            outRead(t);
        } else static if (is(U==BinReader)){
            binRead(t);
        } else {
            static assert(isCoreType!(U),"invalid non core type "~U.stringof);
            static if (is(U==ubyte[])||is(U==void[])){
                T[]str;
                reader(str);
                t=decode(str);
            } else static if (is(U==T[])){
                reader(t);
            } else static if (is(U==char[])||is(U==wchar[])||is(U==dchar[])){
                T[] s;
                reader(s);
                t=convertToString!(ElementTypeOfArray!(U))(s,t);
            } else {
                reader(t);
            }
        }
    }
    
    mixin(coreHandlerSetFromTemplateMixinStr("basicRead"));

    /// reads a raw sequence of bytes
    ubyte[] rawRead(size_t amount){
        ubyte[] data;
        basicRead(data);
        return data;
    }
    /// reads a raw string
    T[] rawReadStr(size_t amount){
        return reader.readNCodePoints(amount);
    }
    /// skips the given string
    bool skipStr(T[] str,bool shouldThrow=true){
        return reader.skipString(str,shouldThrow);
    }
}

