module blip.BasicModels;
import tango.io.Print;

/// interface of an object that can describe itself
interface BasicObjectI{
    Print!(char) desc(Print!(char) s);
}

/// basic interface for objects that can be copied (shallowly)
interface DuplicableI{
    DuplicableI dup();
}

/// basic interface for objects that can be copied (deeply)
interface DeepDuplicableI{
    DeepDuplicableI deepdup();
}

/// basic copiable objects
interface CopiableObjectI : BasicObjectI,DuplicableI,DeepDuplicableI { }

/// object that can do a foreach loop
interface ForeachableI(T){
    /// loop without index, has to be implemented
    int opApply(int delegate(T x) dlg);
    /// loop with index, migh not be implemented (and throw)
    int opApply(int delegate(size_t i,T x) dlg);
}

/// forward iterator interface, and foreach support.
/// the two things cannot be mixed (begin to iterate,
/// then continue with foreach is not allowed)
interface FIteratorI(T): ForeachableI!(T){
    /// goes to the next element
    T next();
    /// true if the iterator is at then
    bool atEnd();
    /// might make opApply parallel (if the work amount is larger than
    /// optimalChunkSize, tries to subdivide it in chunks of that size)
    ForeachableI!(T) parallelLoop(size_t optimalChunkSize);
    /// might make opApply parallel.
    ForeachableI!(T) parallelLoop();
}

/// description of an object, safe even if null
Print!(char) writeDesc(T,S...)(T obj, Print!(char) s,S args){
    if (obj is null) {
        return s("<")(T.stringof)(" *NULL*>").newline;
    } else {
        static if(is(typeof(obj.desc(s,args)))){
            return obj.desc(s,args);
        } else static if (is(typeof(obj.toString()))){
            return s(obj.toString());
        }else{
            // static assert(nArgs!(S)==0,"did not find method desc(Print!(char),"~S.stringof~") in "~T.stringof);
            return s(obj);
        }
    }
}