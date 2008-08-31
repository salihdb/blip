/*******************************************************************************
    Basic linear algebra on NArrays
    at the moment only dot is available without blas/lapack
     norm       --- Vector or matrix norm
     inv        --- Inverse of a square matrix
     solve      --- Solve a linear system of equations
     det        --- Determinant of a square matrix
     lstsq      --- Solve linear least-squares problem
     pinv       --- Pseudo-inverse (Moore-Penrose) using lstsq
    
    Eigenvalues and Decompositions:
    
     eig        --- Eigenvalues and vectors of a square matrix
     eigh       --- Eigenvalues and eigenvectors of a Hermitian matrix
     eigvals    --- Eigenvalues of a square matrix
     eigvalsh   --- Eigenvalues of a Hermitian matrix.
     svd        --- Singular value decomposition of a matrix
     cholesky   --- Cholesky decomposition of a matrix
    
    copyright:      Copyright (c) 2008. Fawzi Mohamed
    license:        BSD style: $(LICENSE)
    version:        Initial release: July 2008
    author:         Fawzi Mohamed
*******************************************************************************/
module frm.narray.LinAlg;
import tango.io.Stdout;
import frm.narray.BasicTypes;
import frm.narray.BasicOps;
version(darwin){
    version=blas;
    version=lapack;
}
version(blas){
    import DBlas=gobo.blas.DBlas;
    public import gobo.blas.Types;
}
version(lapack){
    static assert(is(typeof(f_float)),"lapack needs blas");
    import DLapack=gobo.lapack.DLapack;
}

class LinAlgException:Exception{
    this(char[] err){
        super(err);
    }
}

/// dot product between tensors (reduces a single axis)
NArray!(typeof(T.init*U.init),rank1+rank2-2)dot(T,int rank1,U,int rank2)
    (NArray!(T,rank1)a,NArray!(U,rank2)b,int axis1=-1, int axis2=0)
in {
    assert(-rank1<=axis1 && axis1<rank1,"axis1 out of bounds");
    assert(-rank2<=axis2 && axis2<rank2,"axis2 out of bounds");
    assert(a.shape[((axis1<0)?(rank1+axis1):axis1)]==b.shape[((axis2<0)?(rank2+axis2):axis2)],
        "fuse axis has to have the same size in a and b");
}
body {
    alias typeof(T.init*U.init) S;
    const int rank3=rank1+rank2-2;
    index_type[rank3] newshape;
    int ii=0;
    if (axis1<0) axis1+=rank1;
    if (axis2<0) axis2+=rank2;
    for (int i=0;i<rank1;++i){
        if (i!=axis1){
            newshape[ii]=a.shape[i];
            ++ii;
        }
    }
    for (int i=0;i<rank2;++i){
        if (i!=axis2){
            newshape[ii]=b.shape[i];
            ++ii;
        }
    }
    static if(rank3==0){
        S res;
    } else {
        auto res=NArray!(S,rank3).empty(newshape);
    }
    return dot!(T,rank1,U,rank2,S,rank3)(a,b,res,cast(S)1,cast(S)0,axis1,axis2);
}

/// dot product between tensors (reduces a single axis) with scaling and
/// already present storage target
NArray!(S,rank3)dot(T,int rank1,U,int rank2,S,int rank3)
    (NArray!(T,rank1)a, NArray!(U,rank2)b, ref NArray!(S,rank3) c,
        S scaleRes=cast(S)1, S scaleC=cast(S)0, int axis1=-1, int axis2=0)
in {
    static assert(rank3==rank1+rank2-2,"rank3 has to be rank1+rank2-2");
    assert(-rank1<=axis1 && axis1<rank1,"axis1 out of bounds");
    assert(-rank2<=axis2 && axis2<rank2,"axis2 out of bounds");
    assert(a.shape[((axis1<0)?(rank1+axis1):axis1)]==b.shape[((axis2<0)?(rank2+axis2):axis2)],
        "fuse axis has to have the same size in a and b");
    int ii=0;
    static if(rank3!=0){
        for (int i=0;i<rank1;++i){
            if (i!=axis1 && i!=rank1+axis1){
                assert(c.shape[ii]==a.shape[i],"invalid shape for c");
                ++ii;
            }
        }
        for (int i=0;i<rank2;++i){
            if (i!=axis2 && i!=rank2+axis2){
                assert(c.shape[ii]==b.shape[i],"invalid shape for c");
                ++ii;
            }
        }
    }
}
body {
    if (axis1<0) axis1+=rank1;
    if (axis2<0) axis2+=rank2;
    if ((a.flags|b.flags)&ArrayFlags.Zero){
        if (scaleC==0){
            static if(rank3>0){
                c[]=cast(T)0;
            } else {
                c=cast(T)0;
            }
        } else {
            c *= scaleC;
        }
        return c;
    }
    version(blas){
        static if ((is(T==U) && isBlasType!(T)) && (rank1==1 || rank1==2)&&(rank2==1 || rank2==2)){
            // call blas
            // negative incremented vector in blas loops backwards on a[0..n], not on a[-n+1..1]
            static if(rank1==1 && rank2==1){
                T* aStartPtr=a.startPtrArray,bStartPtr=b.startPtrArray;
                if (a.bStrides[0]<0) aStartPtr=cast(T*)(cast(size_t)aStartPtr+(a.shape[0]-1)*a.bStrides[0]);
                if (b.bStrides[0]<0) bStartPtr=cast(T*)(cast(size_t)bStartPtr+(b.shape[0]-1)*b.bStrides[0]);
                static if (is(T==f_float) && is(S==f_double)){
                    c=cast(S)DBlas.ddot(a.shape[0], aStartPtr, a.bStrides[0]/cast(index_type)T.sizeof,
                        bStartPtr, b.bStrides[0]/cast(index_type)T.sizeof);
                } else static if (is(T==cfloat)|| is(T==cdouble)){
                    c=cast(S)DBlas.dotu(a.shape[0], aStartPtr, a.bStrides[0]/cast(index_type)T.sizeof,
                        bStartPtr, b.bStrides[0]/cast(index_type)T.sizeof);
                } else {
                    c=cast(S)DBlas.dot(a.shape[0], aStartPtr, a.bStrides[0]/cast(index_type)T.sizeof,
                        bStartPtr, b.bStrides[0]/cast(index_type)T.sizeof);
                }
                return c;
            } else static if (rank1==1 && rank2==2) {
                T* aStartPtr=a.startPtrArray;
                if (a.bStrides[0]<0) aStartPtr=cast(T*)(cast(size_t)aStartPtr+(a.shape[0]-1)*a.bStrides[0]);
                if (b.bStrides[0]==cast(index_type)T.sizeof && b.bStrides[1]>0 ||
                    b.bStrides[1]==cast(index_type)T.sizeof && b.bStrides[0]>0){
                    int transpose=1;
                    if (axis2==1) transpose=0;
                    if (b.bStrides[0]!=cast(index_type)T.sizeof) transpose=!transpose;
                    f_int ldb=cast(f_int)((b.bStrides[0]==cast(index_type)T.sizeof)?b.bStrides[1]:b.bStrides[0]);
                    f_int m=(transpose?a.shape[0]:c.shape[0]);
                    // this check is needed to give a valid ldb to blas (that checks it)
                    // even if ldb is never needed (only one column)
                    if (ldb!=cast(f_int)T.sizeof){
                        ldb/=cast(index_type)T.sizeof;
                    } else {
                        ldb=m;
                    }
                    DBlas.gemv((transpose?'T':'N'), m,
                        (transpose?c.shape[0]:a.shape[0]),scaleRes,
                        b.startPtrArray, ldb,
                        aStartPtr,a.bStrides[0]/cast(index_type)T.sizeof,
                        scaleC, c.startPtrArray, c.bStrides[0]/cast(index_type)T.sizeof);
                    return c;
                }
            } else static if (rank1==2 && rank2==1) {
                T* bStartPtr=b.startPtrArray;
                if (b.bStrides[0]<0) bStartPtr=cast(T*)(cast(size_t)bStartPtr+(b.shape[0]-1)*b.bStrides[0]);
                if (a.bStrides[0]==cast(index_type)T.sizeof && a.bStrides[1]>0 ||
                    a.bStrides[1]==cast(index_type)T.sizeof && a.bStrides[0]>0){
                    int transpose=1;
                    if (axis1==1) transpose=0;
                    if (a.bStrides[0]!=cast(index_type)T.sizeof) transpose=!transpose;
                    f_int lda=cast(f_int)((a.bStrides[0]==cast(index_type)T.sizeof)?a.bStrides[1]:a.bStrides[0]);
                    f_int m=(transpose?b.shape[0]:c.shape[0]);
                    // this check is needed to give a valid lda to blas (that checks it)
                    // even if lda is never needed (only one column)
                    if (lda!=cast(f_int)T.sizeof){
                        lda/=cast(index_type)T.sizeof;
                    } else {
                        lda=m;
                    }
                    DBlas.gemv((transpose?'T':'N'), m,
                        (transpose?c.shape[0]:b.shape[0]), scaleRes,
                        a.startPtrArray, lda,
                        bStartPtr,b.bStrides[0]/cast(index_type)T.sizeof,
                        scaleC, c.startPtrArray, c.bStrides[0]/cast(index_type)T.sizeof);
                    return c;
                }
            } else static if(is(S==T)){
                static assert(rank1==2 && rank2==2);
                if ((a.bStrides[0]==cast(index_type)T.sizeof && a.bStrides[1]>0 || a.bStrides[1]==cast(index_type)T.sizeof && a.bStrides[0]>0)&&
                    (b.bStrides[0]==cast(index_type)T.sizeof && b.bStrides[1]>0 || b.bStrides[1]==cast(index_type)T.sizeof && b.bStrides[0]>0)&&
                    (c.bStrides[0]==cast(index_type)T.sizeof && c.bStrides[1]>0 || c.bStrides[1]==cast(index_type)T.sizeof && c.bStrides[0]>0)){
                    int transposeA=0;
                    if (axis1==0) transposeA=1;
                    if (a.bStrides[0]!=cast(index_type)T.sizeof) transposeA=!transposeA;
                    int transposeB=0;
                    if (axis2==1) transposeB=1;
                    if (b.bStrides[0]!=cast(index_type)T.sizeof) transposeB=!transposeB;
                    int swapAB=c.bStrides[0]!=cast(index_type)T.sizeof;
                    f_int ldb=cast(f_int)((b.bStrides[0]==cast(index_type)T.sizeof)?b.bStrides[1]:b.bStrides[0]);
                    f_int lda=cast(f_int)((a.bStrides[0]==cast(index_type)T.sizeof)?a.bStrides[1]:a.bStrides[0]);
                    f_int ldc=cast(f_int)((c.bStrides[0]==cast(index_type)T.sizeof)?c.bStrides[1]:c.bStrides[0]);
                    // these checks are needed to give a valid ldX to blas (that checks it)
                    // even if ldX is never needed (only one column)
                    if (ldb!=cast(f_int)T.sizeof)
                        ldb/=cast(index_type)T.sizeof;
                    else
                        ldb=(transposeB?b.shape[1-axis2]:b.shape[axis2]);
                    if (lda!=cast(f_int)T.sizeof)
                        lda/=cast(index_type)T.sizeof;
                    else
                        lda=(transposeA?a.shape[axis1]:a.shape[1-axis1]);
                    if (ldc!=cast(f_int)T.sizeof)
                        ldc/=cast(index_type)T.sizeof;
                    else
                        ldc=c.shape[0];
                    if (swapAB){
                        DBlas.gemm((transposeB?'N':'T'), (transposeA?'N':'T'),
                        b.shape[1-axis2], a.shape[1-axis1], a.shape[axis1], scaleRes,
                        b.startPtrArray,ldb,
                        a.startPtrArray,lda,
                        scaleC,
                        c.startPtrArray,ldc);
                    } else {
                        DBlas.gemm((transposeA?'T':'N'), (transposeB?'T':'N'),
                        a.shape[1-axis1], b.shape[1-axis2], a.shape[axis1], scaleRes,
                        a.startPtrArray,lda,
                        b.startPtrArray,ldb,
                        scaleC,
                        c.startPtrArray,ldc);
                    }
                    return c;
                }
            }
        }
    }
    if (scaleC==0){
        if (scaleRes==1){
            mixin fuse1!((ref S x,T y,U z){x+=y*z;},(S *x0,ref S x){x=cast(S)0;},
                (S* x0,S xV){*x0=xV;},T,rank1,U,rank2,S);
            fuse1(a,b,c,axis1,axis2);
        } else {
            mixin fuse1!((ref S x,T y,U z){x+=y*z;},(S* x0,ref S x){x=cast(S)0;},
                (S* x0,S xV){*x0=scaleRes*xV;},T,rank1,U,rank2,S);
            fuse1(a,b,c,axis1,axis2);
        }
    } else {
        mixin fuse1!((ref S x,T y,U z){x+=y*z;},(S* x0,ref S x){x=cast(S)0;},
            (S* x0,S xV){*x0=scaleC*(*x0)+scaleRes*xV;},T,rank1,U,rank2,S);
        fuse1(a,b,c,axis1,axis2);
    }
    return c;
}

version (lapack){
    /// finds x for which dot(a,x)==b for a square matrix a
    /// not so efficient (copies a)
    NArray!(T,2) solve(T)(NArray!(T,2)a,NArray!(T,2)b,NArray!(T,2)x=null)
    in{
        static assert(isBlasType!(T),"implemented only for blas types");
        assert(a.shape[0]==a.shape[1],"a should be square");
        assert(a.shape[0]==b.shape[0],"incompatible shapes a-b");
        if (x !is null){
            assert(a.shape[1]==x.shape[0],"incompatible shapes a-x");
            assert(x.shape[1]==b.shape[1],"incompatible shapes b-x");
        }
    }
    body {
        a=a.dup(true);
        scope ipiv=NArray!(f_int,1).empty(a.shape[0]);
        f_int info;
        if (x is null) x=b.dup(true);
        if (!(x.bStrides[0]==cast(index_type)T.sizeof && x.bStrides[1]>0 || x.bStrides[1]==cast(index_type)T.sizeof && x.bStrides[0]>0)){
            scope NArray!(T,2) xx=b.dup(true);
            DLapack.gesv(a.shape[0], b.shape[1], a.startPtrArray, a.bStrides[1]/cast(index_type)T.sizeof, ipiv.startPtrArray,
                xx.startPtrArray, xx.shape[1], info);
            x[]=xx;
        } else {
            DLapack.gesv(a.shape[0], b.shape[1], a.startPtrArray, a.bStrides[1]/cast(index_type)T.sizeof, ipiv.startPtrArray,
                x.startPtrArray, x.shape[1], info);
        }
        if (info > 0)
            throw new LinAlgException("Singular matrix");
        return x;
    }
    /// ditto
    NArray!(T,1) solve(T)(NArray!(T,2)a,NArray!(T,1)b,NArray!(T,1)x=null)
    in{
        static assert(isBlasType!(T),"implemented only for blas types");
        assert(a.shape[0]==a.shape[1],"a should be square");
        assert(a.shape[0]==b.shape[0],"incompatible shapes a-b");
        assert(x is null || x.shape[0]==b.shape[0],"incompatible shapes b-x");
    }
    body {
        scope NArray!(T,2) b1=repeat(b,1,-1);
        if (x is null) x=b.dup(true);
        scope NArray!(T,2) x1=repeat(x,1,-1);
        solve(a,b1,x1);
        return x;
    }
    
    /// returns the inverse matrix
    NArray!(T,2) inv(T)(NArray!(T,2)a)
    in {
        static assert(isBlasType!(T),"implemented only for blas types");
        assert(a.shape[0]==a.shape[1],"a has to be square");
    }
    body {
        scope un=eye!(T)(a.shape[0]);
        return solve(a,un);
    }
    
    /// determinant of the matrix a
    T det(T)(NArray!(T,2)a)
    in {
        static assert(isBlasType!(T),"implemented only for blas types");
        assert(a.shape[0]==b.shape[1],"a has to be square");
    }
    body {
        scope NArray!(f_int,1) pivots = NArray!(f_int,1).zeros();
        f_int info;
        auto a2=a.dup(true);
        results = getrf(a2, pivots, info);
        if (info > 0)
            return cast(T)0;
        int sign=0;
        for (index_type i=0;i<a.shape[0];++i)
            sign += (pivots[i] != i+1);
        sign=sign % 2;
        return (1.-2.*sign)*multiplyAll(diag(a2));
    }
    
    /// wrapper for the lapack Xgetrf routine
    /// computes an LU factorization of a general M-by-N matrix A in place
    /// using partial pivoting with row interchanges.
    /// T has to be a blas type, the matrix a has to ba acceptable to lapack (a.dup(true) if it is not)
    /// and ipiv has to be continuos
    /// if INFO = i>0, U(i-1,i-1) is exactly zero. The factorization
    /// has been completed, but the factor U is exactly
    /// singular, and division by zero will occur if it is used
    /// to solve a system of equations.
    NArray!(T,2) getrf(T)(NArray!(T,2) a,NArray!(f_int,1) ipiv,f_int info)
    in {
        static assert(isBlasType!(T),"implemented only for blas types");
        assert(a.bStrides[0]==cast(index_type)T.sizeof && a.bStrides[1]>=a.shape[0],"a has to be a blas matrix");
        assert(ipiv.bStrides[0]==cast(index_type)T.sizeof,"ipiv has to have stride 1");
        assert(ipiv.shape[0]>=a.shape[0]||ipiv.shape[0]>=a.shape[1],"ipiv should be at least min(a.shape)");
    }
    body {
        DLapack.getrf(a.shape[0], a.shape[1], a.startPtrArray, a.bStrides[1]/cast(index_type)T.sizeof,
            pivots.startPtrArray, info);
        if (info < 0)
            throw new LinAlgException("Illegal input to Fortran routine");
        return a;
    }
    
    /// complex type for the given type
    template complexType(T){
        static if(is(T==float)|| is(T==ifloat)|| is(T==cfloat)){
            alias cfloat complexType;
        } else static if(is(T==double)|| is(T==idouble)|| is(T==cdouble)){
            alias cdouble complexType;
        } else static if(is(T==real)|| is(T==ireal)|| is(T==creal)){
            alias creal complexType;
        } else static assert(0,"unsupported type in complexType "~T.stringof);
    }
    
    /// real type for the given type
    template realType(T){
        static if(is(T==float)|| is(T==ifloat)|| is(T==cfloat)){
            alias float realType;
        } else static if(is(T==double)|| is(T==idouble)|| is(T==cdouble)){
            alias double realType;
        } else static if(is(T==real)|| is(T==ireal)|| is(T==creal)){
            alias real realType;
        } else static assert(0,"unsupported type in realType "~T.stringof);
    }
    
    /// calculates eigenvalues and (if not null) the  right (and left) eigenvectors
    /// of the given matrix
    NArray!(complexType!(T),1) eig(T)(NArray!(T,2)a,NArray!(complexType!(T),1) ev=null,
        NArray!(complexType!(T),2)leftEVect=null,NArray!(complexType!(T),2)rightEVect=null)
    in {
        static assert(isBlasType!(T),"only blas types accepted");
        assert(a.shape[0]==a.shape[1],"matrix a has to be square");
        assert(a.shape[0]==ev.shape[1],"ev has an incorrect size");
        if (rightEVect !is null) {
            assert(a.shape[0]==rightEVect[0],"invalid size for rightEVect");
            assert(a.shape[0]==rightEVect[1],"invalid size for rightEVect");
        }
        if (leftEVect !is null) {
            assert(a.shape[0]==leftEVect[0],"invalid size for leftEVect");
            assert(a.shape[0]==leftEVect[1],"invalid size for leftEVect");
        }
    }
    body {
        scope NArray!(T,2) a1=a.dup(true);
        NArray!(complexType!(T),2) lE=leftEVect,rE=rightEVect;
        T* lEPtr=null,rEPtr=null;
        f_int lELd,rELd;
        if (leftEVect !is null){
            if (leftEVect.bStrides[0]!=cast(index_type)T.sizeof || leftEVect.bStrides[1]<leftEVect.shape[0]*cast(index_type)T.sizeof) {
                lE=leftEVect.dup(true);
            }
            lEPtr=lE.startPtrArray;
            lELd=lE.bStrides[1]/cast(index_type)T.sizeof;
        }
        if (rightEVect !is null){
            if (rightEVect.bStrides[0]!=cast(index_type)T.sizeof || rightEVect.bStrides[1]<rightEVect.shape[0]*cast(index_type)T.sizeof) {
                rE=rightEVect.dup(true);
            }
            rEPtr=rE.startPtrArray;
            rELd=rE.bStrides[1]/cast(index_type)T.sizeof;
        }
        NArray!(complexType!(T),1) eigenval=ev;
        if (eigenval is null || eigenval.bStrides[0]!=cast(index_type)T.sizeof || eigenval.bStrides[1]<=eigenval.shape[0]*cast(index_type)T.sizeof) {
            eigenval = zeros!(complexType!(T))(n);
        }
        f_int n=a.shape[0],info;
        f_int lwork = -1;
        T workTmp;
        static if(is(complexType!(T)==T)){
            scope NArray!(realType!(T),1) rwork = empty!(realType!(T))(2*n);
            DLapack.geev(((lEPtr is null)?'N':'V'),((rEPtr is null)?'N':'V'),n,
                a1.startPtrArray, a1.bStrides[1]/cast(index_type)T.sizeof, w.startPtrArray, lEPtr, lELd, rEPtr, rELd,
                &workTmp, lwork, rwork.startPtrArray, info);
            lwork = cast(int)abs(work[0])+1;
            scope NArray!(T,1) work = empty!(T)(lwork);
            DLapack.geev(((lEPtr is null)?'N':'V'),((rEPtr is null)?'N':'V'),n,
                a1.startPtrArray, a1.bStrides[1]/cast(index_type)T.sizeof, w.startPtrArray, lEPtr, lELd, rEPtr, rELd,
                work, work.bStrides[1]/cast(index_type)T.sizeof, rwork.startPtrArray, info);
            
        } else {
            scope NArray!(realType!(T),1) wr = empty!(realType!(T))(n);
            scope NArray!(realType!(T),1) wi = empty!(realType!(T))(n);
            DLapack.geev(((lEPtr is null)?'N':'V'),((rEPtr is null)?'N':'V'),n,
                a1.startPtrArray, a1.bStrides[1]/cast(index_type)T.sizeof, wr.ptr, wi.ptr, lEPtr, lELd, rEPtr, rELd,
                &workTmp, lwork, info);
            lwork = cast(int)abs(work[0])+1;
            scope NArray!(T,1) work = empty!(T)(lwork);
            DLapack.geev(((lEPtr is null)?'N':'V'),((rEPtr is null)?'N':'V'),n,
                a1.ptr, a1.bStrides[1]/cast(index_type)T.sizeof, wr.startPtrArray, wi.startPtrArray, lEPtr, lELd, rEPtr, rELd,
                work.startPtrArray, work.bStrides[1]/cast(index_type)T.sizeof, info);
            for (int i=0;i<n;++i)
                eigenval[i]=wr[i]+wi[i]*1i;
        }
        if (leftEVect !is lE) leftEVect[]=lE;
        if (rightEVect !is rE) rightEVect[]=rE;
        if (ev !is eigenval) ev[]=eigenval;
        if (info<0) throw new LinAlgException("Illegal input to Fortran routine");
        if (info>0) throw new LinAlgException("Eigenvalues did not converge");
        return eigenval;
    }
    
}
