/// adds serialization support using xpose magic (deprecated)
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
module blip.serialization.SerializationExpose;
import blip.serialization.SerializationBase;
import blip.Comp;
version(Xpose){
    import xf.xpose.Expose;
    public alias xf.xpose.Expose.expose expose;
    public alias xf.xpose.Expose.attribsContain attribsContain;
    public alias xf.xpose.Expose.attribsGet attribsGet;
    public import xf.xpose.Utils;

    template NewSerializationExpose_mix0() {
        static string begin(string target) {
            return `
            static ClassMetaInfo serializationMetaInfo;
        
            ClassMetaInfo getSerializationMetaInfo() {
                return serializationMetaInfo;
            }

            /* private template SerializationInitializerMix() { */
                static this() {
                    alias `~("" == target ? `UnrefType!(typeof(this))` : target)~` TargetType;
                    serializationMetaInfo=ClassMetaInfo.createForType!(TargetType)();
                    static if(!is(TargetType==UnrefType!(typeof(this)))){
                        serializationMetaInfo.externalHandlers=new ExternalSerializationHandlers;
                        serializationMetaInfo.externalHandlers.serialize=&serializeFunction;
                    }
                
                    serializationGatherFieldInfo(serializationMetaInfo);
                }
            /*}*/

            protected static void serializationGatherFieldInfo(ClassMetaInfo serializationMetaInfo) {`;
        }
    
    
        static string end(string target) {
            return `}  /* mixin SerializationInitializerMix;*/ `;
        }
    
    
        static string method(string target, string name, string rename, string overload, string attribs) {
            return "pragma(msg,`method(target: '"~target~"' name: '"~name~"' rename: '"~rename~"' overload: '"~overload~"' attribs: '"~attribs~"')8`);\n";
        }
    
        static string field(string target, string name, string rename, bool readOnly, string attribs) {
            string res="";
            if (rename.length==0) rename=name;
            string fieldN="field_"~rename;
            string type=attribsGet(attribs,"type");
            string indent="    ";
            res~=indent~"{\n";
            res~=indent~"    alias "~(target.length>0?target:"UnrefType!(typeof(this))")~" TType;\n";
            string fType=attribsGet(attribs,"type");
            if (fType.length>0){
                res~=indent~"    alias "~fType~" FType;\n";
            } else {
                res~=indent~"    TType tt;alias typeof(tt."~name~") FType;\n";
            }
            if (attribsContain(`~"`"~attribs~"`"~`, "no-serial"))
                res~=indent~"    auto sLevel=SerializationLevel.never;\n";
            else {
                res~=indent~"    static if (is(typeof(*FType))&& (! isArrayType!(FType)) && !(is(typeof(*FType)==class)||is(typeof(*FType)==struct)||is(typeof(*FType) U== U[]))){\n";
                res~=indent~"        auto sLevel=SerializationLevel.debugLevel;\n";
                res~=indent~"    } else {\n";
                res~=indent~"        auto sLevel=SerializationLevel.normalLevel;\n";
                res~=indent~"    }\n";
            }
            string doc=attribsGet(attribs,"doc");
            string citeList=attribsGet(attribs,"cites");
            res~=indent~"    serializationMetaInfo.addFieldOfType!(FType)(`"~rename~"`,`"
                ~doc~"`,`"~citeList~"`,sLevel);\n";
            res~=indent~"}\n";
            return res;
        }
    }


    template NewSerializationExpose_mix1() {
        static string begin(string target) {
            if (target.length==0) target=`UnrefType!(typeof(this))`;
            return
            `
            static if (is(`~target~` == UnrefType!(typeof(this)))) {
                static if (is(`~target~` == class)){
                    alias typeof(super) SuperType;
                    static if (!is(typeof(SuperType.init.preSerialize(Serializer.init)))) {
                        void preSerialize(Serializer s){ }
                    }
                    static if (!is(typeof(SuperType.init.postSerialize(Serializer.init)))) {
                        void postSerialize(Serializer s){ }
                    }
                    static if (!is(typeof(SuperType.init.preUnserialize(Unserializer.init)))) {
                        typeof(this) preUnserialize(Unserializer s){ return this; }
                    }
                    static if (!is(typeof(SuperType.init.postUnserialize(Unserializer.init)))) {
                        typeof(this) postUnserialize(Unserializer s){ return this; }
                    }
                    void serialize(Serializer s){
                        static if (is(typeof(SuperType.init.serialize(s)))){
                            super.serialize(s);
                        }
                        serializeFunction(s,serializationMetaInfo,cast(void*)this);
                    }
                    void unserialize(Unserializer s){
                        static if (is(typeof(SuperType.init.unserialize(s)))){
                            super.unserialize(s);
                        }
                        unserializeFunction(s,serializationMetaInfo,cast(void*)this);
                    }
                } else static if (is(`~target~` == struct)) {
                    void serialize(Serializer s){
                        serializeFunction(s,serializationMetaInfo,cast(void*)this);
                    }
                    void unserialize(Unserializer s){
                        unserializeFunction(s,serializationMetaInfo,cast(void*)this);
                    }
                }
            } else static if (is(`~target~` == class)){
                static if (is(`~target~` SuperTuple1==super)){
                    private void dummyFunctionToTest(){
                        foreach(SuperType;SuperTuple1){
                            static if (is(SuperType==class)){
                                static if (is(typeof(SuperType.init.serialize(Serializer.init)))||
                                    is(typeof(SuperType.init.unserialize(Unserializer.init)))){
                                        static assert(0,"serialization in subclasses of types that implement methods to serialize have to be impemented inside the subclasses, not outside");
                                }
                            }
                        }
                    }
                }
            }
                
            static void serializeFunction(Serializer serializer, ClassMetaInfo metaInfo, void* _this) {
                assert(metaInfo is serializationMetaInfo);
                static if (is(`~target~` SuperTuple==super)){
                    foreach (SuperType;SuperTuple){
                        static if (is(SuperType==class)){
                            static if (!is(typeof(SuperType.init.serialize(serializer)))){
                                if (metaInfo.superMeta !is null &&
                                    metaInfo.superMeta.externalHandlers !is null){
                                    assert(metaInfo.superMeta.externalHandlers.serialize !is null,
                                        "null externalHandlers.serialize for class "~metaInfo.superMeta.className~"("~SuperType.stringof~")");
                                    metaInfo.superMeta.externalHandlers.serialize(serializer,metaInfo.superMeta,_this);
                                }
                            }
                        }
                    }
                }
                serializeThis(serializer,metaInfo,_this);
            }

            static void unserializeFunction(Unserializer serializer, ClassMetaInfo metaInfo, void* _this) {
                assert(metaInfo is serializationMetaInfo);
                static if (is(`~target~` SuperTuple==super)){
                    foreach (SuperType;SuperTuple){
                        static if (is(SuperType==class)){
                            static if (!is(typeof(SuperType.init.unserialize(serializer)))){
                                if (metaInfo.superMeta !is null &&
                                    metaInfo.superMeta.externalHandlers !is null){
                                    assert(metaInfo.superMeta.externalHandlers.unserialize !is null,
                                        "null externalHandlers.unserialize for class "~metaInfo.superMeta.className~"("~SuperType.stringof~")");
                                    metaInfo.superMeta.externalHandlers.unserialize(serializer,metaInfo.superMeta,_this);
                                }
                            }
                        }
                    }
                }
                serializeThis(serializer,metaInfo,_this);
            }
        
            static void serializeThis(SerializerType)(SerializerType serializer, ClassMetaInfo metaInfo, void* _this){
                int fieldIndex=0;
    `;
        }
    
    
        static string end(string target) {
            return ` }`;
        }
    
    
        static string method(string target, string name, string rename, string overload, string attribs) {
            return ``;
        }
    
        static string field(string target, string name, string rename, bool readOnly, string attribs) {
            if (rename.length==0) rename=name;
            string fieldN="field_"~rename;
            string prefix = "" == target ? "(cast(typeof(this))_this)." : `(cast(RefType!(`~target~`))_this).`;
            string res=`
            {
                FieldMetaInfo *fieldMeta=serializationMetaInfo[fieldIndex];
                serializer.field(fieldMeta,`~prefix~name~`);
                ++fieldIndex;
            }
            `;
            return res;
        }

    }

    struct NewSerializationExpose {
    	template handler(int i : 0) {
    		mixin NewSerializationExpose_mix0;
    	}

    	template handler(int i : 1) {
    		mixin NewSerializationExpose_mix1;
    	}
	
    	mixin HandlerStructMix;
    }
}