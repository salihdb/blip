/*******************************************************************************
    TemplateFu contains various template stuff that I found useful to put
    in a single module
        copyright:      Copyright (c) 2008. Fawzi Mohamed
        license:        BSD style: $(LICENSE)
        version:        Initial release: July 2008
        author:         Fawzi Mohamed
*******************************************************************************/
module blip.TemplateFu;
import tango.core.Traits;

/// returns the number of arguments in the tuple (its length)
template nArgs(){
    const int nArgs=0;
}
/// returns the number of arguments in the tuple (its length)
template nArgs(T,S...){
    const int nArgs=1+nArgs!(S);
}

/// identity function
T Id(T)(T a) { return a; }

/// type with maximum precision
template maxPrecT(T){
    static if (isComplexType!(T)){
        alias creal maxPrecT;
    } else static if (isImaginaryType!(T)){
        alias ireal maxPrecT;
    } else {
        alias real maxPrecT;
    }
}

template isAtomicType(T)
{
    static if( is( T == bool )
            || is( T == char )
            || is( T == wchar )
            || is( T == dchar )
            || is( T == byte )
            || is( T == short )
            || is( T == int )
            || is( T == long )
            || is( T == ubyte )
            || is( T == ushort )
            || is( T == uint )
            || is( T == ulong )
            || is( T == float )
            || is( T == double )
            || is( T == real )
            || is( T == ifloat )
            || is( T == idouble )
            || is( T == ireal ) )
        const isAtomicType = true;
    else
        const isAtomicType = false;
}

template isArray(T)
{
    const bool isArray=is( T U : U[] );
}

template staticArraySize(T)
{
    static assert(isStaticArrayType!(T),"staticArraySize needs a static array as type");
    static assert(rankOfArray!(T)==1,"implemented only for 1d arrays...");
    const size_t staticArraySize=(T).sizeof / typeof(T.init).sizeof;
}

/// returns a dynamic array
template DynamicArrayType(T)
{
    static if( isStaticArrayType!(T) )
        alias typeof(T.dup) DynamicArrayType;
    else static if (isArray!(T))
        alias T DynamicArrayType;
    else
        alias T[] DynamicArrayType;
}

// ------- CTFE -------

/// compile time integer to string
char [] ctfe_i2a(int i){
    char[] digit="0123456789";
    char[] res="".dup;
    if (i==0){
        return "0".dup;
    }
    bool neg=false;
    if (i<0){
        neg=true;
        i=-i;
    }
    while (i>0) {
        res=digit[i%10]~res;
        i/=10;
    }
    if (neg)
        return '-'~res;
    else
        return res;
}

/// checks is c is a valid token char (also at compiletime), assumes a-z A-Z 1-9 sequences in collation
bool ctfe_isTokenChar(char c){
    return (c=='_' || c>='a'&&c<='z' || c>='A'&&c<='Z' || c=='0'|| c>='1' && c<='9');
}

/// checks if code contains the given token
bool ctfe_hasToken(char[] token,char[] code){
    bool outOfTokens=true;
    int i=0;
    while(i<code.length){
        if (outOfTokens){
            int j=0;
            for (;((j<token.length)&&(i<code.length));++j,++i){
                if (code[i]!=token[j]) break;
            }
            if (j==token.length){
                if (i==code.length || !ctfe_isTokenChar(code[i])){
                    return true;
                }
            }
        }
        do {
            outOfTokens=(!ctfe_isTokenChar(code[i]));
            ++i;
        } while((!outOfTokens) && i<code.length)
    }
    return false;
}

/// replaces all occurrences of token in code with repl
char[] ctfe_replaceToken(char[] token,char[] repl,char[] code){
    char[] res="".dup;
    bool outOfTokens=true;
    int i=0,i0;
    while(i<code.length){
        i0=i;
        if (outOfTokens){
            int j=0;
            for (;((j<token.length)&&(i<code.length));++j,++i){
                if (code[i]!=token[j]) break;
            }
            if (j==token.length){
                if (i==code.length || !ctfe_isTokenChar(code[i])){
                    res~=repl;
                    i0=i;
                }
            }
        }
        do {
            outOfTokens=(!ctfe_isTokenChar(code[i]));
            ++i;
        } while((!outOfTokens) && i<code.length)
        res~=code[i0..i];
    }
    return res;
}

/// compile time integer power
T ctfe_powI(T)(T x,int p){
    T xx=cast(T)1;
    if (p<0){
        p=-p;
        x=1/x;
    }
    for (int i=0;i<p;++i)
        xx*=x;
    return xx;
}