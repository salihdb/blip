/*******************************************************************************
        copyright:      Copyright (c) 2009. Fawzi Mohamed
        license:        Apache 2.0
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.container.BulkArray;
import tango.core.Memory;
import blip.BasicModels;
import blip.t.stdc.string;
import blip.t.core.Traits;
import blip.serialization.Serialization;
import blip.serialization.SerializationMixins;
import blip.container.AtomicSLink;
import blip.parallel.smp.WorkManager;
import blip.io.BasicIO;
import blip.container.GrowableArray;
import cstdlib = tango.stdc.stdlib : free, malloc;

/// guard object to deallocate large arrays that contain inner pointers
class Guard{
    ubyte[] data;
    uint refCount;
    this(void[] data){
        this.data=cast(ubyte[])data;
        refCount=1;
    }
    void retain(){
        assert(refCount!=0);
        ++refCount;
    }
    void release(){
        assert(refCount!=0);
        --refCount;
        if (refCount==0){
            //GC.free(data.ptr);
            cstdlib.free(data.ptr);
            data=null;
        }
    }
    this(size_t size,bool scanPtr=false){
        GC.BlkAttr attr;
        if (!scanPtr)
            attr=GC.BlkAttr.NO_SCAN;
        //ubyte* mData2=cast(ubyte*)GC.malloc(size);
        ubyte* mData2=cast(ubyte*)cstdlib.malloc(size);
        if(mData2 is null) throw new Exception("malloc failed");
        data=mData2[0..size];
        refCount=1;
    }
    ~this(){
        //GC.free(data.ptr);
        cstdlib.free(data.ptr);
    }
}

/// 1D array mallocated if large, with parallel looping
struct BulkArray(T){
    enum Flags{
        None=0,
        Dummy,
    }
    static size_t defaultOptimalBlockSize=100*1024/T.sizeof;
    static const BulkArrayCallocSize=100*1024;
    T* ptr, ptrEnd;
    Guard guard;
    Flags flags=Flags.Dummy;
    static const BulkArray dummy={null,null,null,Flags.Dummy};
    alias T dtype;
    
    // ---- Serialization ---
    static ClassMetaInfo metaI;
    static this(){
        synchronized{
            if (metaI is null){
                metaI=ClassMetaInfo.createForType!(BulkArray)
                    ("BulkArray!("~T.stringof~")");
                metaI.kind=TypeKind.CustomK;
            }
        }
    }
    ClassMetaInfo getSerializationMetaInfo(){
        return metaI;
    }
    void serialize(Serializer s){
        T[] dArray=this.data;
        auto ac=s.writeArrayStart(null,dArray.length);
        FieldMetaInfo *elMetaInfoP=null;
        version(PseudoFieldMetaInfo){
            FieldMetaInfo elMetaInfo=FieldMetaInfo("el","",
                getSerializationInfoForType!(T)());
            elMetaInfo.pseudo=true;
            elMetaInfoP=&elMetaInfo;
        }
        foreach (ref d;dArray){
            s.writeArrayEl(ac,delegate void(){ s.field(elMetaInfoP, d); } );
        }
        s.writeArrayEnd(ac);
    }
    void unserialize(Unserializer s){
        T[] dArray;
        FieldMetaInfo elMetaInfo=FieldMetaInfo("el","",
            getSerializationInfoForType!(T)());
        elMetaInfo.pseudo=true;
        auto ac=s.readArrayStart(null);
        dArray.length=cast(size_t)ac.sizeHint();
        size_t pos=0;
        while(s.readArrayEl(ac,
            {
                if (pos==dArray.length){
                    dArray.length=GC.growLength(dArray.length+1,T.sizeof);
                }
                s.field(&elMetaInfo, dArray[pos]);
                ++pos;
            } )) {}
        dArray.length=pos;
        this.ptr=dArray.ptr;
        this.ptrEnd=this.ptr+dArray.length;
        this.guard=new Guard(dArray);
    }
    
    mixin printOut!();
    
    /// data as array
    T[] data(){
        return ((this.ptr is null)?null:(this.ptr[0..(this.ptrEnd-this.ptr)]));
    }
    void data(T[] newData){
        this.ptr=newData.ptr;
        this.ptrEnd=this.ptr+newData.length;
    }
    /// sets data ana guard to the one of the given guard
    void dataOfGuard(Guard g){
        this.guard=g;
        this.ptr=cast(T*)g.data.ptr;
        this.ptrEnd=this.ptr+g.data.length/T.sizeof;
    }
    
    static BulkArray opCall(){
        BulkArray b;
        return b;
    }
    static BulkArray opCall(size_t size,bool scanPtr=false){
        BulkArray res;
        if (size*T.sizeof>BulkArrayCallocSize){
            res.guard=new Guard(size*T.sizeof,(typeid(T).flags & 2)!=0);
            res.ptr=cast(T*)res.guard.data.ptr;
            res.ptrEnd=res.ptr+size;
        } else {
            res.data=new T[size];
        }
        res.flags=Flags.None;
        return res;
    }
    static BulkArray opCall(T[] data,Guard guard=null){
        BulkArray res;
        res.data=data;
        res.guard=guard;
        res.flags=Flags.None;
        return res;
    }
    static BulkArray opCall(T*ptr,T*ptrEnd,Guard guard=null){
        BulkArray res;
        res.ptr=ptr;
        res.ptrEnd=ptrEnd;
        assert(ptrEnd>=ptr,"invalid pointers");
        res.guard=guard;
        res.flags=Flags.None;
        return res;
    }
    /// returns the adress of element i
    T* ptrI(size_t i)
    in{
        if (this.ptr+i>=this.ptrEnd){
            assert(0,collectAppender(delegate void(CharSink sink){
                dumperP(sink)("index of BulkArray out of bounds:")(i)(" for array of size ")(this.ptrEnd-this.ptr);
            }));
        }
    } body {
        return this.ptr+i;
    }
    /// returns element i
    DynamicArrayType!(T) opIndex(size_t i){
        assert(this.ptr+i<this.ptrEnd,"index out of bounds");
        return this.ptr[i];
    }
    /// assign element i
    void opIndexAssign(T val,size_t i){
        assert(this.ptr+i<this.ptrEnd,"index out of bounds ");
        *(this.ptr+i)=val;
    }
    /// returns a slice of the array
    BulkArray opIndex(size_t i,size_t j){
        assert(i<=j,"slicing with i>j"); // allow???
        assert(i>=0&&j<=this.length,"slicing index out of bounds");
        return BulkArray(this.data[i..j],this.guard);
    }
    /// ditto
    BulkArray opSlice(size_t i,size_t j){
        assert(i<=j,"slicing with i>j"); // allow???
        assert(i>=0&&j<=this.length,"slicing index out of bounds");
        return BulkArray(this.data[i..j],this.guard);
    }
    /// sets a slice of the array
    void opIndexAssign(T val,size_t i,size_t j){
        assert(i<=j,"slicing with i>j"); // allow???
        assert(i>=0&&j<=this.length,"slicing index out of bounds");
        BulkArray(this.data[i..j],this.guard)[]=val;
    }
    /// ditto
    void opSliceAssign(T val,size_t i,size_t j){
        assert(i<=j,"slicing with i>j"); // allow???
        assert(i>0&&j<=this.length,"slicing index out of bounds");
        BulkArray(this.data[i..j],this.guard)[]=val;
    }
    /// gets a slice of the array as normal array (this will get invalid when dis array is collected)
    T[] getSlice(size_t i,size_t j){
        assert(i<=j,"slicing with i>j"); // allow???
        assert(i>=0&&j<=this.length,"slicing index out of bounds");
        return this.data[i..j];
    }
    void opIndexAssign(BulkArray val,size_t i,size_t j){
        assert(i<=j,"slicing with i>j"); // allow???
        assert(i>0&&j<=this.length,"slicing index out of bounds");
        BulkArray(this.data[i..j],this.guard)[]=val;
    }
    /// copies an bulk array
    void copyFrom(V)(BulkArray!(V) b){
        if (b.length!=length) throw new Exception("different length",__FILE__,__LINE__);
        static if(is(T==V)){
            memcpy(this.ptr,b.ptr,this.length*T.sizeof);
        } else {
            baBinaryOpStr!(`
            static if(is(typeof((*aPtr0)[]=(*bPtr0)))){
                (*aPtr0)[]=(*bPtr0);
            }else {
                *aPtr0=cast(typeof(*aPtr0))*bPtr0;
            }`,T,V)(*this,b);
        }
    }
    void opSliceAssign(BulkArray b){
        copyFrom!(T)(b);
    }
    /// length of the array
    size_t length(){
        return ptrEnd-ptr;
    }
    /// shallow copy of the array
    BulkArray!(V) dupT(V=T)(){
        auto n=BulkArray!(V)(length);
        static if (is(T==V)){
            memcpy(n.data.ptr,data.ptr,length*T.sizeof);
        } else {
            baBinaryOpStr!(`
            static if(is(typeof((*aPtr0)[]=(*bPtr0)))){
                (*aPtr0)[]=(*bPtr0);
            }else {
                *aPtr0=cast(typeof(*aPtr0))*bPtr0;
            }`,V,T)(n,*this);
        }
        return n;
    }
    /// ditto
    BulkArray dup(){
        return dupT!(T)();
    }
    /// deep copy of the array
    BulkArray deepdup(){
        BulkArray n=BulkArray(length);
        static if (is(typeof(T.init.deepdup))){
            baBinaryOpStr!("*bPtr0=cast(typeof(*bPtr0))aPtr0.deepdup;",T,T)(*this,n);
        } else static if (is(typeof(T.init.dup()))) {
            baBinaryOpStr!("*bPtr0=cast(typeof(*bPtr0))aPtr0.dup;",T,T)(*this,n);
        } else {
            memcpy(n.data.ptr,data.ptr,length*T.sizeof);
        }
        return n;
    }
    // iterator/sequential loop done directly on BulkArray
    bool next(ref T* el){
        if (ptr==ptrEnd) {
            el=null;
            return false;
        }
        el=++ptr;
        return true;
    }
    int opApply(int delegate(ref DynamicArrayType!(T) v) loopBody){
        for (T*aPtr=ptr;aPtr!=ptrEnd;++aPtr){
            int ret=loopBody(*aPtr);
            if (ret) return ret;
        }
        return 0;
    }
    int opApply(int delegate(ref size_t i,ref DynamicArrayType!(T) v) loopBody){
        T*aPtr=ptr;
        assert(ptrEnd>=aPtr,"invalid ptrEnd");
        size_t nEl=ptrEnd-aPtr;
        for (size_t i=0;i!=nEl;++i,++aPtr){
            int ret=loopBody(i,*aPtr);
            if (ret) return ret;
        }
        return 0;
    }
    /// parallel foreach loop structure
    /// could be more aggressive in reusing the slice structs, but the difference should be only in the log_2(n) region
    struct PLoop{
        int res;
        Exception e;
        T* start;
        T* end;
        size_t index;
        Slice1 *freeList1;
        Slice2 *freeList2;
        size_t optimalBlockSize;
        struct Slice1{
            PLoop *context;
            T* start;
            T* end;
            int delegate(ref DynamicArrayType!(T) v) loopBody;
            Slice1 *next;
            void exec(){
                try{
                    if (context.res!=0) return;
                    if(end-start>context.optimalBlockSize*3/2){
                        auto newChunk=popFrom(context.freeList1);
                        if (newChunk is null){
                            newChunk=new Slice1;
                            newChunk.loopBody=loopBody;
                            newChunk.context=context;
                        }
                        auto newChunk2=popFrom(context.freeList1);
                        if (newChunk2 is null){
                            newChunk2=new Slice1;
                            newChunk2.loopBody=loopBody;
                            newChunk2.context=context;
                        }
                        auto mid=(end-start)/2;
                        if (mid>context.optimalBlockSize) // try to have exact multiples of optimalBlockSize (so that one can have a fast path for it)
                            mid=((mid+context.optimalBlockSize-1)/context.optimalBlockSize)*context.optimalBlockSize;
                        newChunk.start=start;
                        start+=mid;
                        newChunk.end=start;
                        newChunk2.start=start;
                        newChunk2.end=end;
                        Task("BulkArrayPLoop0sub",&newChunk.exec).appendOnFinish(&newChunk.giveBack).autorelease.submit();
                        Task("BulkArrayPLoop0sub2",&newChunk2.exec).appendOnFinish(&newChunk2.giveBack).autorelease.submit();
                    } else {
                        for (T*tPtr=start;tPtr!=end;++tPtr){
                            auto res=loopBody(*tPtr);
                            if (res){
                                context.res=res;
                                return;
                            }
                        }
                    }
                } catch (Exception e){
                    context.e=e;
                    context.res=-1;
                }
            }
            void giveBack(){
                this.next=null;
                insertAt(context.freeList1,this);
            }
        }
        struct Slice2{
            PLoop *context;
            T* start;
            T* end;
            int delegate(ref size_t index,ref DynamicArrayType!(T) v) loopBody;
            size_t index;
            Slice2 *next;
            void exec(){
                try{
                    if (context.res!=0) return;
                    if (end-start>context.optimalBlockSize*3/2){
                        auto newChunk=popFrom(context.freeList2);
                        if (newChunk is null){
                            newChunk=new Slice2;
                            newChunk.loopBody=loopBody;
                            newChunk.context=context;
                        }
                        auto newChunk2=popFrom(context.freeList2);
                        if (newChunk2 is null){
                            newChunk2=new Slice2;
                            newChunk2.loopBody=loopBody;
                            newChunk2.context=context;
                        }
                        auto mid=(end-start)/2;
                        if (mid>context.optimalBlockSize) // try to have exact multiples of optimalBlockSize (so that one can have a fast path for it)
                            mid=((mid+context.optimalBlockSize-1)/context.optimalBlockSize)*context.optimalBlockSize;
                        newChunk.start=start;
                        start+=mid;
                        newChunk.end=start;
                        newChunk.index=index;
                        index+=mid;
                        newChunk2.start=start;
                        newChunk2.end=end;
                        newChunk2.index=index;
                        Task("BulkArrayPLoop0sub",&newChunk.exec).appendOnFinish(&newChunk.giveBack).autorelease.submit();
                        Task("BulkArrayPLoop0sub2",&newChunk2.exec).appendOnFinish(&newChunk2.giveBack).autorelease.submit();
                    } else {
                        auto idx=index;
                        for (T*tPtr=start;tPtr!=end;++tPtr){
                            auto res=loopBody(idx,*tPtr);
                            if (res!=0){
                                context.res=res;
                                return;
                            }
                            ++idx;
                        }
                    }
                } catch(Exception e){
                    context.e=e;
                    context.res=-1;
                }
            }
            void giveBack(){
                this.next=null;
                insertAt(context.freeList2,this);
            }
        }
        static PLoop opCall(BulkArray array,size_t optimalBlockSize){
            PLoop it;
            assert(! BulkArrayIsDummy(array), "array cannot be null");
            assert(optimalBlockSize!=0,"optimalBlockSize cannot be 0");
            it.start=array.ptr;
            it.end=array.ptrEnd;
            it.index=0;
            it.optimalBlockSize=optimalBlockSize;
            it.e=null;
            return it;
        }
        int opApply(int delegate(ref DynamicArrayType!(T) v) loopBody){
            if (end-start>optimalBlockSize*2){
                Slice1 newChunk;
                newChunk.loopBody=loopBody;
                newChunk.context=this;
                newChunk.start=start;
                newChunk.end=end;
                Task("BulkArrayPLoop0",&newChunk.exec).autorelease.executeNow();
                if (e!is null){
                    throw new Exception("Exception in BulkArray PLoop",__FILE__,__LINE__,e);
                }
                auto cnk=freeList1;
                while (cnk !is null){
                    auto nextC=cnk.next;
                    cnk.next=null;
                    delete cnk;
                    cnk=nextC;
                }
                freeList1=null;
                return res;
            } else {
                for (T*aPtr=start;aPtr!=end;++aPtr){
                    int ret=loopBody(*aPtr);
                    if (ret!=0) return ret;
                }
            }
            return 0;
        }
        int opApply(int delegate(ref size_t i,ref DynamicArrayType!(T) v) loopBody){
            if (end-start>optimalBlockSize*2){
                Slice2 newChunk;
                newChunk.loopBody=loopBody;
                newChunk.context=this;
                newChunk.start=start;
                newChunk.end=end;
                newChunk.index=index;
                Task("BulkArrayPLoop1",&newChunk.exec).autorelease.executeNow();
                if (e!is null){
                    throw new Exception("Exception in BulkArray PLoop",__FILE__,__LINE__,e);
                }
                auto cnk=freeList2;
                while (cnk !is null){
                    auto nextC=cnk.next;
                    cnk.next=null;
                    delete cnk;
                    cnk=nextC;
                }
                freeList2=null;
                return res;
            } else {
                size_t len=end-start;
                T*aPtr=start;
                for (size_t i=0;i!=len;++i,++aPtr){
                    int ret=loopBody(i,*aPtr);
                    if (ret) return ret;
                }
            }
            return 0;
        }
    }
    /// return what is needed for a sequential foreach loop on the array
    BulkArray sLoop(){
        return *this;
    }
    /// return what is needed for a parallel foreach loop on the array
    PLoop pLoop(size_t optimalBlockSize=defaultOptimalBlockSize){
        return PLoop(*this,optimalBlockSize);
    }
    void opSliceAssign(T val){
        foreach(ref v;pLoop())
            v=val;
    }
    /// implement an FIterator compliant interface on T*
    final class FIteratorP:FIteratorI!(DynamicArrayType!(T)*){
        BulkArray it;
        bool parallel;
        size_t optimalChunkSize;
        this(BulkArray array){
            it=array;
            parallel=false;
            optimalChunkSize=defaultOptimalBlockSize;
        }
        bool next(ref DynamicArrayType!(T)* el){
            return it.next(el);
        }
        int opApply(int delegate(ref DynamicArrayType!(T) v) loopBody){
            if (parallel){
                return it.pLoop(optimalChunkSize).opApply(loopBody);
            } else {
                return it.sLoop().opApply(loopBody);
            }
        }
        int opApply(int delegate(ref size_t i,ref DynamicArrayType!(T) v) loopBody){
            if (parallel){
                return it.pLoop(optimalChunkSize).opApply(loopBody);
            } else {
                return it.sLoop().opApply(loopBody);
            }
        }
        FIteratorP parallelLoop(size_t myOptimalChunkSize){
            optimalChunkSize=myOptimalChunkSize;
            parallel=true;
            return this;
        }
        FIteratorP parallelLoop(){
            parallel=true;
            return this;
        }
    }
}

/// tests if b is a dummy array
static bool BulkArrayIsDummy(T)(BulkArray!(T) b){
    return (b.flags & BulkArray!(T).Flags.Dummy)!=0;
}

void baUnaryOpStr(char[] opStr,T)(ref BulkArray!(T) a){
    for (aPtr0=a.ptr;aPtr0!=ptrEnd;++aPtr0){
        mixin(opStr);
    }
}

void baBinaryOpStr(char[] opStr,T,U)(ref BulkArray!(T) a,ref BulkArray!(U) b){
    assert(a.length==b.length,"binaryOpStr only on equally sized arrays");
    U * bPtr0=b.ptr;
    T* aPtrEnd=a.ptrEnd;
    for (T *aPtr0=a.ptr;aPtr0!=aPtrEnd;++aPtr0,++bPtr0){
        mixin(opStr);
    }
}

void baTertiaryOpStr(char[] opStr,T,U,V)(ref BulkArray!(T) a,ref BulkArray!(U) b,ref BulkArray!(V) c){
    assert(a.length==b.length,"binaryOpStr only on equally sized arrays");
    assert(a.length==c.length,"binaryOpStr only on equally sized arrays");
    U * bPtr0=b.ptr;
    V * cPtr0=b.ptr;
    T* aPtrEnd=a.ptrEnd;
    for (T *aPtr0=a.ptr;aPtr0!=aPtrEnd;++aPtr0,++bPtr0,++cPtr0){
        mixin(opStr);
    }
}

