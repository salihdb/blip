/// atomic singly linked list ops
/// at the moment it works on any type that builds a liked list using a field called next
/// T is supposed to be a pointer to an element of the linked list.
///
/// Make this also as template with user given next field? would need mixins...
///
/// author: fawzi
/// license: apache 2.0
module blip.container.AtomicSLink;
import blip.sync.Atomic: atomicOp,memoryBarrier;

/// inserts newHead before head, and returns the value at head when the insertion took place
T insertAt(T)(ref T head,T newHead){
    static if(is(typeof(newHead is null))){
        assert(!(newHead is null),"cannot add a null head");
    }
    return atomicOp(head,delegate T(T val){
        newHead.next=val;
        memoryBarrier!(false,false,false,true)();
        return newHead;
    });
}

/// removes one element from the top of list
T popFrom(T)(ref T list){
    return atomicOp(list,delegate T(T val){ return ((val is null)?null:val.next); });
}