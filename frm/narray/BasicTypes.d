/*******************************************************************************
    N dimensional dense rectangular arrays
    
    Inspired by muarray by William V. Baxter (III) with hints of 
    numpy, and haskell GSL/Matrix Library, but evolved to something of quite different
    
    - rank must be choosen at compiletime -> smart indexing possible
    - sizes can be choosen at runtime -> no compile time size
      (overhead should be acceptable for all but the smallest arrays)
    - a given array has fixed startIdx, and strides (in D 2.0 these should be invariant)
    - also the rest of the structure should be as "fixed" as possible.
    - at the moment only the underlying array is modified after creation when using
      subviews, but in the future also this might go away.
    - generic efficent looping templates are available.
    - store array not pointer (safer, but might be changed in the future)
    - structure not class (faster, but might be changed)
    Rationale:
    - indexing should be as fast as possible (if one uses multidimensional arrays
      probably indexing is going to be important to him) -> fixed rank, invariant strides
    - close to optimal (performacewise) looping should be easy to perform -> generic looping templates
    - A good compiler should be able to move most of indexing out of a loop -> invariant strides
    - avoid copying as much as possible (lots of operations guaranteed to return a view).
    
    all operation assume that there is *no* overlap between parst that are assigned and those
    that are read (for example assignement of an array to itself has an undefined behaviour)
    
    Possible changes: I might switch to a struct+class to keep a pointer to non gc memory
      (should be a little bit faster)
    
    copyright:      Copyright (c) 2008. Fawzi Mohamed
    license:        BSD style: $(LICENSE)
    version:        Initial release: July 2008
    author:         Fawzi Mohamed
*******************************************************************************/
module frm.narray.BasicTypes;
import tango.stdc.stdlib: calloc,free,realloc;
import tango.core.Array: sort;
import tango.stdc.string: memset,memcpy,memcmp;
import frm.TemplateFu;
import tango.io.Print: Print;
import tango.io.stream.FormatStream: FormatOutput;
import tango.io.Buffer: GrowBuffer;
import tango.math.Math: abs;
import frm.rtest.RTest;

/// flags for fast checking of 
enum ArrayFlags {
    /// C-style contiguous which means that a linear scan of
    /// mData with stride 1 is equivalent to scanning with a loop
    /// in which the last index is the fastest varying
    Contiguous   = 0x1,
    /// Fortran-style contiguous means that a lineat scan of
    /// mData with stride 1 with a (transpose of Contiguous).
    Fortran      = 0x2,
    /// If this flag is set this array frees its data in the destructor.
    ShouldFreeData      = 0x4,
    /// if the array is "compact" and mData scans the whole array
    /// only once (and mData can be directly used to loop on all elements)
    /// Contiguous|Fortran implies Compact
    Compact      = 0x8,
    /// if the array is non small
    Small        = 0x10,
    /// if the array is large
    Large        = 0x20,
    /// if the array can be only read
    ReadOnly     = 0x40,
    /// if the array has size 0
    Zero         = 0x80,
    /// flags that the user can set (the other are automatically calculated)
    ExtFlags = ShouldFreeData | ReadOnly,
    All = Contiguous | Fortran | ShouldFreeData | Compact | Small | Large| ReadOnly| Zero, // useful ??
    None = 0
}

alias int index_type; // switch back to int later

/// describes a range
/// upper bound is not part of the range if positive
/// negative numbers are from the end, and (unlike the positive range)
/// the upper bound is inclusive (i.e. Range(-1,-1) is the last element,
/// but Range(0,0) contains no elements)
/// if the increment is 0, the range is unbounded (with increment 1)
struct Range{
    index_type from,to,inc;
    /// a range from 0 to to (not included)
    static Range opCall(index_type to){
        Range res;
        res.from=0;
        res.to=to;
        res.inc=1;
        return res;
    }
    /// a range from start to end
    static Range opCall(index_type start,index_type end){
        Range res;
        res.from=start;
        res.to=end;
        res.inc=1;
        return res;
    }
    /// a range from start to end with steps inc
    static Range opCall(index_type start,index_type end,index_type inc){
        Range res;
        res.from=start;
        res.to=end;
        res.inc=inc;
        return res;
    }
}

/// returns the reduction of the rank done by the arguments in the tuple
/// allow also static arrays?
template reductionFactor(){
    const int reductionFactor=0;
}
/// ditto
template reductionFactor(T,S...){
    static if (is(T==int) || is(T==long)||is(T==uint)||is(T==ulong))
        const int reductionFactor=1+reductionFactor!(S);
    else static if (is(T==Range))
        const int reductionFactor=reductionFactor!(S);
    else{
        static assert(0,"ERROR: unexpected type <"~T.stringof~"> in reductionFactor, this will fail");
    }
}

/// threshold for manual allocation
const int manualAllocThreshold=200*1024;

/// the template class that represent a rank-dimensional dense rectangular array of type T
template NArray(V=double,int rank=1){
static if (rank<1)
    alias V NArray;
else {
    final class NArray : RandGen
    {
        alias V dtype;
        alias ArrayFlags Flags;

        /// initial index (useful when looping backward)
        const index_type mStartIdx;
        /// strides (can be negative)
        index_type[rank] mStrides;
        /// shape of the array
        index_type[rank] mShape;
        /// the raw data of the array
        V[] mData;
        /// flags to quickly check properties of the array
        uint mFlags = Flags.None;
        /// owner of the data if it is manually managed
        void *mBase = null;
        /// flags
        uint flags() { return mFlags; }
        /// the underlying data slice
        V[] data() { return mData; }
        /// strides of the array
        index_type[] strides() { return mStrides; }
        /// shape of the array
        index_type[] shape() { return mShape; }
        /// position of first element in the data slice (to allow reverse indexing)
        index_type startIdx() { return mStartIdx; }
        /// pointer to the first element of the array (not necessarily the start of the slice)
        V* ptr() { return mData.ptr+mStartIdx; }
        /// calulates the base flags (Contiguos,Fortran,Compact,Small,Large)
        static uint calcBaseFlags(index_type[rank] strides, index_type[rank] shape, index_type startIdx,
            V[] data){
            uint flags=Flags.None;
            // check contiguos & fortran
            bool contiguos,fortran;
            index_type size=-1;
            contiguos=fortran=(startIdx==0);
            if (contiguos){
                static if (rank == 1) {
                    contiguos=fortran=(shape[0]==0 || shape[0] == 1 || 1 == strides[0]);
                    size=shape[0];
                } else {
                    index_type sz=1;
                    for (int i=0;i<rank;i++){
                        if (strides[i]!=sz && shape[i]!=1)
                            fortran=false;
                        sz*=shape[i];
                    }
                    size=sz;
                    sz=1;
                    if (sz==0){
                        contiguos=true;
                        fortran=true;
                    } else {
                        for (int i=rank-1;i>=0;i--){
                            if (strides[i]!=sz && shape[i]!=1)
                                contiguos=false;
                            sz*=shape[i];
                        }
                    }
                }
            }
            if (contiguos)
                flags|=Flags.Contiguous|Flags.Compact;
            if (fortran)
                flags|=Flags.Fortran|Flags.Compact;
            else if (! contiguos) {
                // check compact
                index_type[rank] posStrides=strides;
                index_type posStart=startIdx;
                for (int i=0;i<rank;i++){
                    if (posStrides[i]<0){
                        posStart+=posStrides[i]*(shape[i]-1);
                        posStrides[i]=-posStrides[i];
                    }
                }
                int[rank] sortIdx;
                static if(rank==1){
                    bool compact=(strides[0]==1);
                    size=shape[0];
                } else {
                    static if(rank==2){
                        if (strides[0]<=strides[1]){
                            sortIdx[0]=1;
                            sortIdx[1]=0;
                        } else {
                            sortIdx[0]=1;
                            sortIdx[1]=0;
                        }
                    } else {
                        for (int i=0;i<rank;i++)
                            sortIdx[i]=i;
                        sortIdx.sort((int x,int y){return strides[x]<strides[y];});
                    }
                    index_type sz=1;
                    bool compact=true;
                    for (int i=0;i<rank;i++){
                        if (posStrides[sortIdx[i]]!=sz)
                            compact=false;
                        sz*=shape[sortIdx[i]];
                    }
                    size=sz;
                }
                if (size==0)
                    compact=true;
                if (posStart!=0)
                    compact=false;
                if (compact)
                    flags|=Flags.Compact;
            }
            if (flags & Flags.Compact){
                if (data !is null && data.length!=size){
                    // should this be an error, or should it be accepted ???
                    flags &= ~(Flags.Contiguous|Flags.Fortran|Flags.Compact);
                }
            }
            if (size==0){
                flags|=Flags.Zero;
            }
            if (size< 4*rank && size<20) {
                flags|=Flags.Small;
            }
            if (size>30*rank || size>100) {
                flags|=Flags.Large;
            }
            return flags;
        }
        
        /// this is the default constructor, it is quite lowlevel and you are
        /// supposed to create arrays with higher level functions (empty,zeros,ones,...)
        /// the data will be freed if flags & Flags.ShouldFreeData, the other flags are ignored
        this(index_type[rank] strides, index_type[rank] shape, index_type startIdx,
            V[] data, uint flags, void *mBase=null)
        in {
            index_type minIndex=startIdx,maxIndex=startIdx,size=1;
            for (int i=0;i<rank;i++){
                assert(shape[i]>=0,"shape has to be positive in NArray construction");
                size*=shape[i];
                if (strides[i]<0){
                    minIndex+=strides[i]*(shape[i]-1);
                } else {
                    maxIndex+=strides[i]*(shape[i]-1);
                }
            }
            if (size!=0 && data !is null){
                assert(minIndex>=0,"minimum real internal index negative in NArray construction");
                assert(maxIndex<data.length,"data array too small in NArray construction");
            }
        }
        body {
            this.mShape[] = shape;
            this.mStrides[] = strides;
            this.mStartIdx = startIdx;
            this.mData=data;
            this.mFlags=calcBaseFlags(strides,shape,startIdx,data)|(flags & Flags.ExtFlags);
            this.mBase=mBase;
        }
        
        ~this(){
            if (flags&Flags.ShouldFreeData){
                free(mData.ptr);
            }
        }
        
        /// another way to construct an object (also low level, see empty, zeros and ones for better ways)
        static NArray opCall(index_type[rank] strides, index_type[rank] shape, index_type startIdx,
            V[] data, uint flags, void* mBase=null){
            return new NArray(strides,shape,startIdx,data,flags,mBase);
        }
                    
        /// returns an empty (uninitialized) array of the requested shape
        static NArray empty(index_type[rank] shape,bool fortran=false){
            index_type size=1;
            foreach (sz;shape)
                size*=sz;
            uint flags=ArrayFlags.None;
            V[] mData;
            if (size*V.sizeof>manualAllocThreshold) {
                V* mData2=cast(V*)calloc(size,V.sizeof);
                if(mData2 is null) throw new Exception("calloc failed");
                mData=mData2[0..size];
                flags=ArrayFlags.ShouldFreeData;
            } else {
                mData=new V[size];
            }
            index_type[rank] strides;
            if (!fortran){
                index_type sz=1;
                foreach_reverse(i, d; shape) {
                    strides[i] = sz;
                    sz *= d;
                }
            } else {
                index_type sz=1;
                foreach(i, d; shape) {
                    strides[i] = sz;
                    sz *= d;
                }
            }
            return NArray(strides,shape,cast(index_type)0,mData,flags);
        }
        /// returns an array initialized to 0 of the requested shape
        static NArray zeros(index_type[rank] shape, bool fortran=false){
            NArray res=empty(shape,fortran);
            static if(isAtomicType!(V)){
                memset(res.mData.ptr,0,res.mData.length*V.sizeof);
            } else {
                res.mData[]=cast(V)0;
            }
            return res;
        }
        /// returns an array initialized to 1 of the requested shape
        static NArray ones(index_type[rank] shape, bool fortran=false){
            NArray res=empty(shape,fortran);
            res.mData[]=cast(V)1;
            return res;
        }
        
        /+ -------------- indexing, slicing subviews ------------- +/
        /// indexing
        /// if array has rank 3: array[1,4,3] -> scalar, array[2] -> 2D array,
        /// array[3,Range(6,7)] -> 2D array, ...
        /// if a sub array is returned (and not a scalar) then it is *always* a subview
        /// indexing never copies data
        NArray!(V,rank-reductionFactor!(S))opIndex(S...)(S idx_tup)
        in {
            static assert(rank>=nArgs!(S),"too many argumens in indexing operation");
            static if(rank==reductionFactor!(S)){
                foreach (i,v;idx_tup){
                    assert(0<=v && v<mShape[i],"index "~ctfe_i2a(i)~" out of bounds");
                }
            } else {
                foreach(i,TT;S){
                    static if(is(TT==int)||is(TT==long)||is(TT==uint)||is(TT==ulong)){
                        assert(0<=idx_tup[i] && idx_tup[i]<mShape[i],"index "~ctfe_i2a(i)~" out of bounds");
                    } else static if(is(TT==Range)){
                        {
                            index_type from=idx_tup[i].from,to=idx_tup[i].to,step=idx_tup[i].inc;
                            if (from<0) from+=mShape[i];
                            if (to<0) to+=mShape[i]+1;
                            if (from<to && step>=0 || from>to && step<0){
                                assert(0<=from && from<mShape[i],
                                    "invalid lower range for dimension "~ctfe_i2a(i));
                                if (step==0)
                                    to=mShape[i];
                                else if (step>0)
                                    to=from+(to-from+step-1)/step;
                                else
                                    to=from-(to-from+step+1)/step;
                                assert(to>=0 && to<=mShape[i],
                                    "invalid upper range for dimension "~ctfe_i2a(i));
                            }
                        }
                    } else static assert(0,"unexpected type <"~TT.stringof~"> in opIndex");
                }
            }
        }
        body {
            static assert(rank>=nArgs!(S),"too many arguments in indexing operation");
            static if (rank==reductionFactor!(S)){
                index_type idx=mStartIdx;
                foreach(i,TT;S){
                    static assert(is(TT==int)||is(TT==long)||is(TT==uint)||is(TT==ulong),"unexpected type <"~TT.stringof~"> in full indexing");
                    idx+=idx_tup[i]*mStrides[i];
                }
                return mData[idx];
            } else {
                const int rank2=rank-reductionFactor!(S);
                index_type[rank2] newstrides,newshape;
                index_type newStartIdx;
                int idim=0;
                foreach(i,TT;S){
                    static if (is(TT==int)||is(TT==long)||is(TT==uint)||is(TT==ulong)){
                        newStartIdx+=idx_tup[i]*mStrides[i];
                    } else static if (is(TT==Range)){
                        {
                            index_type from=idx_tup[i].from,to=idx_tup[i].to,step=idx_tup[i].inc;
                            if (from<0) from+=mShape[i];
                            if (to<0) to+=mShape[i]+1;
                            index_type n;
                            if (step>0) {
                                n=(to-from+step-1)/step;
                            } else if (step==0) {
                                n=mShape[i]-from;
                                step=1;
                            } else{
                                n=(to-from+step+1)/step;
                            }
                            if (n>0) {
                                newshape[idim]=n;
                                newStartIdx+=from*mStrides[i];
                                newstrides[idim]=step*mStrides[i];
                            } else {
                                newshape[idim]=0; // set everything to 0?
                                newstrides[idim]=step*mStrides[i];
                            }
                            idim+=1;
                        }
                    } else static assert(0,"unexpected type in opIndex");
                }
                for (int i=rank2-idim;i>0;--i){
                    newstrides[rank2-i]=mStrides[rank-i];
                    newshape[rank2-i]=mShape[rank-i];
                }
                // calc min index & max index (optimal subslice)
                index_type minIndex=newStartIdx,maxIndex=newStartIdx,size=1;
                for (int i=0;i<rank2;i++){
                    size*=newshape[i];
                    if (newstrides[i]<0){
                        minIndex+=newstrides[i]*(newshape[i]-1);
                    } else {
                        maxIndex+=newstrides[i]*(newshape[i]-1);                            
                    }
                }
                V[] newdata;
                if (size>0) {
                    newdata=mData[minIndex..maxIndex+1];
                } else {
                    newdata=null;
                }
                NArray!(V,rank2) res=NArray!(V,rank2)(newstrides,newshape,newStartIdx-minIndex,newdata,
                    newFlags,newBase);
                return res;
            }
        }
        
        /// index assignement
        /// if array has rank 3 array[1,2,3]=4.0, array[1]=2Darray, array[1,Range(3,7)]=2Darray
        NArray!(V,rank-reductionFactor!(S)) opIndexAssign(U,S...)(U val,
            S idx_tup)
        in{
            assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned");
            static assert(is(U==NArray!(V,rank-reductionFactor!(S)))||is(U==V),"invalid value type <"~U.stringof~"> in opIndexAssign");
            static assert(rank>=nArgs!(S),"too many argumens in indexing operation");
            static if (rank==reductionFactor!(S)){
                foreach(i,TT;S){
                    static if(is(TT==int)||is(TT==long)||is(TT==uint)||is(TT==ulong)){
                        assert(0<=idx_tup[i] && idx_tup[i]<mShape[i],"index "~ctfe_i2a(i)~" out of bounds");                        
                    } else static assert(0,"unexpected type <"~TT.stringof~"> in opIndexAssign");
                } // else check done in opIndex...
            }
        }
        body{
            static assert(rank>=nArgs!(S),"too many arguments in indexing operation");
            static if (rank==reductionFactor!(S)){
                index_type idx=mStartIdx;
                foreach(i,TT;S){
                    static assert(is(TT==int)||is(TT==long)||is(TT==uint)||is(TT==ulong),"unexpected type <"~TT.stringof~"> in full indexing");
                    idx+=idx_tup[i]*mStrides[i];
                }
                data[idx]=val;
                return val;
            } else {
                auto subArr=opIndex(idx_tup);
                subArr[]=val;
            }
        }
                
        /// static array indexing (separted from opIndex as potentially less efficient)
        NArray!(V,rank-cast(int)staticArraySize!(S))arrayIndex(S)(S index){
            static assert(is(S:int[])||is(S:long[])||is(S:uint[])||is(S:ulong[]),"only arrays of indexes supported");
            static assert(isStaticArray!(S),"arrayIndex needs *static* arrays as input");
            const char[] loopBody=("auto res=opIndex("~arrayToSeq("index",cast(int)staticArraySize!(S))~");");
            mixin(loopBody);
            return res;
        }

        /// static array indexAssign (separted from opIndexAssign as potentially less efficient)
        NArray!(V,rank-cast(int)staticArraySize!(S))arrayIndexAssign(S,U)(U val,S index){
            static assert(is(S:int[])||is(S:long[])||is(S:uint[])||is(S:ulong[]),"only arrays of indexes supported");
            static assert(isStaticArray!(S),"arrayIndex needs *static* arrays as input");
            mixin("NArray!(V,rank-cast(int)staticArraySize!(S)) res=opIndexAssign(val,"~arrayToSeq("index",staticArraySize!(S))~");");
            return res;
        }
        
        /// copies the array, undefined behaviour if there is overlap
        NArray opSliceAssign(S,int rank2)(NArray!(S,rank2) val)
        in { 
            static assert(rank2==rank,"assign operation should have same rank "~ctfe_i2a(rank)~"vs"~ctfe_i2a(rank2));
            assert(mShape==val.mShape,"assign arrays need to have the same shape");
            assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned");
        }
        body {
            static if (is(T==S)){
                if (mFlags & val.mFlags & (Flags.Fortran | Flags.Contiguous)){
                    memcpy(mData.ptr,val.mData.ptr,mData.length*T.sizeof);
                }
            }
            binaryOpStr!("*aPtr0=cast("~V.stringof~")*bPtr0;",rank,V,S)(this,val);
            return this;
        }
        
        /// assign a scalar to the whole array with array[]=value;
        NArray opSliceAssign()(V val)
        in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
        body{
            mixin unaryOpStr!("*aPtr0=val",rank,V);
            unaryOpStr(this);
            return this;
        }
                
        /++
        + this sub iterator trades a little speed for more safety when used step by step.
        + For example instead of updating only the pointer or the starting point it updates the slice.
        + This is safe also to updates of the base array mData in the sense that each next/get
        + is done using the base array mData, not a local copy.
        + After an update in the base array a call to value is wrong, but next or get will set it correctly.
        + Dropping this (unlikely to be used) thing would speed up a little some things.
        +/
        static if (rank==1){
            struct SubView{
                NArray baseArray;
                index_type stride; // invariant
                index_type iPos, iDim, iIdx;
                static SubView opCall(NArray a, int axis=0)
                in { assert(axis==0); }
                body {
                    SubView res;
                    res.baseArray=a;
                    res.iPos=0;
                    res.stride=a.strides[axis];
                    res.iDim=a.shape[axis];
                    res.iIdx=a.startIdx;
                    return res;
                }
                bool next(){
                    iPos++;
                    if (iPos<iDim){
                        iIdx+=stride;
                        return false;
                    } else {
                        iPos=iDim;
                        return false;
                    }
                }
                V value()
                in { assert(iPos<iDim); }
                body {
                    return baseArray.mData[iIdx];
                }
                void value(V val)
                in { assert(iPos<iDim); }
                body {
                    baseArray.mData[iIdx]=val;
                }
                V get(index_type index)
                in { assert(0<=index && index<iDim,"invalid index in SubView.get"); }
                body {
                    iIdx+=(index-iIdx)*stride;
                    iPos=index;
                    return baseArray.mData[iIdx];
                }
                int opApply( int delegate(ref V) loop_body ) {
                    if (iPos<iDim){
                        V* pos= &(baseArray.mData[iIdx]);
                        for (index_type i=iPos;i!=iDim;++i){
                            if (auto r=loop_body(*pos)) return r;
                            pos+=stride;
                        }
                    }
                    return 0;
                }
                int opApply( int delegate(ref index_type,ref V) loop_body ) {
                    if (iPos<iDim){
                        V*pos= &(baseArray.mData[iIdx]);
                        for (index_type i=iPos;i!=iDim;i++){
                            if (auto r=loop_body(i,*pos)) return r;
                            pos+=stride;
                        }
                    }
                    return 0;
                }
            }
        } else {
            struct SubView{
                NArray baseArray;
                NArray!(V,rank-1) view;
                index_type[2] subSlice;
                index_type iPos, iDim, stride;
                static SubView opCall(NArray a, int axis=0)
                in { assert(0<=axis && axis<rank); }
                body {
                    index_type[rank-1] shape,strides;
                    int ii=0;
                    for(int i=0;i<rank;i++){
                        if (i!=axis){
                            shape[ii]=a.shape[i];
                            strides[ii]=a.strides[i];
                            ii++;
                        }
                    }
                    index_type startIdx;
                    if (a.strides[axis]>=0)
                        startIdx=a.startIdx;
                    else
                        startIdx=a.startIdx-(a.shape[axis]-1)*a.strides[axis];
                    index_type [2]subSlice=a.startIdx;
                    subSlice[1]+=1;
                    for (int i=0;i<rank-1;i++) {
                        if (shape[i]<1){
                            subSlice[1]=subSlice[0];
                            break;
                        }
                        if (strides[i]>=0)
                            subSlice[1]+=(shape[i]-1)*strides[i];
                        else
                            subSlice[0]+=(shape[i]-1)*strides[i];
                    }
                    SubView res;
                    res.baseArray=a;
                    res.subSlice[]=subSlice;
                    res.stride=a.strides[axis];
                    res.iPos=0;
                    res.iDim=a.shape[axis];
                    res.view=NArray!(V,rank-1)(strides,shape,startIdx-subSlice[0],
                        a.mData[subSlice[0]..subSlice[1]],
                        a.newFlags,a.newBase);
                    return res;
                }
                bool next(){
                    iPos++;
                    if (iPos<iDim){
                        subSlice[0]+=stride;
                        subSlice[1]+=stride;
                        view.mData=baseArray.mData[subSlice[0]..subSlice[1]];
                        return true;
                    } else {
                        iPos=iDim;
                        return false;
                    }
                }
                NArray!(V,rank-1) value(){
                    return view;
                }
                void value(NArray!(V,rank-1) val){

                }
                NArray!(V,rank-1) get(index_type index)
                in { assert(0<=index && index<iDim,"invalid index in SubView.get"); }
                body {
                    subSlice[0]+=(index-iPos)*stride;
                    subSlice[1]+=(index-iPos)*stride;
                    iPos=index;
                    view.mData=baseArray.mData[subSlice[0]..subSlice[1]];
                    return view;
                }
                int opApply( int delegate(ref NArray!(V,rank-1)) loop_body ) {
                    for (index_type i=iPos;i<iDim-1;i++){
                        view.mData=baseArray.mData[subSlice[0]..subSlice[1]];
                        if (auto r=loop_body(view)) return r;
                        subSlice[0]+=stride;
                        subSlice[1]+=stride;
                    }
                    return 0;
                }
                int opApply( int delegate(ref index_type,ref NArray!(V,rank-1)) loop_body ) {
                    for (index_type i=iPos;i<iDim;i++){
                        view.mData=baseArray.mData[subSlice[0]..subSlice[1]];
                        if (auto r=loop_body(i,view)) return r;
                        subSlice[0]+=stride;
                        subSlice[1]+=stride;
                    }
                    return 0;
                }
                Print!(char)desc(Print!(char)s){
                    if (this is null){
                        return s("<SubView *null*>").newline;
                    }
                    s("<SubView!(")(V.stringof)(",")(rank)(")").newline;
                    s("baseArray:");
                    baseArray.desc(s)(",").newline;
                    view.desc(s("view:"))(",").newline;
                    s("subSlice:")(subSlice)(",").newline;
                    s("iPos:")(iPos)(", ")("iDim:")(iDim)(", ")("stride :")(stride).newline;
                    s(">").newline;
                    return s;
                }
            }
        }
                
        /++ Iterates over the values of the array according to the current strides. 
         +  Usage is:  for(; !iter.end; iter.next) { ... } or (better and faster)
         +  foreach(v;iter) foreach(i,v;iter)
         +/
        struct FlatIterator{
            V* p;
            NArray baseArray;
            index_type [rank] left;
            index_type [rank] adds;
            static FlatIterator opCall(ref NArray baseArray){
                FlatIterator res;
                res.baseArray=baseArray;
                for (int i=0;i<rank;++i)
                    res.left[rank-1-i]=baseArray.mShape[i]-1;
                res.p=baseArray.mData.ptr+baseArray.mStartIdx;
                foreach (s; baseArray.shape) {
                    if (s==0) {
                        res.left[]=0;
                        res.p=null;
                    }
                }
                res.adds[0]=baseArray.mStrides[rank-1];
                for(int i=1;i<rank;i++){
                    res.adds[i]=baseArray.mStrides[rank-1-i]-baseArray.mStrides[rank-i]*(baseArray.shape[rank-i]-1);
                }
                return res;
            }
            /// Advance to the next item.  Return false if there is no next item.
            bool next(){
                if (left[0]!=0){
                    left[0]-=1;
                    p+=adds[0];
                    return true;
                } else {
                    static if (rank==1){
                        p=null;
                        return false;
                    } else static if (rank==2){
                        if (left[1]!=0){
                            left[0]=baseArray.mShape[rank-1]-1;
                            left[1]-=1;
                            p+=adds[1];
                            return true;
                        } else {
                            p=null;
                            return false;
                        }
                    } else {
                        if (!p) return false; // remove?
                        left[0]=baseArray.mShape[rank-1]-1;
                        for (int i=1;i<rank;i++){
                            if (left[i]!=0){
                                left[i]-=1;
                                p+=adds[i];
                                return true;
                            } else{
                                left[i]=baseArray.mShape[rank-1-i]-1;
                            }
                        }
                        p=null;
                        return false;
                    }
                }
            }
            /// Advance to the next item.  Return false if there is no next item.
            bool opAddAssign(int i) {
                assert(i==1, "+=1, or ++ are the only allowed increments");
                return next();
            }
            /// Assign a value to the element the iterator points at using 
            /// The syntax  iter[] = value.
            /// Equivalent to  *iter.ptr = value
            /// This is an error if the iter.end() is true.
            void opSliceAssign(V v) { *p = v; }
            /// Advance to the next item.  Return false if there is no next item.
            bool opPostInc() {  return next(); }
            /// Return true if at the end, false otherwise.
            bool end() { return p is null; }
            /// Return the value at the current location of the iterator
            V value() { return *p; }
            /// Sets the value at the current location of the iterator
            void value(V val) { *p=val; }
            /// Return a pointer to the value at the current location of the iterator
            V* ptr() { return p; }
            /// Return the array over which this iterator is iterating
            NArray array() { return baseArray; }

            int opApply( int delegate(ref V) loop_body ) 
            {
                if (p is null) return 0;
                if (left!=baseArray.mShape){
                    for(;!end(); next()) {
                        int ret = loop_body(*p);
                        if (ret) return ret;
                    }
                } else {
                    const char[] loopBody=`
                    int ret=loop_body(*baseArrayPtr0);
                    if (ret) return ret;
                    `;
                    mixin(sLoopPtr(rank,["baseArray"],[],loopBody,"i"));
                }
                return 0;
            }
            int opApply( int delegate(ref index_type,ref V) loop_body ) 
            {
                if (p is null) return 0;
                if (left==baseArray.mShape) {
                    for(index_type i=0; !end(); next(),i++) {
                        int ret = loop_body(i,*p);
                        if (ret) return ret;
                    }
                } else {
                    const char[] loopBody=`
                    int ret=loop_body(iPos,*baseArrayPtr0);
                    if (ret) return ret;
                    ++iPos;
                    `;
                    index_type iPos=0;
                    mixin(sLoopPtr(rank,["baseArray"],[],loopBody,"i"));
                }
                return 0;
            }
            Print!(char)desc(Print!(char)s){
                if (this is null){
                    return s("<FlatIterator *null*>").newline;
                }
                s("<FlatIterator rank:")(rank)(", p:")(p)(",").newline;
                s("left:")(left)(",").newline;
                s("adds:")(adds).newline;
                baseArray.desc(s("baseArray:"))(",").newline;
                s(">").newline;
                return s;
            }
        }
        
        struct SFlatLoop{
            NArray a;
            static SFlatLoop opCall(NArray a){
                SFlatLoop res;
                res.a=a;
                return res;
            }
            int opApply( int delegate(inout V) loop_body ) 
            {
                const char[] loopBody=`
                int ret=loop_body(*aPtr0);
                if (ret) return ret;
                `;
                mixin(sLoopPtr(rank,["a"],[],loopBody,"i"));
                return 0;
            }
            int opApply( int delegate(ref index_type,ref V) loop_body ) 
            {
                const char[] loopBody=`
                int ret=loop_body(iPos,*aPtr0);
                if (ret) return ret;
                ++iPos;
                `;
                index_type iPos=0;
                mixin(sLoopPtr(rank,["a"],[],loopBody,"i"));
                return 0;
            }
            static if (rank>1){
                mixin(opApplyIdxAll(rank,"a",true));
            }
        }

        struct PFlatLoop{
            NArray a;
            static PFlatLoop opCall(NArray a){
                PFlatLoop res;
                res.a=a;
                return res;
            }
            int opApply( int delegate(ref V) loop_body ) 
            {
                const char[] loopBody=`
                int ret=loop_body(*aPtr0);
                if (ret) return ret;
                `;
                mixin(pLoopPtr(rank,["a"],[],loopBody,"i"));
                return 0;
            }
            int opApply( int delegate(ref index_type,ref V) loop_body ) 
            {
                const char[] loopBody=`
                int ret=loop_body(iPos,*aPtr0);
                if (ret) return ret;
                ++iPos;
                `;
                index_type iPos=0;
                // this should be changed if pLoopPtr becomes really parallel
                mixin(sLoopPtr(rank,["a"],[],loopBody,"i"));
                return 0;
            }
            static if (rank>1){
                mixin(opApplyIdxAll(rank,"a",false));
            }
        }
        
        static if(rank==1){
            /// loops on the 0 axis
            int opApply( int delegate(ref V) loop_body ) {
                return SubView(this).opApply(loop_body);
            }
            /// loops on the 0 axis
            int opApply( int delegate(ref index_type,ref V) loop_body ) {
                return SubView(this).opApply(loop_body);
            }
        } else {
            /// loops on the 0 axis
            int opApply( int delegate(ref NArray!(V,rank-1)) loop_body ) {
                return SubView(this).opApply(loop_body);
            }
            /// loops on the 0 axis
            int opApply( int delegate(ref index_type,ref NArray!(V,rank-1)) loop_body ) {
                return SubView(this).opApply(loop_body);
            }
        }

        /// returns a subview along the given axis
        SubView subView(int axis=0){
            return SubView(this,axis);
        }

        /// returns a flat iterator
        FlatIterator flatIter(){
            return FlatIterator(this);
        }
        
        /// returns a proxy for sequential flat foreach
        SFlatLoop sFlat(){
            return SFlatLoop(this);
        }

        /// returns a proxy for parallel flat foreach
        PFlatLoop pFlat(){
            return PFlatLoop(this);
        }
        
        /+ --------------------------------------------------- +/
        
        /// Return a deep copy of the array
        /// fortran ordering in the copy can be requested.
        NArray dup(bool fortran=false)
        {
            void cpVal(V a,out V b){
                b=a;
            }
            NArray res=empty(this.mShape,fortran);
            if ( flags & res.flags & (Flags.Fortran | Flags.Contiguous) ) 
            {
                memcpy(res.mData.ptr, mData.ptr, V.sizeof * mData.length);
            }
            else
            {
                binaryOpStr!("*aPtr0=*bPtr0;",rank,V,V)(res,this);
            }
            return res;
        }
        
        /// Returns a copy of the given type (if the type is the same return itself)
        NArray!(S,rank)asType(S)(){
            static if(is(S==V)){
                return this;
            } else {
                auto res=NArray!(S,rank).empty(mShape);
                binaryOpStr!("*aPtr0=cast("~S.stringof~")*bPtr0;",rank,S,V)(res,this);
                return res;
            }
        }
        

        /+ --------------------- math ops ------------------- +/

        // should the cast be removed from array opXxxAssign, and move out of the static if?
        
        static if (is(typeof(-V.init))) {
            /// Return a negated version of the array
            NArray opNeg() {
                NArray res=empty(mShape);
                binaryOpStr!("*bPtr0=-(*aPtr0);",rank,V,V)(this,res);
                return res;
            }
        }

        static if (is(typeof(+V.init))) {
            /// Allowed as long as the underlying type has op pos
            /// But it always makes a full value copy regardless of whether the underlying unary+ 
            /// operator is a no-op.
            NArray opPos() {
                NArray res=empty(mShape);
                binaryOpStr!("*bPtr0= +(*aPtr0);",rank,V,V)(this,res);
                return res;
            }
        }

        /// Add this array and another one and return a new array.
        NArray!(typeof(V.init+S.init),rank) opAdd(S)(NArray!(S,rank) o) { 
            NArray!(typeof(V.init+S.init),rank) res=NArray!(typeof(V.init+S.init),rank).empty(mShape);
            ternaryOpStr!("*cPtr0=(*aPtr0)+(*bPtr0);",rank,V,S,typeof(V.init+S.init))(this,o,res);
            return res;
        }
        static if (is(typeof(V.init+V.init))) {
            /// Add a scalar to this array and return a new array with the result.
            NArray!(typeof(V.init+V.init),rank) opAdd()(V o) { 
                NArray!(typeof(V.init+V.init),rank) res=NArray!(typeof(V.init+V.init),rank).empty(mShape);
                mixin binaryOpStr!("*bPtr0 = (*aPtr0) * o;",rank,V,V);
                binaryOpStr(this,res);
                return res;
            }
        }
        static if (is(typeof(V.init+V.init)==V)) {
            /// Add another array onto this one in place.
            NArray opAddAssign(S)(NArray!(S,rank) o)
            in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                binaryOpStr!("*aPtr0 += cast("~V.stringof~")*bPtr0;",rank,V,S)(this,o);
                return this;
            }
            /// Add a scalar to this array in place.
            NArray opAddAssign()(V o)
            in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                mixin unaryOpStr!("*aPtr0+=o;",rank,V);
                unaryOpStr(this);
                return this;
            }            
        }

        /// Subtract this array and another one and return a new array.
        NArray!(typeof(V.init-S.init),rank) opSub(S)(NArray!(S,rank) o) { 
            NArray!(typeof(V.init-S.init),rank) res=NArray!(typeof(V.init-S.init),rank).empty(mShape);
            ternaryOpStr!("*cPtr0=(*aPtr0)-(*bPtr0);",rank,V,S,typeof(V.init-S.init))(this,o,res);
            return res;
        }
        static if (is(typeof(V.init-V.init))) {
            /// Subtract a scalar from this array and return a new array with the result.
            final NArray opSub()(V o) { 
                NArray res=empty(mShape);
                mixin binaryOpStr!("*bPtr0=(*aPtr0)-o;",rank,V,V);
                binaryOpStr(this,res);
                return res;
            }
        }
        static if (is(typeof(V.init-V.init)==V)) {
            /// Subtract another array from this one in place.
            NArray opSubAssign(S)(NArray!(S,rank) o)
            in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                binaryOpStr!("*aPtr0 -= cast("~V.stringof~")*bPtr0;",rank,V,V)(this,o);
                return this;
            }
            /// Subtract a scalar from this array in place.
            NArray opSubAssign()(V o)
            in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                mixin unaryOpStr!("*aPtr0-=o;",rank,V);
                unaryOpStr(this);
                return this;
            }
        }

        /// Element-wise multiply this array and another one and return a new array.
        /// For matrix multiply, use the non-member dot(a,b) function.
        NArray!(typeof(V.init*S.init),rank) opMul(S)(NArray!(S,rank) o) { 
            NArray res=NArray!(typeof(V.init*S.init),rank).empty(mShape);
            ternaryOpStr!("*cPtr0=(*aPtr0)*(*bPtr0);",rank,V,S,typeof(V.init*S.init))(this,o,res);
            return res;
        }
        static if (is(typeof(V.init*V.init))) {
            /// Multiplies this array by a scalar and returns a new array.
            final NArray!(typeof(V.init*V.init),rank) opMul()(V o) { 
                NArray!(typeof(V.init*V.init),rank) res=NArray!(typeof(V.init*V.init),rank).empty(mShape);
                mixin binaryOpStr!("*bPtr0=(*aPtr0)*o;",rank,V,typeof(V.init*V.init));
                binaryOpStr(this,res);
                return res;
            }
        }
        
        static if (is(typeof(V.init*V.init)==V)) {
            /// Element-wise multiply this array by another in place.
            /// For matrix multiply, use the non-member dot(a,b) function.
            NArray opMulAssign(S)(NArray!(S,rank) o)
            in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                binaryOpStr!("*aPtr0 *= cast("~V.stringof~")*bPtr0;",rank,V,typeof(V.init*V.init))(this,o);
                return this;
            }
            /// scales the current array.
            NArray opMulAssign()(V o)
            in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                mixin unaryOpStr!("*aPtr0 *= o;",rank,V);
                unaryOpStr(this);
                return this;
            }
        }

        /// Element-wise divide this array by another one and return a new array.
        /// To solve linear equations like A * x = b for x, use the nonmember linsolve
        /// function.
        NArray!(typeof(V.init/S.init),rank) opDiv(S)(NArray!(S,rank) o) { 
            NArray!(typeof(V.init/S.init),rank) res=NArray!(typeof(V.init/S.init),rank).empty(mShape);
            ternaryOpStr!("*cPtr0=(*aPtr0)/(*bPtr0);",rank,V,S,typeof(V.init/S.init))(this,o,res);
            return res;
        }
        static if (is(typeof(V.init/V.init))) {
            /// divides this array by a scalar and returns a new array with the result.
            NArray!(typeof(V.init/V.init),rank) opDiv()(V o) { 
                NArray!(typeof(V.init/V.init),rank) res=NArray!(typeof(V.init/V.init),rank).empty(mShape);
                mixin binaryOpStr!("*bPtr0=(*aPtr0)/o;",rank,V,typeof(V.init/V.init));
                binaryOpStr(this,res);
                return res;
            }
        }
        static if (is(typeof(V.init/V.init)==V)) {
            /// Element-wise divide this array by another in place.
            /// To solve linear equations like A * x = b for x, use the nonmember linsolve
            /// function.
            NArray opDivAssign(S)(NArray!(S,rank) o)
            in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                binaryOpStr!("*aPtr0 /= cast("~V.stringof~")*bPtr0;",rank,V,S)(this,o);
                return this;
            }
            /// divides in place this array by a scalar.
            NArray opDivAssign()(V o)
            in { assert(!(mFlags&Flags.ReadOnly),"ReadOnly array cannot be assigned"); }
            body { 
                mixin unaryOpStr!("*aPtr0 /= o;",rank,V);
                unaryOpStr(this);
                return this;
            }
        }
        
        /+ --------------------------------------------------- +/
        
        /// Compare with another array for value equality
        bool opEquals(NArray o) { 
            if (mShape!=o.mShape) return false;
            if (flags & o.mFlags & Flags.Compact){
                return !memcmp(mData.ptr,o.mData.ptr,mData.length*V.sizeof);
            }
            mixin(sLoopPtr(rank,["","o"],[],"if (*Ptr0 != *oPtr0) return false;","i"));
            return true; 
        }

        /// Compare for ordering not allowed (do it lexicographically on rank, shape, and then 
        /// elements using the standard C ordering??)
        int opCmp(NArray o) { 
            assert(0, "Comparison of arrays not allowed");
            return 0; 
        }

        char[] toString(){
            GrowBuffer buf=new GrowBuffer(256);
            Print!(char) stringIO=new FormatOutput(buf);
            printData(stringIO);
            stringIO.flush();
            char[] res=cast(char[])buf.slice();
            return res;
        }
        
        Print!(char) printData(Print!(char)s,char[] formatEl="{,10}", index_type elPerLine=10,
            char[] indent=""){
            s("[");
            static if(rank==1) {
                index_type lastI=mShape[0]-1;
                foreach(index_type i,V v;SubView(this)){
                    s.format(formatEl,v);
                    if (i!=lastI){
                        s(",");
                        if (i%elPerLine==elPerLine-1){
                            s("\n")(indent)(" ");
                        }
                    }
                }
            } else {
                index_type lastI=mShape[0]-1;
                foreach(i,v;this){
                    v.printData(s,formatEl,elPerLine,indent~" ");
                    if (i!=lastI){
                        s(",\n")(indent)(" ");
                    }
                }
            }
            s("]");
            return s;
        }
            
        /// description of the NArray wrapper, not of the contents, for debugging purposes...
        Print!(char) desc(Print!(char)s){
            if (this is null){
                return s("<NArray *null*>").newline;
            }
            s("<NArray @:")(&this)(",").newline;
            s("  startIdx:")(mStartIdx)(",").newline;
            s("  strides:")(mStrides)(",").newline;
            s("  shape:")(mShape)(",").newline;
            s("  flags:")(flags)("=None");
            if (flags&Flags.Contiguous) s("|Contiguos");
            if (flags&Flags.Fortran) s("|Fortran");
            if (flags&Flags.Compact) s("|Compact");
            if (flags&Flags.Small) s("|Small");
            if (flags&Flags.Large) s("|Large");
            if (flags&Flags.ShouldFreeData) s("|ShouldFreeData");
            if (flags&Flags.ReadOnly) s("|ReadOnly");
            s(",").newline;
            s("  data: <array<")(V.stringof)("> @:")(mData.ptr)(", #:")(mData.length)(",").newline;
            s("  base:")(mBase).newline;
            s(">");
            return s;
        }
        
        /// returns the base for an array that is a view of the current array
        void *newBase(){
            void *res=mBase;
            if (mFlags&Flags.ShouldFreeData){
                assert(mBase is null,"if this array is the owner of the data it should not have base arrays");
                res=cast(void *)&this;
            }
            return res;
        }
        
        /// returns the flags for an array derived from the current one
        uint newFlags(){
            return mFlags&~Flags.ShouldFreeData; // &Flags.ExtFlags ???
        }
        
        /// increments a static index array, return true if it did wrap
        bool incrementArrayIdx(index_type[rank] index){
            int i=rank-1;
            while (i>=0) {
                ++index[i];
                if (index[i]<mShape[i]) break;
                index[i]=0;
                --i;
            }
            return i<0;
        }
        /// return the total number of elements in the array
        index_type size(){
            index_type res=1;
            for (int i=0;i<rank;++i){
                res*=mShape[i];
            }
            return res;
        }
        /// return the transposed view of the array
        NArray T(){
            index_type[rank] newshape,newstrides;
            for (int i=0;i<rank;++i){
                newshape[i]=mShape[rank-1-i];
            }
            for (int i=0;i<rank;++i){
                newstrides[i]=mStrides[rank-1-i];
            }
            return NArray(newstrides,newshape,mStartIdx,mData,newFlags,newBase);
        }
        
        /// returns an array that loops over the elements in the best possible way
        NArray optAxisOrder()
        in {
            for (int i=0;i<rank;++i)
                assert(mShape[i]>0,"zero sized arrays not accepted");
        }
        body {
            static if(rank==1){
                if (mStrides[0]>=0)
                    return this;
                return NArray([-mStrides[0]],mShape,mStartIdx+mStrides[0]*(mShape[0]-1),
                    mData,newFlags,newBase);
            } else static if(rank==2){
                if (mStrides[0]>=mStrides[1] && mStrides[0]>=0){
                    return this;
                } else {
                    index_type[rank] newstrides;
                    index_type newStartIdx=mStartIdx;
                    if (mStrides[0]>0){
                        newstrides[0]=mStrides[0];
                    } else {
                        newstrides[0]=-mStrides[0];
                        newStartIdx+=mStrides[0]*(mShape[0]-1);
                    }
                    if (mStrides[1]>0){
                        newstrides[1]=mStrides[1];
                    } else {
                        newstrides[1]=-mStrides[1];
                        newStartIdx+=mStrides[1]*(mShape[1]-1);
                    }
                    index_type[rank] newshape;
                    if(newstrides[0]>=newstrides[1]){
                        newshape[0]=mShape[0];
                        newshape[1]=mShape[1];
                    } else {
                        newshape[0]=mShape[1];
                        newshape[1]=mShape[0];
                        auto tmp=newstrides[0];
                        newstrides[0]=newstrides[1];
                        newstrides[1]=tmp;
                    }
                    return NArray(newstrides,newshape,newStartIdx,mData,newFlags,newBase);
                }
            } else {
                int no_reorder=1;
                for (int i=1;i<rank;++i)
                    if(mStrides[i-1]<mStrides[i]) no_reorder=0;
                if (no_reorder && mStrides[rank-1]>=0) return this;
                index_type[rank] pstrides;
                index_type newStartIdx=mStartIdx;
                for (int i=0;i<rank;++i){
                    if (mStrides[i]>0){
                        pstrides[i]=mStrides[i];
                    } else {
                        pstrides[i]=-mStrides[i];
                        newStartIdx+=mStrides[i]*(mShape[i]-1);
                    }
                }
                int[rank] sortIdx;
                for (int i=0;i<rank;i++)
                    sortIdx[i]=i;
                sortIdx.sort((int x,int y){return pstrides[x]>pstrides[y];});
                index_type[rank] newshape,newstrides;
                for (int i=0;i<rank;i++)
                    newshape[i]=mShape[sortIdx[i]];
                for (int i=0;i<rank;i++)
                    newstrides[i]=pstrides[sortIdx[i]];
                return NArray(newstrides,newshape,newStartIdx,mData,newFlags,newBase);
            }
        }
        
        /// perform a generic axis transformation (inversion an then permutation)
        /// and returns the resulting view (check validity of permutation?)
        NArray axisTransform(int[rank]perm,int[rank] invert)
        in{
            int [rank] found=0;
            for (int i=0;i<rank;++i){
                found[perm[i]]=1;
            }
            for (int i=0;i<rank;++i){
                assert(found[i],"invalid permutation");
            }
        }
        body{
            int no_change=1;
            for (int i=0;i<rank;++i){
                no_change=invert[i]==0&&perm[i]==i&&no_change;
            }
            if (no_change)
                return this;
            index_type[rank] newshape, pstrides, newstrides;
            index_type newStartIdx=mStartIdx;
            for (int i=0;i<rank;++i){
                if (!invert[i]){
                    pstrides[i]=-mStrides[i];
                } else {
                    pstrides[i]=-mStrides[i];
                    newStartIdx+=mStrides[i]*(mShape[i]-1);
                }
            }
            for (int i=0;i<rank;++i){
                newstrides[i]=pstrides[perm[i]];
                newshape[i]=mShape[perm[i]];
            }
            return NArray(newstrides,newshape,newStartIdx,mData,newFlags,newBase);
        }
        
        /// returns a random array (here with randNArray & co due to bug 2246)
        static NArray randomGenerate(Rand r,int idx,ref int nEl, ref bool acceptable){
            const index_type maxSize=1_000_000;
            float mean=10.0f;
            index_type[rank] dims;
            index_type totSize;
            do {
                foreach (ref el;dims){
                    el=cast(index_type)r.gamma(mean);;
                }
                totSize=1;
                foreach (el;dims)
                    totSize*=el;
                mean*=(cast(float)maxSize)/(cast(float)totSize);
            } while (totSize>maxSize)
            NArray res=NArray.empty(dims);
            return randNArray(r,res);
        }
    }
}// end static if
}// end template NArray

/+ -------- looping/generic operations --------- +/

/// applies an operation on all elements of the array. The looping order is arbitrary
/// and might be concurrent
void unaryOp(alias op,int rank,T)(NArray!(T,rank) a){
    mixin(pLoopPtr(rank,["a"],[],"op(*aPtr0);\n","i"));
}
/// ditto
void unaryOpStr(char[] op,int rank,T)(NArray!(T,rank) a){
    mixin(pLoopPtr(rank,["a"],[],op,"i"));
}

/// applies an operation combining the corresponding elements of two arrays.
/// The looping order is arbitrary and might be concurrent.
void binaryOp(alias op,int rank,T,S)(NArray!(T,rank) a, NArray!(S,rank) b)
in { assert(a.mShape==b.mShape,"incompatible shapes in binaryOp"); }
body {
    mixin(pLoopPtr(rank,["a","b"],[],"op(*aPtr0,*bPtr0);\n","i"));
}
/// ditto
void binaryOpStr(char[] op,int rank,T,S)(NArray!(T,rank) a, NArray!(S,rank) b)
in { assert(a.mShape==b.mShape,"incompatible shapes in binaryOp"); }
body {
    mixin(pLoopPtr(rank,["a","b"],[],op,"i"));
}

/// applies an operation combining the corresponding elements of three arrays .
/// The looping order is arbitrary and might be concurrent.
void ternaryOp(alias op, int rank, T, S, U)(NArray!(T,rank) a, NArray!(S,rank) b, NArray!(U,rank) c)
in { assert(a.mShape==b.mShape && a.mShape==c.mShape,"incompatible shapes in ternaryOp"); }
body {
    mixin(pLoopPtr(rank,["a","b","c"],[],
        "op(*aPtr0,*bPtr0,*cPtr0);\n","i"));
}
/// ditto
void ternaryOpStr(char[] op, int rank, T, S, U)(NArray!(T,rank) a, NArray!(S,rank) b, NArray!(U,rank) c)
in { assert(a.mShape==b.mShape && a.mShape==c.mShape,"incompatible shapes in ternaryOp"); }
body {
    mixin(pLoopPtr(rank,["a","b","c"],[],op,"i"));
}

/+ -------------- looping mixin constructs ---------------- +/

/// if baseName is not empty adds a dot (somethime this.xxx does not work and xxx works)
char [] arrayNameDot(char[] baseName){
    if (baseName=="") {
        return "";
    } else {
        return baseName~".";
    }
}
/++
+ general sequential index based loop character mixin
+/
char [] sLoopGenIdx(int rank,char[][] arrayNames,char[][] startIdxs,
        char[] loop_body,char[]ivarStr,char[]indent="    "){
    char[] res="".dup;
    char[] indentInc="    ";
    char[] indent2=indent~indentInc;

    foreach(i,arrayName;arrayNames){
        res~=indent~arrayNameDot(arrayName)~"dtype * "~arrayName~"BasePtr="
            ~arrayNameDot(arrayName)~"mData.ptr;\n";
        
        res~=indent~"index_type "~arrayName~"Idx"~ctfe_i2a(rank-1)~"=";
        if (startIdxs.length<=i || startIdxs[i]=="")
            res~=arrayNameDot(arrayName)~"mStartIdx;\n";
        else
            res~=startIdxs[i]~";\n";
        for (int idim=0;idim<rank;idim++){
            res~=indent~"index_type "~arrayName~"Stride"~ctfe_i2a(idim)~"="
                ~arrayNameDot(arrayName)~"mStrides["~ctfe_i2a(idim)~"];\n";
        }
    }
    for (int idim=0;idim<rank;idim++){
        char[] ivar=ivarStr.dup~"_"~ctfe_i2a(idim)~"_";
        res~=indent~"for (index_type "~ivar~"=0;"
            ~ivar~"<"~arrayNameDot(arrayNames[0])~"mShape["~ctfe_i2a(idim)~"];++"~ivar~"){\n";
        if (idim<rank-1) {
            foreach(arrayName;arrayNames){
                res~=indent2~"index_type "~arrayName~"Idx"~ctfe_i2a(rank-2-idim)~"="~arrayName~"Idx"~ctfe_i2a(rank-1-idim)~";\n";
            }
        }
        indent=indent2;
        indent2=indent~indentInc;
    }
    res~=indent~loop_body~"\n";
    for (int idim=rank-1;idim>=0;idim--){
        indent2=indent[0..indent.length-indentInc.length];
        foreach(arrayName;arrayNames){
            res~=indent~arrayName~"Idx"~ctfe_i2a(rank-1-idim)~" += "
                ~arrayName~"Stride"~ctfe_i2a(idim)~";\n";
        }
        res~=indent2~"}\n";
        indent=indent2;
    }
    return res;
}

/++
+ general sequential pointer based mixin
+ partial pointers are defined, but indexes are not (counts backward)
+/
char [] sLoopGenPtr(int rank,char[][] arrayNames,char[][] startIdxs,
        char[] loop_body,char[]ivarStr,char[] indent="    "){
    char[] res="".dup;
    char[] indInc="    ";
    char[] indent2=indent~indInc;

    foreach(i,arrayName;arrayNames){
        res~=indent;
        res~=arrayNameDot(arrayName)~"dtype * "~arrayName~"Ptr"~ctfe_i2a(rank-1)~"="~arrayNameDot(arrayName)~"mData.ptr+";
        if (startIdxs.length<=i || startIdxs[i]=="")
            res~=arrayNameDot(arrayName)~"mStartIdx;\n";
        else
            res~=startIdxs[i]~";\n";
        for (int idim=0;idim<rank;idim++){
            res~=indent;
            res~="index_type "~arrayName~"Stride"~ctfe_i2a(idim)~"="~arrayNameDot(arrayName)~"mStrides["~ctfe_i2a(idim)~"];\n";
        }
    }
    for (int idim=0;idim<rank;idim++){
        char[] ivar=ivarStr.dup~"_"~ctfe_i2a(idim)~"_";
        res~=indent~"for (index_type "~ivar~"="~arrayNameDot(arrayNames[0])~"mShape["~ctfe_i2a(idim)~"];"
            ~ivar~"!=0;--"~ivar~"){\n";
        if (idim<rank-1) {
            foreach(arrayName;arrayNames){
                res~=indent2~arrayNameDot(arrayName)~"dtype * "~arrayName~"Ptr"~ctfe_i2a(rank-2-idim)~"="~arrayName~"Ptr"~ctfe_i2a(rank-1-idim)~";\n";
            }
        }
        indent=indent2;
        indent2=indent~indInc;
    }
    res~=indent~loop_body~"\n";
    for (int idim=rank-1;idim>=0;idim--){
        indent2=indent[0..indent.length-indInc.length];
        foreach(arrayName;arrayNames){
            res~=indent~arrayName~"Ptr"~ctfe_i2a(rank-1-idim)~" += "
                ~arrayName~"Stride"~ctfe_i2a(idim)~";\n";
        }
        res~=indent2~"}\n";
        indent=indent2;
    }
    return res;
}

/++
+ possibly parallel Index based loop that never compacts.
+ All indexes (flat and in each dimension) are defined.
+/
char [] pLoopGenIdx(int rank,char[][] arrayNames,char[][] startIdxs,
        char[] loop_body,char[]ivarStr){
    return sLoopGenIdx(rank,arrayNames,startIdxs,loop_body,ivarStr);
}

/++
+ (possibly) parallel index based loop character mixin.
+ Only the flat indexes are valid if it can do a compact loop.
+ startIdxs is ignored if it can do a compact loop.
+/
char [] pLoopIdx(int rank,char[][] arrayNames,char[][] startIdxs,
        char[] loopBody,char[]ivarStr,char[][] arrayNamesDot=[],int[] optAccess=[],char[] indent="    "){
    if (arrayNames.length==0)
        return "".dup;
    char[] res="".dup;
    char[] indent2=indent~"    ";
    char[] indent3=indent2~"    ";
    bool hasNamesDot=true;
    if (arrayNamesDot.length==0){
        hasNamesDot=false;
        arrayNamesDot=[];
        foreach(i,arrayName;arrayNames)
            arrayNamesDot~=[arrayNameDot(arrayName)];
    }
    assert(arrayNamesDot.length==arrayNames.length);
    if(hasNamesDot)
        res~=indent~"commonFlags"~ivarStr~"=";
    else
        res~=indent~"uint commonFlags"~ivarStr~"=";
    foreach (i,arrayName;arrayNames){
        res~=arrayNameDot(arrayName)~"mFlags";
        if (i!=arrayNames.length-1) res~=" & ";
    }
    res~=";\n";
    res~=indent~"if ("~arrayNameDot(arrayNames[0])~"mData !is null &&\n";
    res~=indent~"    (commonFlags"~ivarStr~"&(ArrayFlags.Contiguous|ArrayFlags.Fortran) ||\n";
    res~=indent~"    commonFlags"~ivarStr~"&(ArrayFlags.Small | ArrayFlags.Compact)==ArrayFlags.Compact\n";
    res~=indent2;
    for (int i=1;i<arrayNames.length;i++)
        res~="&& "~arrayNameDot(arrayNames[0])~"mStrides=="~arrayNameDot(arrayNames[i])~"mStrides ";
    res~=")){\n";
    res~=indent2~"index_type "~ivarStr~"_0;\n";
    res~=indent2~"index_type "~ivarStr~"Length="~arrayNameDot(arrayNames[0])~"mData.length;\n";
    foreach(i,arrayName;arrayNames){
        res~=indent2~arrayNameDot(arrayName)~"dtype * "~arrayName~"BasePtr="
            ~arrayNameDot(arrayName)~"mData.ptr;\n";
        res~=indent2~"alias "~ivarStr~"_0 "~arrayName~"Idx0;\n";
    }
    res~=indent2~"for ("~ivarStr~"_0=0;"~ivarStr~"_0!="~ivarStr~"Length;++"~ivarStr~"_0){\n";
    res~=indent3~loopBody~"\n";
    res~=indent2~"}\n";
    res~=indent~"}";
    if(!hasNamesDot && arrayNames.length==1){
        res~=" else if (commonFlags"~ivarStr~"&ArrayFlags.Large){\n";
        res~=indent2~"typeof("~arrayNames[0]~") "~arrayNames[0]~"_opt_="
            ~arrayNamesDot[0]~"optAxisOrder;\n";
        char[][] newNamesDot=[arrayNames[0]~"_opt_."];
        res~=pLoopIdx(rank,arrayNames,startIdxs,loopBody,ivarStr,newNamesDot,[],indent2);
        res~=indent~"}";
    } else if ((!hasNamesDot) && arrayNames.length>1 && optAccess.length>0){
        res~=" else if (commonFlags"~ivarStr~"&ArrayFlags.Large){\n";
        res~=indent2~"int[rank] perm,invert;\n";
        res~=indent2~"findOptAxisTransform(perm,invert,[";
        foreach(i,iArr;optAccess){
            assert(iArr>=0&&iArr<arrayNames.length,"out of bound optAccess");
            res~=arrayNames[iArr];
            if (i!=optAccess.length-1)
                res~=",";
        }
        res~="]);\n";
        foreach(i,arrayName;arrayNames){
            res~=indent2~"typeof("~arrayName~") "~arrayName~"_opt_="
                ~arrayNamesDot[i]~"axisTransform(perm,invert);\n";
        }
        char[][] newNamesDot=[];
        foreach(arrayName;arrayNames){
            newNamesDot~=[arrayName~"_opt_."];
        }
        res~=pLoopIdx(rank,arrayNames,startIdxs,loopBody,ivarStr,newNamesDot,[],indent2);
        res~=indent~"}";
    }
    res~=" else {\n";
    res~=sLoopGenIdx(rank,arrayNames,startIdxs,loopBody,ivarStr,indent2);
    res~=indent~"}";
    return res;
}
/++
+ (possibly) parallel pointer based loop character mixin
+ startIdxs is ignored if it can do a compact loop, only the final pointers are valid
+/
char [] pLoopPtr(int rank,char[][] arrayNames,char[][] startIdxs,
        char[] loopBody,char[]ivarStr,char[][] arrayNamesDot=[],int[] optAccess=[],char[] indent="    "){
    if (arrayNames.length==0)
        return "".dup;
    char[] res="".dup;
    char[] indent2=indent~"    ";
    char[] indent3=indent2~"    ";
    bool hasNamesDot=true;
    if (arrayNamesDot.length==0){
        hasNamesDot=false;
        arrayNamesDot=[];
        foreach(i,arrayName;arrayNames)
            arrayNamesDot~=[arrayNameDot(arrayName)];
    }
    assert(arrayNamesDot.length==arrayNames.length);
    if(hasNamesDot)
        res~=indent~"commonFlags"~ivarStr~"=";
    else
        res~=indent~"uint commonFlags"~ivarStr~"=";
    foreach (i,arrayNameD;arrayNamesDot){
        res~=arrayNameD~"mFlags";
        if (i!=arrayNamesDot.length-1) res~=" & ";
    }
    res~=";\n";
    res~=indent~"if (commonFlags"~ivarStr~"&(ArrayFlags.Contiguous|ArrayFlags.Fortran) ||\n";
    res~=indent2~"commonFlags"~ivarStr~"&(ArrayFlags.Small | ArrayFlags.Compact)==ArrayFlags.Compact\n";
    res~=indent2;
    for (int i=1;i<arrayNamesDot.length;i++)
        res~="&& "~arrayNamesDot[0]~"mStrides=="~arrayNamesDot[i]~"mStrides ";
    res~="){\n";
    foreach(i,arrayName;arrayNames)
        res~=indent2~arrayNamesDot[i]~"dtype * "~arrayName~"Ptr0="
            ~arrayNamesDot[i]~"mData.ptr;\n";
    res~=indent2~"for (index_type "~ivarStr~"_0="~arrayNamesDot[0]~"mData.length;"~
        ivarStr~"_0!=0;--"~ivarStr~"_0){\n";
    res~=indent3~loopBody~"\n";
    foreach(arrayName;arrayNames)
        res~=indent3~"++"~arrayName~"Ptr0;\n";
    res~=indent2~"}\n";
    res~=indent~"}";
    if(!hasNamesDot && arrayNames.length==1){
        res~=" else if (commonFlags"~ivarStr~"&ArrayFlags.Large){\n";
        res~=indent2~"typeof("~arrayNames[0]~") "~arrayNames[0]~"_opt_="
            ~arrayNamesDot[0]~"optAxisOrder;\n";
        char[][] newNamesDot=[arrayNames[0]~"_opt_."];
        res~=pLoopPtr(rank,arrayNames,startIdxs,loopBody,ivarStr,newNamesDot,[],indent2);
        res~=indent~"}";
    } else if ((!hasNamesDot) && arrayNames.length>1 && optAccess.length>0){
        res~=" else if (commonFlags"~ivarStr~"&ArrayFlags.Large){\n";
        res~=indent2~"int[rank] perm,invert;\n";
        res~=indent2~"findOptAxisTransform(perm,invert,[";
        foreach(i,iArr;optAccess){
            assert(iArr>=0&&iArr<arrayNames.length,"out of bound optAccess");
            res~=arrayNames[iArr];
            if (i!=optAccess.length-1)
                res~=",";
        }
        res~="]);\n";
        foreach(i,arrayName;arrayNames){
            res~=indent2~"typeof("~arrayName~") "~arrayName~"_opt_="
                ~arrayNamesDot[i]~"axisTransform(perm,invert);\n";
        }
        char[][] newNamesDot=[];
        foreach(arrayName;arrayNames){
            newNamesDot~=[arrayName~"_opt_."];
        }
        res~=pLoopPtr(rank,arrayNames,startIdxs,loopBody,ivarStr,newNamesDot,[],indent2);
        res~=indent~"}";
    }
    res~=" else {\n";
    res~=sLoopGenPtr(rank,arrayNames,startIdxs,loopBody,ivarStr,indent2);
    res~=indent~"}\n";
    return res;
}
/++
+ sequential (inner fastest) index based loop character mixin
+ only the 
+/
char [] sLoopIdx(int rank,char[][] arrayNames,char[][] startIdxs,
        char[] loopBody,char[]ivarStr){
    if (arrayNames.length==0)
        return "".dup;
    char[] res="".dup;
    res~="    uint commonFlags"~ivarStr~"=";
    foreach (i,arrayName;arrayNames){
        res~=arrayNameDot(arrayName)~"mFlags";
        if (i!=arrayNames.length-1) res~=" & ";
    }
    res~=";\n    if (commonFlags"~ivarStr~"&ArrayFlags.Contiguous){\n";
    foreach (i,arrayName;arrayNames){
        res~="        "~arrayNameDot(arrayName)~"dtype * "~arrayName~"BasePtr="~arrayNameDot(arrayName)~"mData.ptr;\n";
    }
    res~="        index_type "~arrayNames[0]~"_length="~arrayNameDot(arrayNames[0])~"mData.length;\n";
    res~="        for (index_type "~ivarStr~"_=0;"~ivarStr~"_!="~arrayNames[0]~"_length;++"~ivarStr~"_){\n";
    foreach(i,arrayName;arrayNames)
        res~="        index_type "~arrayName~"Idx0="~ivarStr~"_;";
    res~="            "~loopBody~"\n";
    res~="        }\n";
    res~="    } else {\n";
    res~=sLoopGenIdx(rank,arrayNames,startIdxs,loopBody,ivarStr);
    res~="    }";
    return res;
}

/++
+ sequential (inner fastest) loop character mixin
+/
char [] sLoopPtr(int rank,char[][] arrayNames,char[][] startIdxs,
        char[] loopBody,char[]ivarStr){
    if (arrayNames.length==0)
        return "".dup;
    char[] res="".dup;
    res~="    uint commonFlags"~ivarStr~"=";
    foreach (i,arrayName;arrayNames){
        res~=arrayNameDot(arrayName)~"mFlags";
        if (i!=arrayNames.length-1) res~=" & ";
    }
    res~=";\n    if (commonFlags"~ivarStr~"&ArrayFlags.Contiguous){\n";
    foreach (i,arrayName;arrayNames){
        res~="        "~arrayNameDot(arrayName)~"dtype * "~arrayName~"Ptr0="~arrayNameDot(arrayName)~"mData.ptr;\n";
    }
    res~="        for (index_type "~ivarStr~"_0="~arrayNameDot(arrayNames[0])~"mData.length;"~
        ivarStr~"_0!=0;--"~ivarStr~"_0){\n";
    res~="            "~loopBody~"\n";
    foreach(i,arrayName;arrayNames)
        res~="            ++"~arrayName~"Ptr0;\n";
    res~="        }\n";
    res~="    } else {\n";
    res~=sLoopGenPtr(rank,arrayNames,startIdxs,loopBody,ivarStr);
    res~="    }\n";
    return res;
}

/// array to Sequence (for arrayIndex,arrayIndexAssign)
char[] arrayToSeq(char[] arrayName,int dim){
    char[] res="".dup;
    for (int i=0;i<dim;++i){
        res~=arrayName~"["~ctfe_i2a(i)~"]";
        if (i!=dim-1)
            res~=", ";
    }
    return res;
}

char[] opApplyIdxAll(int rank,char[] arrayName,bool sequential){
    char[] res="".dup;
    char[] indent="    ";
    res~="int opApply(int delegate(";
    for (int i=0;i<rank;++i){
        res~="ref index_type, ";
    }
    res~="ref V) loop_body) {\n";
    char[] loopBody="".dup;
    loopBody~=indent~"int ret=loop_body(";
    for (int i=0;i<rank;++i){
        loopBody~="i_"~ctfe_i2a(i)~"_, ";
    }
    loopBody~="*(aBasePtr+aIdx0));\n";
    loopBody~=indent~"if (ret) return ret;\n";
    if (sequential) {
        res~=sLoopGenIdx(rank,["a"],[],loopBody,"i");
    } else {
        res~=pLoopGenIdx(rank,["a"],[],loopBody,"i");
    }
    res~="    return 0;";
    res~="}\n";
    return res;
}

/// finds the optimal axis transform for the given arrays
/// make it a variadic template?
void findOptAxisTransform(int rank,T,uint nArr)(out int[rank]perm,out int[rank]invert,
    NArray!(T,rank)[nArr] arrays)
in {
    assert(!(arrays[0].mFlags&ArrayFlags.Zero),"zero arrays not supported"); // accept them??
    for (int iArr=1;i<nArr;++i){
        assert(arrays[0].mShape==arrays[i].mShape,"all arrays need to have the same shape");
    }
}
body {
    invert[]=0;
    index_type[nArr][rank] pstrides;
    index_type[nArr] newStartIdx;
    for (int iArr=0;iArr<nArr;++iArr){
        auto nArr=arrays[iArr];
        newStartIdx[iArr]=nArr.mStartIdx;
        for (int i=0;i<rank;++i){
            auto s=nArr.mStrides[i];
            if (s>0){
                pstrides[i][iArr]=s;
                invert-=1;
            } else if (s!=0){
                pstrides[i][iArr]=-s;
                newStartIdx[iArr]+=s*(nArr.mShape[i]-1);
                invert+=1;
            } else {
                pstrides[i][iArr]=s;
            }
        }
    }
    for (int i=0;i<rank;++i)
        invert[i]=invert[i]>0;
    for (int i=0;i<rank;++i)
        perm[i]=[i];
    const int maxR=(rank>3)?rank-4:0;
    // use also the shape as criteria?
    for (int i=rank-1;i>=0;--i){
        for (int j=i-1;j>=0;--j){
            int shouldSwap=0;
            for (int iArr=0;iArr<nArr;++iArr){
                if (pstrides[perm[i]][iArr]<pstrides[perm[j]][iArr]){
                    shouldSwap-=1;
                }else if (pstrides[perm[i]][iArr]>pstrides[perm[j]][iArr]){
                    shouldSwap+=1;
                }
            }
            if (shouldSwap>0){
                auto tmp=perm[i];
                perm[i]=perm[j];
                perm[j]=tmp;
            }
        }
    }
}
/+ ------------------------------------------------- +/
// array randomization (here because due to bug 2246 in the 
// compiler the specialization of randomGenerate does not work,
// and it uses the RandGen interface)

/// randomizes the content of the array
NArray!(T,rank) randomizeNArray(RandG,T,int rank)(RandG r,NArray!(T,rank)a){
    if (a.mFlags | ArrayFlags.Compact){
        r.randomize(a.mData);
    } else {
        mixin unaryOpStr!("r.randomize(*aPtr0);",rank,T);
        unaryOpStr(a);
    }
    return a;
}
/// returns a random array of the given size with the given distribution
template randomNArray(T){
    NArray!(T,rkOfShape!(S))randomNArray(RandG,S)(RandG r,S dim){
        static if (arrayElT!(S)==index_type){
            alias dim mdim;
        } else {
            index_type[rkOfShape!(S)] mdim;
            foreach (i,ref el;mdim)
                el=dim[i];
        }
        NArray!(T,rkOfShape!(S)) res=NArray!(T,rkOfShape!(S)).empty!(T)(mdim);
        return randomizeNArray(r,res);
    }
}
/// returns a random array of the given size with normal (signed values)
/// or exp (unsigned values) distribued numbers.
NArray!(T,rank) randNArray(T,int rank)(Rand r, NArray!(T,rank) a){
    static if (is(T==float)|| is(T==double)||is(T==real)){
        auto source=r.normalD(cast(T)3.0);
    }else static if (is(T==ubyte)||is(T==uint)||is(T==ulong)) {
        auto source=r.expD(10.0);
    } else {
        auto source=r.normalD(30.0);
    }
    return randomizeNArray(source,a);
}

/// returns a new array with the same content as a, but with a random layout
/// (row ordering, loop order, strides,...)
NArray!(T,rank) randLayout(T,int rank)(Rand r, NArray!(T,rank)a){
    if (a.size==0) return a;
    int[rank] permutation,rest;
    foreach (i,ref el;rest)
        el=i;
    foreach (i,ref el;permutation){
        int pRest=r.uniformR(rank-i);
        permutation[i]=rest[pRest];
        rest[pRest]=rest[rank-i-1];
    }
    index_type[rank] gaps;
    index_type[] g=gaps[];
    r.normalD(1.0).randomize(g);
    foreach(ref el;gaps){
        if (el==0 || el>5 || el<-5) el=1;
    }
    index_type newStartIdx=0;
    index_type[rank] newStrides;
    index_type sz=1;
    foreach(perm;permutation){
        newStrides[perm]=sz*gaps[perm];
        sz*=a.mShape[perm]*abs(gaps[perm]);
        if (gaps[perm]<0) {
            newStartIdx+=-(a.mShape[perm]-1)*newStrides[perm];
        }
    }
    auto base=NArray!(T,1).empty([sz]);
    auto res=NArray!(T,rank)(newStrides,a.mShape,newStartIdx,
        base.mData,a.newFlags&~ArrayFlags.ReadOnly,base.newBase);
    res[]=a;
    res.mFlags|=(a.mFlags&ArrayFlags.ReadOnly);
    return res;
}
/+ ------------------------------------------------- +/
